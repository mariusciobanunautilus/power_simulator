/*
 * Power Simulator
 * Transform March 2026 PZU prices into core.market_price
 *
 * Source workbook:
 *   sheet: Martie
 *   nominal block: B177:AF200
 *
 * Source geometry:
 *   calendar days = 1..31
 *   hour rows      = 1..24
 *
 * Spring DST behaviour:
 *   2026-03-29 contains only 23 physical settlement hours.
 *
 *   The workbook expresses this directly:
 *     Martie!AD180 is absent
 *
 *   Therefore:
 *     nominal matrix size = 31 × 24 = 744
 *     populated source cells = 743
 *
 * Expected source cells:
 *   743
 *
 * Canonical temporal mapping:
 *   docs/dst-source-to-settlement-mapping.md
 *
 * No synthetic hour is permitted. Every populated workbook cell
 * must resolve to exactly one core.settlement_interval.
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
 * Do not silently overwrite already-loaded March PZU prices.
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
          and si.local_date >= date '2026-03-01'
          and si.local_date < date '2026-04-01'
    ) then
        raise exception
            'March 2026 PZU prices already exist for run_id = 1. Transformation aborted.';
    end if;

end
$$;


/*
 * ============================================================
 * BUILD SOURCE → SETTLEMENT MAPPING
 * ============================================================
 *
 * Workbook coordinates provide:
 *
 *   day column  -> row 176 header
 *   hour row    -> column A header
 *
 * The source contains no Martie!AD180 cell:
 *
 *   local date       = 2026-03-29
 *   local hour label = 4
 *
 * This is correct spring-DST source behaviour.
 *
 * We do NOT generate that missing source row.
 *
 * Mapping is permitted only when exactly one physical settlement
 * interval exists for the populated source local date/hour.
 */

create temporary table tmp_pzu_march_map
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
      and sc.sheet_name = 'Martie'
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
            3,
            pc.day_of_month
        ) as local_date,

        (
            select count(*)
            from core.settlement_interval si
            where si.market_code = 'RO'
              and si.local_date = make_date(
                    2026,
                    3,
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
                    3,
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
    v_dst_gap_source_rows integer;
    v_dst_gap_physical_rows integer;
    v_dst_day_source_rows integer;
    v_dst_day_physical_rows integer;
begin

    /*
     * Source geometry.
     *
     * 31 × 24 nominal cells minus the nonexistent spring-DST
     * hour = 743 source observations.
     */

    select count(*)
    into v_source_rows
    from tmp_pzu_march_map;


    if v_source_rows <> 743 then
        raise exception
            'Expected 743 March PZU source cells, found %.',
            v_source_rows;
    end if;


    /*
     * Every populated value must be numeric.
     */

    select count(*)
    into v_numeric_rows
    from tmp_pzu_march_map
    where value_text ~ '^-?[0-9]+([.][0-9]+)?$';


    if v_numeric_rows <> 743 then
        raise exception
            'Expected 743 numeric March PZU source values, found %.',
            v_numeric_rows;
    end if;


    /*
     * Source values must be direct observations, not formulas.
     */

    select count(*)
    into v_formula_rows
    from raw.source_cell sc

    join tmp_pzu_march_map m
      on m.source_cell_id = sc.source_cell_id

    where sc.formula_text is not null;


    if v_formula_rows <> 0 then
        raise exception
            'Expected zero formula cells in March PZU source block, found %.',
            v_formula_rows;
    end if;


    /*
     * Explicitly verify the spring-DST source gap.
     *
     * There must be no source row for:
     *
     *   2026-03-29
     *   local_hour_label = 4
     */

    select count(*)
    into v_dst_gap_source_rows
    from tmp_pzu_march_map
    where local_date = date '2026-03-29'
      and local_hour_label = 4;


    if v_dst_gap_source_rows <> 0 then
        raise exception
            'Expected no March PZU source row for 2026-03-29 hour 4, found %.',
            v_dst_gap_source_rows;
    end if;


    /*
     * The physical settlement calendar must also contain no
     * interval for this nonexistent local hour.
     */

    select count(*)
    into v_dst_gap_physical_rows
    from core.settlement_interval
    where market_code = 'RO'
      and local_date = date '2026-03-29'
      and local_hour_label = 4;


    if v_dst_gap_physical_rows <> 0 then
        raise exception
            'Expected no physical settlement interval for 2026-03-29 hour 4, found %.',
            v_dst_gap_physical_rows;
    end if;


    /*
     * The DST transition day must contain exactly 23 populated
     * source observations.
     */

    select count(*)
    into v_dst_day_source_rows
    from tmp_pzu_march_map
    where local_date = date '2026-03-29';


    if v_dst_day_source_rows <> 23 then
        raise exception
            'Expected 23 March PZU source rows for 2026-03-29, found %.',
            v_dst_day_source_rows;
    end if;


    /*
     * The canonical settlement calendar must contain exactly
     * 23 physical hours on that same local date.
     */

    select count(*)
    into v_dst_day_physical_rows
    from core.settlement_interval
    where market_code = 'RO'
      and local_date = date '2026-03-29';


    if v_dst_day_physical_rows <> 23 then
        raise exception
            'Expected 23 physical settlement intervals for 2026-03-29, found %.',
            v_dst_day_physical_rows;
    end if;


    /*
     * Canonical DST-safe mapping requirement:
     * every populated source cell must resolve to exactly one
     * physical interval.
     */

    select count(*)
    into v_unique_rows
    from tmp_pzu_march_map
    where candidate_count = 1;


    if v_unique_rows <> 743 then
        raise exception
            'Expected 743 uniquely mapped March PZU source cells, found %.',
            v_unique_rows;
    end if;


    select count(*)
    into v_zero_candidate_rows
    from tmp_pzu_march_map
    where candidate_count = 0;


    if v_zero_candidate_rows <> 0 then
        raise exception
            'Found % March PZU source cells with no physical settlement interval.',
            v_zero_candidate_rows;
    end if;


    select count(*)
    into v_ambiguous_rows
    from tmp_pzu_march_map
    where candidate_count > 1;


    if v_ambiguous_rows <> 0 then
        raise exception
            'Found % March PZU source cells with ambiguous physical settlement intervals.',
            v_ambiguous_rows;
    end if;


    select count(*)
    into v_null_interval_rows
    from tmp_pzu_march_map
    where interval_id is null;


    if v_null_interval_rows <> 0 then
        raise exception
            'Found % March PZU source cells without interval_id.',
            v_null_interval_rows;
    end if;


    /*
     * Every populated source cell must resolve to a distinct
     * physical interval.
     */

    select count(*)
    into v_duplicate_interval_rows

    from (
        select interval_id
        from tmp_pzu_march_map
        group by interval_id
        having count(*) <> 1
    ) d;


    if v_duplicate_interval_rows <> 0 then
        raise exception
            'Found % duplicate March PZU settlement interval mappings.',
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

from tmp_pzu_march_map m

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
    v_dst_loaded_rows integer;
    v_synthetic_gap_rows integer;
    v_min_price numeric;
    v_max_price numeric;
begin

    select
        count(*),

        count(*) filter (
            where mp.record_status = 'unclassified'
        ),

        count(mp.source_cell_id),

        count(
            distinct mp.source_cell_id
        ),

        count(
            distinct mp.interval_id
        ),

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
      and si.local_date >= date '2026-03-01'
      and si.local_date < date '2026-04-01';


    if v_loaded_rows <> 743 then
        raise exception
            'Expected 743 March PZU market-price rows, found %.',
            v_loaded_rows;
    end if;


    if v_unclassified_rows <> 743 then
        raise exception
            'Expected all 743 March PZU rows to be unclassified, found %.',
            v_unclassified_rows;
    end if;


    if v_lineage_rows <> 743 then
        raise exception
            'Expected source_cell_id on all 743 March PZU rows, found %.',
            v_lineage_rows;
    end if;


    if v_distinct_source_cells <> 743 then
        raise exception
            'Expected 743 distinct March PZU source_cell_id values, found %.',
            v_distinct_source_cells;
    end if;


    if v_distinct_intervals <> 743 then
        raise exception
            'Expected 743 distinct March PZU settlement intervals, found %.',
            v_distinct_intervals;
    end if;


    /*
     * Verify the DST day itself contains exactly 23 loaded prices.
     */

    select count(*)
    into v_dst_loaded_rows
    from core.market_price mp

    join core.settlement_interval si
      on si.interval_id = mp.interval_id

    where mp.run_id = 1
      and mp.market_code = 'PZU'
      and si.market_code = 'RO'
      and si.local_date = date '2026-03-29';


    if v_dst_loaded_rows <> 23 then
        raise exception
            'Expected 23 loaded PZU prices for 2026-03-29, found %.',
            v_dst_loaded_rows;
    end if;


    /*
     * Explicitly prove that no synthetic hour-4 record was created.
     */

    select count(*)
    into v_synthetic_gap_rows
    from core.market_price mp

    join core.settlement_interval si
      on si.interval_id = mp.interval_id

    where mp.run_id = 1
      and mp.market_code = 'PZU'
      and si.market_code = 'RO'
      and si.local_date = date '2026-03-29'
      and si.local_hour_label = 4;


    if v_synthetic_gap_rows <> 0 then
        raise exception
            'Found % synthetic PZU rows for nonexistent 2026-03-29 hour 4.',
            v_synthetic_gap_rows;
    end if;


    /*
     * Source-backed price range.
     *
     * Negative market prices are valid observations and must not
     * be normalized or rejected.
     */

    if v_min_price <> (-20.64)::numeric then
        raise exception
            'Unexpected March PZU minimum price: expected -20.64, found %.',
            v_min_price;
    end if;


    if v_max_price <> 1437.96::numeric then
        raise exception
            'Unexpected March PZU maximum price: expected 1437.96, found %.',
            v_max_price;
    end if;

end
$$;


commit;


/*
 * ============================================================
 * RESULT PREVIEW: DST DAY
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
  and si.local_date = date '2026-03-29'

order by
    si.interval_start_utc;


/*
 * ============================================================
 * SUMMARY
 * ============================================================
 */

select
    count(*) as march_pzu_rows,
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
  and si.local_date >= date '2026-03-01'
  and si.local_date < date '2026-04-01';