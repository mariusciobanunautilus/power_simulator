/*
 * Power Simulator
 * Transform workbook balancing assumptions into core.balancing_month
 *
 * Source:
 *   raw.source_cell
 *   workbook sheet: Asumptions
 *   rows: 4-15
 *
 * Mapping:
 *   O = month label
 *   P = deficit MWh
 *   Q = deficit RON/MWh
 *   R = excess MWh
 *   S = excess RON/MWh
 *   U = redistribution income RON
 *
 * Column T is intentionally NOT loaded because it is calculated
 * from the underlying inputs and belongs in the calculation layer.
 *
 * Record-status rule:
 *   The workbook does not contain an authoritative actual/forecast
 *   indicator for these balancing observations.
 *
 *   Therefore every imported balancing row is stored as:
 *
 *       record_status = 'unclassified'
 *
 *   Status MUST NOT be inferred from:
 *     - core.model_run.as_of_utc
 *     - calendar month
 *     - workbook formatting
 *     - whether a value appears historical or forecast-like
 *
 *   A future authoritative source may explicitly classify records
 *   as actual, forecast or manual_override.
 *
 * Lineage rule:
 *   Explicit workbook cells receive source-cell lineage.
 *
 *   September-December contain no source cells in column U.
 *   Their redistribution_income_ron values therefore default to 0
 *   during transformation and deliberately have no artificial
 *   source-cell lineage.
 *
 * Run:
 *   core.model_run.run_id = 1
 */


begin;


/*
 * ============================================================
 * SAFETY GUARD
 * ============================================================
 *
 * Do not silently overwrite an already transformed model run.
 */

do $$
begin

    if exists (
        select 1
        from core.balancing_month
        where run_id = 1
    ) then
        raise exception
            'core.balancing_month already contains data for run_id = 1. Transformation aborted.';
    end if;


    if exists (
        select 1
        from core.balancing_month_lineage
        where run_id = 1
    ) then
        raise exception
            'core.balancing_month_lineage already contains data for run_id = 1. Transformation aborted.';
    end if;

end
$$;


/*
 * ============================================================
 * SOURCE-EVIDENCE VALIDATION
 * ============================================================
 *
 * Verified workbook evidence:
 *
 *   O month label                    12
 *   P deficit MWh                    12
 *   Q deficit RON/MWh                12
 *   R excess MWh                     12
 *   S excess RON/MWh                 12
 *   U redistribution income RON       8
 *
 * Total explicit source cells:        68
 */

do $$
declare
    v_o integer;
    v_p integer;
    v_q integer;
    v_r integer;
    v_s integer;
    v_u integer;
    v_total integer;
begin

    select
        count(*) filter (
            where regexp_replace(cell_address, '\d', '', 'g') = 'O'
        ),
        count(*) filter (
            where regexp_replace(cell_address, '\d', '', 'g') = 'P'
        ),
        count(*) filter (
            where regexp_replace(cell_address, '\d', '', 'g') = 'Q'
        ),
        count(*) filter (
            where regexp_replace(cell_address, '\d', '', 'g') = 'R'
        ),
        count(*) filter (
            where regexp_replace(cell_address, '\d', '', 'g') = 'S'
        ),
        count(*) filter (
            where regexp_replace(cell_address, '\d', '', 'g') = 'U'
        ),
        count(*)
    into
        v_o,
        v_p,
        v_q,
        v_r,
        v_s,
        v_u,
        v_total
    from raw.source_cell
    where source_file_id = 1
      and sheet_name = 'Asumptions'
      and cell_address ~ '^(O|P|Q|R|S|U)([4-9]|1[0-5])$';


    if v_o <> 12 then
        raise exception
            'Expected 12 month-label source cells in column O, found %.',
            v_o;
    end if;


    if v_p <> 12 then
        raise exception
            'Expected 12 deficit-MWh source cells in column P, found %.',
            v_p;
    end if;


    if v_q <> 12 then
        raise exception
            'Expected 12 deficit-price source cells in column Q, found %.',
            v_q;
    end if;


    if v_r <> 12 then
        raise exception
            'Expected 12 excess-MWh source cells in column R, found %.',
            v_r;
    end if;


    if v_s <> 12 then
        raise exception
            'Expected 12 excess-price source cells in column S, found %.',
            v_s;
    end if;


    if v_u <> 8 then
        raise exception
            'Expected 8 redistribution-income source cells in column U, found %.',
            v_u;
    end if;


    if v_total <> 68 then
        raise exception
            'Expected 68 balancing source cells in total, found %.',
            v_total;
    end if;

end
$$;


/*
 * ============================================================
 * LOAD MONTHLY BALANCING FACTS
 * ============================================================
 */

with source_cells as (
    select
        sc.source_cell_id,
        sc.cell_address,

        regexp_replace(
            sc.cell_address,
            '\D',
            '',
            'g'
        )::integer as row_no,

        regexp_replace(
            sc.cell_address,
            '\d',
            '',
            'g'
        ) as column_code,

        coalesce(
            sc.cached_text,
            sc.raw_text
        ) as value_text

    from raw.source_cell sc

    where sc.source_file_id = 1
      and sc.sheet_name = 'Asumptions'
      and sc.cell_address ~ '^(O|P|Q|R|S|U)([4-9]|1[0-5])$'
),

pivoted as (
    select
        row_no,

        max(value_text)
            filter (
                where column_code = 'O'
            ) as month_label,

        max(value_text)
            filter (
                where column_code = 'P'
            )::numeric as deficit_mwh,

        max(value_text)
            filter (
                where column_code = 'Q'
            )::numeric as deficit_ron_per_mwh,

        max(value_text)
            filter (
                where column_code = 'R'
            )::numeric as excess_mwh,

        max(value_text)
            filter (
                where column_code = 'S'
            )::numeric as excess_ron_per_mwh,

        coalesce(
            max(value_text)
                filter (
                    where column_code = 'U'
                )::numeric,
            0
        ) as redistribution_income_ron

    from source_cells

    group by row_no
),

prepared as (
    select
        mr.run_id,

        make_date(
            mr.model_year,
            p.row_no - 3,
            1
        ) as month_start,

        p.month_label,
        p.deficit_mwh,
        p.deficit_ron_per_mwh,
        p.excess_mwh,
        p.excess_ron_per_mwh,
        p.redistribution_income_ron,

        /*
         * No authoritative actual/forecast classification exists
         * in the workbook source.
         */
        'unclassified' as record_status

    from pivoted p

    cross join core.model_run mr

    where mr.run_id = 1
)

insert into core.balancing_month (
    run_id,
    month_start,
    deficit_mwh,
    deficit_ron_per_mwh,
    excess_mwh,
    excess_ron_per_mwh,
    redistribution_income_ron,
    record_status,
    source_cell_id
)

select
    run_id,
    month_start,
    deficit_mwh,
    deficit_ron_per_mwh,
    excess_mwh,
    excess_ron_per_mwh,
    redistribution_income_ron,
    record_status,

    /*
     * Multiple workbook cells contribute to each monthly record.
     * Field-level provenance is therefore stored in
     * core.balancing_month_lineage.
     */
    null as source_cell_id

from prepared

order by month_start;


/*
 * ============================================================
 * LOAD FIELD-LEVEL SOURCE LINEAGE
 * ============================================================
 */

with source_cells as (
    select
        sc.source_cell_id,

        regexp_replace(
            sc.cell_address,
            '\D',
            '',
            'g'
        )::integer as row_no,

        regexp_replace(
            sc.cell_address,
            '\d',
            '',
            'g'
        ) as column_code

    from raw.source_cell sc

    where sc.source_file_id = 1
      and sc.sheet_name = 'Asumptions'
      and sc.cell_address ~ '^(O|P|Q|R|S|U)([4-9]|1[0-5])$'
),

prepared as (
    select
        mr.run_id,

        make_date(
            mr.model_year,
            sc.row_no - 3,
            1
        ) as month_start,

        case sc.column_code
            when 'O'
                then 'month_label'

            when 'P'
                then 'deficit_mwh'

            when 'Q'
                then 'deficit_ron_per_mwh'

            when 'R'
                then 'excess_mwh'

            when 'S'
                then 'excess_ron_per_mwh'

            when 'U'
                then 'redistribution_income_ron'
        end as source_role,

        sc.source_cell_id

    from source_cells sc

    cross join core.model_run mr

    where mr.run_id = 1
)

insert into core.balancing_month_lineage (
    run_id,
    month_start,
    source_role,
    source_cell_id
)

select
    run_id,
    month_start,
    source_role,
    source_cell_id

from prepared

where source_role is not null

order by
    month_start,
    source_role;


/*
 * ============================================================
 * VALIDATION
 * ============================================================
 *
 * Expected:
 *
 *   12 balancing months
 *
 *   68 source-lineage records:
 *
 *     month_label                    12
 *     deficit_mwh                    12
 *     deficit_ron_per_mwh            12
 *     excess_mwh                     12
 *     excess_ron_per_mwh             12
 *     redistribution_income_ron       8
 *                                    --
 *                                    68
 *
 * September-December have no source cells in column U.
 * Their redistribution_income_ron = 0 values are normalized
 * defaults produced by this transformation and therefore do not
 * receive fabricated source-cell lineage.
 *
 * Every balancing row must be unclassified because no
 * authoritative actual/forecast source exists in the workbook.
 */

do $$
declare
    balancing_rows integer;
    lineage_rows integer;
    redistribution_lineage_rows integer;
    unsupported_status_rows integer;
begin

    select count(*)
    into balancing_rows
    from core.balancing_month
    where run_id = 1;


    if balancing_rows <> 12 then
        raise exception
            'Expected 12 balancing months for run_id = 1, found %.',
            balancing_rows;
    end if;


    select count(*)
    into lineage_rows
    from core.balancing_month_lineage
    where run_id = 1;


    if lineage_rows <> 68 then
        raise exception
            'Expected 68 balancing lineage rows for run_id = 1, found %.',
            lineage_rows;
    end if;


    select count(*)
    into redistribution_lineage_rows
    from core.balancing_month_lineage
    where run_id = 1
      and source_role = 'redistribution_income_ron';


    if redistribution_lineage_rows <> 8 then
        raise exception
            'Expected 8 redistribution_income_ron lineage rows for run_id = 1, found %.',
            redistribution_lineage_rows;
    end if;


    select count(*)
    into unsupported_status_rows
    from core.balancing_month
    where run_id = 1
      and record_status <> 'unclassified';


    if unsupported_status_rows <> 0 then
        raise exception
            'Expected all balancing rows to have record_status = unclassified; found % rows with another status.',
            unsupported_status_rows;
    end if;

end
$$;


/*
 * ============================================================
 * COMMIT
 * ============================================================
 */

commit;


/*
 * ============================================================
 * RESULT PREVIEW
 * ============================================================
 */

select
    bm.month_start,
    bm.deficit_mwh,
    bm.deficit_ron_per_mwh,
    bm.excess_mwh,
    bm.excess_ron_per_mwh,
    bm.redistribution_income_ron,
    bm.record_status,

    (
        select count(*)
        from core.balancing_month_lineage bml
        where bml.run_id = bm.run_id
          and bml.month_start = bm.month_start
    ) as lineage_cells

from core.balancing_month bm

where bm.run_id = 1

order by bm.month_start;


select
    source_role,
    count(*) as lineage_rows
from core.balancing_month_lineage
where run_id = 1
group by source_role
order by source_role;