/*
 * Power Simulator
 * Transform January 2026 PZU prices into core.market_price
 *
 * Source workbook:
 *   sheet: Ianuarie
 *   block: B177:AF200
 *
 * Source geometry:
 *   columns B:AF   = calendar days 1..31
 *   rows 177:200  = local hour labels 1..24
 *
 * Expected source cells:
 *   31 days × 24 hours = 744
 *
 * Canonical temporal mapping:
 *   docs/dst-source-to-settlement-mapping.md
 *
 * January 2026 contains no DST transition, therefore every
 * source cell must resolve to exactly one core.settlement_interval.
 *
 * Market:
 *   market_code   = PZU
 *   currency_code = RON
 *
 * Record status:
 *   The workbook does not authoritatively classify these prices
 *   as actual or forecast.
 *
 *   record_status = 'unclassified'
 *
 * Lineage:
 *   Every inserted market-price row preserves its original
 *   raw.source_cell.source_cell_id.
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
 * Do not silently overwrite already-loaded January PZU prices.
 */

do $$
begin

    if exists (
        select 1
        from core.market_price mp

        join core.settlement_interval si
          on si.interval_id = mp.interval_id

        where mp.run_id = 1
          and mp.market_code = 'PZU'
          and si.market_code = 'RO'
          and si.local_date >= date '2026-01-01'
          and si.local_date < date '2026-02-01'
    ) then
        raise exception
            'January 2026 PZU prices already exist for run_id = 1. Transformation aborted.';
    end if;

end
$$;


/*
 * ============================================================
 * BUILD SOURCE → SETTLEMENT MAPPING
 * ============================================================
 *
 * The workbook coordinates provide:
 *
 *   day column  -> row 176 header
 *   hour row    -> column A header
 *
 * Candidate count is calculated before insertion.
 *
 * Mapping is permitted only when exactly one physical settlement
 * interval exists for the source local date/hour.
 */

create temporary table tmp_pzu_january_map
on commit drop
as

with price_cells as (

    select
        sc.source_cell_id,
        sc.cell_address,

        coalesce(
            sc.cached_text,
            sc.raw_text
        ) as value_text,

        day_header.raw_text::integer
            as day_of_month,

        hour_header.raw_text::integer
            as local_hour_label

    from raw.source_cell sc

    join raw.source_cell day_header
      on day_header.source_file_id = sc.source_file_id
     and day_header.sheet_name = sc.sheet_name
     and day_header.cell_address =
            regexp_replace(
                sc.cell_address,
                '[0-9]',
                '',
                'g'
            ) || '176'

    join raw.source_cell hour_header
      on hour_header.source_file_id = sc.source_file_id
     and hour_header.sheet_name = sc.sheet_name
     and hour_header.cell_address =
            'A' ||
            regexp_replace(
                sc.cell_address,
                '[^0-9]',
                '',
                'g'
            )

    where sc.source_file_id = 1
      and sc.sheet_name = 'Ianuarie'
      and sc.cell_address ~
            '^(?:[B-Z]|A[A-F])(?:17[7-9]|18[0-9]|19[0-9]|200)$'
),

mapped as (

    select
        pc.source_cell_id,
        pc.cell_address,
        pc.value_text,
        pc.day_of_month,
        pc.local_hour_label,

        make_date(
            2026,
            1,
            pc.day_of_month
        ) as local_date,

        (
            select count(*)
            from core.settlement_interval si
            where si.market_code = 'RO'
              and si.local_date = make_date(
                    2026,
                    1,
                    pc.day_of_month
                  )
              and si.local_hour_label = pc.local_hour_label
        ) as candidate_count,

        (
            select min(si.interval_id)
            from core.settlement_interval si
            where si.market_code = 'RO'
              and si.local_date = make_date(
                    2026,
                    1,
                    pc.day_of_month
                  )
              and si.local_hour_label = pc.local_hour_label
        ) as interval_id

    from price_cells pc

)

select
    source_cell_id,
    cell_address,
    value_text,
    day_of_month,
    local_hour_label,
    local_date,
    candidate_count,
    interval_id

from mapped;


/*
 * ============================================================
 * SOURCE AND MAPPING VALIDATION
 * ============================================================
 */

do $$
declare
    v_source_rows integer;
    v_numeric_rows integer;
    v_formula_rows integer;
    v_unique_rows integer;
    v_zero_candidate_rows integer;
    v_ambiguous_rows integer;
    v_null_interval_rows integer;
    v_duplicate_interval_rows integer;
begin

    /*
     * Source geometry
     */

    select count(*)
    into v_source_rows
    from tmp_pzu_january_map;


    if v_source_rows <> 744 then
        raise exception
            'Expected 744 January PZU source cells, found %.',
            v_source_rows;
    end if;


    /*
     * Every value must be numeric.
     */

    select count(*)
    into v_numeric_rows
    from tmp_pzu_january_map
    where value_text ~ '^-?[0-9]+([.][0-9]+)?$';


    if v_numeric_rows <> 744 then
        raise exception
            'Expected 744 numeric January PZU source values, found %.',
            v_numeric_rows;
    end if;


    /*
     * Source values must be direct observations, not formulas.
     */

    select count(*)
    into v_formula_rows
    from raw.source_cell sc

    join tmp_pzu_january_map m
      on m.source_cell_id = sc.source_cell_id

    where sc.formula_text is not null;


    if v_formula_rows <> 0 then
        raise exception
            'Expected zero formula cells in January PZU source block, found %.',
            v_formula_rows;
    end if;


    /*
     * Canonical DST-safe mapping requirement:
     * exactly one physical interval per source cell.
     */

    select count(*)
    into v_unique_rows
    from tmp_pzu_january_map
    where candidate_count = 1;


    if v_unique_rows <> 744 then
        raise exception
            'Expected 744 uniquely mapped January PZU source cells, found %.',
            v_unique_rows;
    end if;


    select count(*)
    into v_zero_candidate_rows
    from tmp_pzu_january_map
    where candidate_count = 0;


    if v_zero_candidate_rows <> 0 then
        raise exception
            'Found % January PZU source cells with no physical settlement interval.',
            v_zero_candidate_rows;
    end if;


    select count(*)
    into v_ambiguous_rows
    from tmp_pzu_january_map
    where candidate_count > 1;


    if v_ambiguous_rows <> 0 then
        raise exception
            'Found % January PZU source cells with ambiguous physical settlement intervals.',
            v_ambiguous_rows;
    end if;


    select count(*)
    into v_null_interval_rows
    from tmp_pzu_january_map
    where interval_id is null;


    if v_null_interval_rows <> 0 then
        raise exception
            'Found % January PZU source cells without interval_id.',
            v_null_interval_rows;
    end if;


    /*
     * One source cell must resolve to one unique physical interval.
     */

    select count(*)
    into v_duplicate_interval_rows

    from (
        select interval_id
        from tmp_pzu_january_map
        group by interval_id
        having count(*) <> 1
    ) d;


    if v_duplicate_interval_rows <> 0 then
        raise exception
            'Found % duplicate January PZU settlement interval mappings.',
            v_duplicate_interval_rows;
    end if;

end
$$;


/*
 * ============================================================
 * LOAD CORE MARKET PRICES
 * ============================================================
 */

insert into core.market_price (
    run_id,
    interval_id,
    market_code,
    currency_code,
    price_per_mwh,
    record_status,
    source_cell_id
)

select
    1 as run_id,
    m.interval_id,
    'PZU' as market_code,
    'RON' as currency_code,
    m.value_text::numeric as price_per_mwh,
    'unclassified' as record_status,
    m.source_cell_id

from tmp_pzu_january_map m

where m.candidate_count = 1

order by m.interval_id;


/*
 * ============================================================
 * POST-LOAD VALIDATION
 * ============================================================
 */

do $$
declare
    v_loaded_rows integer;
    v_unclassified_rows integer;
    v_lineage_rows integer;
    v_distinct_source_cells integer;
    v_distinct_intervals integer;
    v_min_price numeric;
    v_max_price numeric;
begin

    select
        count(*),
        count(*) filter (
            where mp.record_status = 'unclassified'
        ),
        count(mp.source_cell_id),
        count(distinct mp.source_cell_id),
        count(distinct mp.interval_id),
        min(mp.price_per_mwh),
        max(mp.price_per_mwh)

    into
        v_loaded_rows,
        v_unclassified_rows,
        v_lineage_rows,
        v_distinct_source_cells,
        v_distinct_intervals,
        v_min_price,
        v_max_price

    from core.market_price mp

    join core.settlement_interval si
      on si.interval_id = mp.interval_id

    where mp.run_id = 1
      and mp.market_code = 'PZU'
      and si.market_code = 'RO'
      and si.local_date >= date '2026-01-01'
      and si.local_date < date '2026-02-01';


    if v_loaded_rows <> 744 then
        raise exception
            'Expected 744 January PZU market-price rows, found %.',
            v_loaded_rows;
    end if;


    if v_unclassified_rows <> 744 then
        raise exception
            'Expected all 744 January PZU rows to be unclassified, found %.',
            v_unclassified_rows;
    end if;


    if v_lineage_rows <> 744 then
        raise exception
            'Expected source_cell_id on all 744 January PZU rows, found %.',
            v_lineage_rows;
    end if;


    if v_distinct_source_cells <> 744 then
        raise exception
            'Expected 744 distinct January PZU source_cell_id values, found %.',
            v_distinct_source_cells;
    end if;


    if v_distinct_intervals <> 744 then
        raise exception
            'Expected 744 distinct January PZU settlement intervals, found %.',
            v_distinct_intervals;
    end if;


    if v_min_price <> 131.0275::numeric then
        raise exception
            'Unexpected January PZU minimum price: expected 131.0275, found %.',
            v_min_price;
    end if;


    if v_max_price <> 2318.49::numeric then
        raise exception
            'Unexpected January PZU maximum price: expected 2318.49, found %.',
            v_max_price;
    end if;

end
$$;


commit;


/*
 * ============================================================
 * RESULT PREVIEW
 * ============================================================
 */

select
    si.local_date,
    si.local_hour_label,
    si.local_occurrence,
    si.interval_start_utc,
    mp.price_per_mwh,
    mp.currency_code,
    mp.record_status,
    mp.source_cell_id,
    sc.cell_address

from core.market_price mp

join core.settlement_interval si
  on si.interval_id = mp.interval_id

join raw.source_cell sc
  on sc.source_cell_id = mp.source_cell_id

where mp.run_id = 1
  and mp.market_code = 'PZU'
  and si.market_code = 'RO'
  and si.local_date >= date '2026-01-01'
  and si.local_date < date '2026-02-01'

order by
    si.interval_start_utc;


/*
 * ============================================================
 * SUMMARY
 * ============================================================
 */

select
    count(*) as january_pzu_rows,
    count(distinct mp.interval_id) as distinct_intervals,
    count(distinct mp.source_cell_id) as distinct_source_cells,
    min(mp.price_per_mwh) as min_price,
    max(mp.price_per_mwh) as max_price,
    min(si.local_date) as first_local_date,
    max(si.local_date) as last_local_date

from core.market_price mp

join core.settlement_interval si
  on si.interval_id = mp.interval_id

where mp.run_id = 1
  and mp.market_code = 'PZU'
  and si.market_code = 'RO'
  and si.local_date >= date '2026-01-01'
  and si.local_date < date '2026-02-01';