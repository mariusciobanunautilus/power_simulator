/*
 * Power Simulator
 * Transform November 2026 PZU prices into core.market_price
 *
 * Source workbook:
 *   sheet: Noiembrie
 *   hourly PZU matrix: rows 177:200, calendar-day columns from row 176
 *
 * Expected populated source cells: 720
 *
 * Canonical temporal mapping:
 *   docs/dst-source-to-settlement-mapping.md
 *
 * Record status:
 *   unclassified
 *
 * Lineage:
 *   every inserted fact preserves raw.source_cell.source_cell_id
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
          and si.local_date >= date '2026-11-01'
          and si.local_date < date '2026-12-01'
    ) then
        raise exception
            'November 2026 PZU prices already exist for run_id = 1. Transformation aborted.';
    end if;
end
$$;

create temporary table tmp_pzu_november_map
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
      and sc.sheet_name = 'Noiembrie'
      and sc.cell_address ~
            '^(?:[B-Z]|A[A-F])(?:17[7-9]|18[0-9]|19[0-9]|200)$'
),
mapped as (
    select
        pc.*,
        make_date(2026, 11, pc.day_of_month) as local_date,
        (
            select count(*)
            from core.settlement_interval si
            where si.market_code = 'RO'
              and si.local_date = make_date(2026, 11, pc.day_of_month)
              and si.local_hour_label = pc.local_hour_label
        ) as candidate_count,
        (
            select min(si.interval_id)
            from core.settlement_interval si
            where si.market_code = 'RO'
              and si.local_date = make_date(2026, 11, pc.day_of_month)
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
    v_null_interval_rows integer;
    v_duplicate_interval_rows integer;
begin
    select count(*) into v_source_rows from tmp_pzu_november_map;
    if v_source_rows <> 720 then
        raise exception 'November: expected 720 source cells, found %.', v_source_rows;
    end if;

    select count(*) into v_numeric_rows
    from tmp_pzu_november_map
    where value_text ~ '^-?[0-9]+([.][0-9]+)?$';
    if v_numeric_rows <> 720 then
        raise exception 'November: expected 720 numeric values, found %.', v_numeric_rows;
    end if;

    select count(*) into v_formula_rows
    from tmp_pzu_november_map
    where formula_text is not null;
    if v_formula_rows <> 0 then
        raise exception 'November: expected zero formula cells, found %.', v_formula_rows;
    end if;

    select count(*) into v_unique_rows
    from tmp_pzu_november_map
    where candidate_count = 1;
    if v_unique_rows <> 720 then
        raise exception 'November: expected 720 unique mappings, found %.', v_unique_rows;
    end if;

    select count(*) into v_zero_candidate_rows
    from tmp_pzu_november_map
    where candidate_count = 0;
    if v_zero_candidate_rows <> 0 then
        raise exception 'November: found % zero-candidate mappings.', v_zero_candidate_rows;
    end if;

    select count(*) into v_ambiguous_rows
    from tmp_pzu_november_map
    where candidate_count > 1;
    if v_ambiguous_rows <> 0 then
        raise exception 'November: found % ambiguous mappings.', v_ambiguous_rows;
    end if;

    select count(*) into v_null_interval_rows
    from tmp_pzu_november_map
    where interval_id is null;
    if v_null_interval_rows <> 0 then
        raise exception 'November: found % null interval mappings.', v_null_interval_rows;
    end if;

    select count(*) into v_duplicate_interval_rows
    from (
        select interval_id
        from tmp_pzu_november_map
        group by interval_id
        having count(*) <> 1
    ) d;
    if v_duplicate_interval_rows <> 0 then
        raise exception 'November: found % duplicate interval mappings.', v_duplicate_interval_rows;
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
from tmp_pzu_november_map
where candidate_count = 1
order by interval_id;

do $$
declare
    v_loaded_rows integer;
    v_unclassified_rows integer;
    v_distinct_source_cells integer;
    v_distinct_intervals integer;
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
      and si.local_date >= date '2026-11-01'
      and si.local_date < date '2026-12-01';

    if v_loaded_rows <> 720
       or v_unclassified_rows <> 720
       or v_distinct_source_cells <> 720
       or v_distinct_intervals <> 720 then
        raise exception
            'November: invalid post-load counts rows %, status %, sources %, intervals %.',
            v_loaded_rows, v_unclassified_rows, v_distinct_source_cells, v_distinct_intervals;
    end if;

    if v_min_price <> (602.2479919575)::numeric(20,8) then
        raise exception
            'November: unexpected stored minimum %, expected source minimum 602.2479919575 at schema scale.',
            v_min_price;
    end if;

    if v_max_price <> (1756.95097683)::numeric(20,8) then
        raise exception
            'November: unexpected stored maximum %, expected source maximum 1756.95097683 at schema scale.',
            v_max_price;
    end if;
end
$$;

commit;

select
    count(*) as november_pzu_rows,
    count(distinct mp.interval_id) as distinct_intervals,
    count(distinct mp.source_cell_id) as distinct_source_cells,
    min(mp.price_per_mwh) as min_price,
    max(mp.price_per_mwh) as max_price
from core.market_price mp
join core.settlement_interval si
  on si.interval_id = mp.interval_id
where mp.run_id = 1
  and mp.market_code = 'PZU'
  and si.market_code = 'RO'
  and si.local_date >= date '2026-11-01'
  and si.local_date < date '2026-12-01';
