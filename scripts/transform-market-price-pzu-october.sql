/*
 * Power Simulator
 * Transform October 2026 PZU prices into core.market_price.
 *
 * Source workbook:
 *   sheet: Octombrie
 *   hourly PZU matrix: rows 177:200, calendar-day columns from row 176
 *
 * Source cells: 744
 *
 * Canonical DST rule:
 *   docs/dst-source-to-settlement-mapping.md
 *
 * Autumn DST exception:
 *   2026-10-25 has 25 physical settlement intervals.
 *   The workbook provides only one source value for local hour 4:
 *
 *     Octombrie!Z180
 *     source_cell_id = 76634
 *     value          = 709.7704640775
 *
 *   That source value has two physical candidates:
 *     local_occurrence = 1
 *     local_occurrence = 2
 *
 *   It is therefore deliberately NOT loaded into core.market_price.
 *
 * Expected result:
 *   743 resolved PZU facts
 *   1 unresolved source cell
 *   2 unrepresented physical intervals (the repeated hour candidates)
 */

begin;

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
          and si.local_date >= date '2026-10-01'
          and si.local_date < date '2026-11-01'
    ) then
        raise exception
            'October 2026 PZU prices already exist for run_id = 1. Transformation aborted.';
    end if;
end
$$;

create temporary table tmp_pzu_october_map
on commit drop
as
with price_cells as (
    select
        sc.source_cell_id,
        sc.cell_address,
        sc.formula_text,
        coalesce(sc.cached_text, sc.raw_text) as value_text,
        day_header.raw_text::integer as day_of_month,
        hour_header.raw_text::integer as local_hour_label
    from raw.source_cell sc
    join raw.source_cell day_header
      on day_header.source_file_id = sc.source_file_id
     and day_header.sheet_name = sc.sheet_name
     and day_header.cell_address =
            regexp_replace(sc.cell_address, '[0-9]', '', 'g') || '176'
    join raw.source_cell hour_header
      on hour_header.source_file_id = sc.source_file_id
     and hour_header.sheet_name = sc.sheet_name
     and hour_header.cell_address =
            'A' || regexp_replace(sc.cell_address, '[^0-9]', '', 'g')
    where sc.source_file_id = 1
      and sc.sheet_name = 'Octombrie'
      and sc.cell_address ~
            '^(?:[B-Z]|A[A-F])(?:17[7-9]|18[0-9]|19[0-9]|200)$'
),
mapped as (
    select
        pc.*,
        make_date(2026, 10, pc.day_of_month) as local_date,
        (
            select count(*)
            from core.settlement_interval si
            where si.market_code = 'RO'
              and si.local_date = make_date(2026, 10, pc.day_of_month)
              and si.local_hour_label = pc.local_hour_label
        ) as candidate_count,
        (
            select min(si.interval_id)
            from core.settlement_interval si
            where si.market_code = 'RO'
              and si.local_date = make_date(2026, 10, pc.day_of_month)
              and si.local_hour_label = pc.local_hour_label
        ) as interval_id
    from price_cells pc
)
select *
from mapped;

do $$
declare
    v_source_rows integer;
    v_numeric_rows integer;
    v_formula_rows integer;
    v_unique_rows integer;
    v_zero_candidate_rows integer;
    v_ambiguous_rows integer;
    v_ambiguous_source_rows integer;
    v_physical_candidates integer;
    v_dst_source_rows integer;
    v_dst_physical_rows integer;
begin
    select count(*) into v_source_rows from tmp_pzu_october_map;
    if v_source_rows <> 744 then
        raise exception 'October: expected 744 source cells, found %.', v_source_rows;
    end if;

    select count(*) into v_numeric_rows
    from tmp_pzu_october_map
    where value_text ~ '^-?[0-9]+([.][0-9]+)?$';
    if v_numeric_rows <> 744 then
        raise exception 'October: expected 744 numeric values, found %.', v_numeric_rows;
    end if;

    select count(*) into v_formula_rows
    from tmp_pzu_october_map
    where formula_text is not null;
    if v_formula_rows <> 0 then
        raise exception 'October: expected zero formula cells, found %.', v_formula_rows;
    end if;

    select count(*) into v_unique_rows
    from tmp_pzu_october_map
    where candidate_count = 1;
    if v_unique_rows <> 743 then
        raise exception 'October: expected 743 unique mappings, found %.', v_unique_rows;
    end if;

    select count(*) into v_zero_candidate_rows
    from tmp_pzu_october_map
    where candidate_count = 0;
    if v_zero_candidate_rows <> 0 then
        raise exception 'October: found % zero-candidate mappings.', v_zero_candidate_rows;
    end if;

    select count(*) into v_ambiguous_rows
    from tmp_pzu_october_map
    where candidate_count > 1;
    if v_ambiguous_rows <> 1 then
        raise exception 'October: expected exactly 1 ambiguous mapping, found %.', v_ambiguous_rows;
    end if;

    select count(*) into v_ambiguous_source_rows
    from tmp_pzu_october_map
    where candidate_count = 2
      and source_cell_id = 76634
      and cell_address = 'Z180'
      and local_date = date '2026-10-25'
      and local_hour_label = 4
      and value_text::numeric = 709.7704640775::numeric;
    if v_ambiguous_source_rows <> 1 then
        raise exception
            'October: expected canonical ambiguous source Octombrie!Z180 exactly once.';
    end if;

    select count(*) into v_physical_candidates
    from core.settlement_interval
    where market_code = 'RO'
      and local_date = date '2026-10-25'
      and local_hour_label = 4
      and local_occurrence in (1, 2);
    if v_physical_candidates <> 2 then
        raise exception
            'October: expected 2 physical candidates for repeated hour 4, found %.',
            v_physical_candidates;
    end if;

    select count(*) into v_dst_source_rows
    from tmp_pzu_october_map
    where local_date = date '2026-10-25';
    if v_dst_source_rows <> 24 then
        raise exception
            'October: expected 24 workbook source rows on 2026-10-25, found %.',
            v_dst_source_rows;
    end if;

    select count(*) into v_dst_physical_rows
    from core.settlement_interval
    where market_code = 'RO'
      and local_date = date '2026-10-25';
    if v_dst_physical_rows <> 25 then
        raise exception
            'October: expected 25 physical intervals on 2026-10-25, found %.',
            v_dst_physical_rows;
    end if;
end
$$;

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
    1,
    interval_id,
    'PZU',
    'RON',
    value_text::numeric,
    'unclassified',
    source_cell_id
from tmp_pzu_october_map
where candidate_count = 1
order by interval_id;

do $$
declare
    v_loaded_rows integer;
    v_unclassified_rows integer;
    v_distinct_source_cells integer;
    v_distinct_intervals integer;
    v_dst_loaded_rows integer;
    v_repeated_hour_loaded_rows integer;
    v_min_price numeric;
    v_max_price numeric;
begin
    select
        count(*),
        count(*) filter (where mp.record_status = 'unclassified'),
        count(distinct mp.source_cell_id),
        count(distinct mp.interval_id),
        min(mp.price_per_mwh),
        max(mp.price_per_mwh)
    into
        v_loaded_rows,
        v_unclassified_rows,
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
      and si.local_date >= date '2026-10-01'
      and si.local_date < date '2026-11-01';

    if v_loaded_rows <> 743
       or v_unclassified_rows <> 743
       or v_distinct_source_cells <> 743
       or v_distinct_intervals <> 743 then
        raise exception
            'October: invalid post-load counts rows %, status %, sources %, intervals %.',
            v_loaded_rows, v_unclassified_rows, v_distinct_source_cells, v_distinct_intervals;
    end if;

    select count(*) into v_dst_loaded_rows
    from core.market_price mp
    join core.settlement_interval si
      on si.interval_id = mp.interval_id
    where mp.run_id = 1
      and mp.market_code = 'PZU'
      and si.local_date = date '2026-10-25';
    if v_dst_loaded_rows <> 23 then
        raise exception
            'October: expected 23 resolved PZU facts on 2026-10-25, found %.',
            v_dst_loaded_rows;
    end if;

    select count(*) into v_repeated_hour_loaded_rows
    from core.market_price mp
    join core.settlement_interval si
      on si.interval_id = mp.interval_id
    where mp.run_id = 1
      and mp.market_code = 'PZU'
      and si.local_date = date '2026-10-25'
      and si.local_hour_label = 4;
    if v_repeated_hour_loaded_rows <> 0 then
        raise exception
            'October: ambiguous repeated hour was incorrectly loaded % times.',
            v_repeated_hour_loaded_rows;
    end if;

    if v_min_price <> 375.35807017::numeric then
        raise exception
            'October: unexpected stored minimum %, expected 375.35807017.',
            v_min_price;
    end if;

    if v_max_price <> 2052.65772380::numeric then
        raise exception
            'October: unexpected stored maximum %, expected 2052.65772380.',
            v_max_price;
    end if;
end
$$;

commit;

select
    count(*) as october_pzu_rows,
    count(distinct mp.interval_id) as distinct_intervals,
    count(distinct mp.source_cell_id) as distinct_source_cells,
    count(*) filter (
        where si.local_date = date '2026-10-25'
    ) as dst_day_loaded_rows,
    count(*) filter (
        where si.local_date = date '2026-10-25'
          and si.local_hour_label = 4
    ) as repeated_hour_loaded_rows,
    min(mp.price_per_mwh) as min_price,
    max(mp.price_per_mwh) as max_price
from core.market_price mp
join core.settlement_interval si
  on si.interval_id = mp.interval_id
where mp.run_id = 1
  and mp.market_code = 'PZU'
  and si.market_code = 'RO'
  and si.local_date >= date '2026-10-01'
  and si.local_date < date '2026-11-01';
