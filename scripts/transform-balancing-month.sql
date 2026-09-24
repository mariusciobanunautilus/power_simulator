-- Power Simulator
-- Transform workbook balancing assumptions into core.balancing_month
--
-- Source:
--   raw.source_cell
--   workbook sheet: Asumptions
--   rows: 4-15
--
-- Mapping:
--   O = month label
--   P = deficit MWh
--   Q = deficit RON/MWh
--   R = excess MWh
--   S = excess RON/MWh
--   U = redistribution income RON
--
-- Column T is intentionally NOT loaded because it is calculated
-- from the underlying inputs and belongs in the calculation layer.
--
-- Run:
--   core.model_run.run_id = 1


begin;


-- ============================================================
-- SAFETY GUARD
-- ============================================================
-- Do not silently overwrite an already transformed model run.

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
end
$$;


-- ============================================================
-- LOAD MONTHLY BALANCING FACTS
-- ============================================================

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

        case
            when make_date(
                mr.model_year,
                p.row_no - 3,
                1
            )
            <
            date_trunc(
                'month',
                mr.as_of_utc
                    at time zone 'Europe/Bucharest'
            )::date
            then 'actual'

            else 'forecast'
        end as record_status

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

    -- Multiple workbook cells contribute to each monthly record.
    -- Detailed provenance is stored in
    -- core.balancing_month_lineage.
    null as source_cell_id

from prepared

order by month_start;


-- ============================================================
-- LOAD FIELD-LEVEL SOURCE LINEAGE
-- ============================================================

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


-- ============================================================
-- VALIDATION
-- ============================================================

do $$
declare
    balancing_rows integer;
begin

    select count(*)
    into balancing_rows
    from core.balancing_month
    where run_id = 1;

    if balancing_rows <> 12 then
        raise exception
            'Expected 12 balancing months for run_id = 1, found %',
            balancing_rows;
    end if;

end
$$;


commit;


-- ============================================================
-- RESULT PREVIEW
-- ============================================================

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