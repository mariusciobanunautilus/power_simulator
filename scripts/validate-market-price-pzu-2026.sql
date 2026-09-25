/*
 * Power Simulator
 * Validate full-year 2026 PZU market-price load.
 *
 * Expected workbook source cells: 8759
 * Expected loaded facts:          8758
 * Expected physical intervals:    8760
 *
 * Difference:
 *   one October source cell is DST-ambiguous:
 *     Octombrie!Z180
 *     source_cell_id = 76634
 *     2026-10-25 local hour 4
 *
 * It has two physical candidates and is intentionally not loaded.
 */

do $$
declare
    v_source_cells integer;
    v_loaded_rows integer;
    v_distinct_sources integer;
    v_distinct_intervals integer;
    v_unclassified_rows integer;
    v_physical_intervals integer;
    v_missing_physical integer;
    v_october_ambiguous_source integer;
begin
    select count(*)
    into v_source_cells
    from raw.source_cell
    where source_file_id = 1
      and sheet_name in (
          'Ianuarie','Februarie','Martie','Aprilie','Mai','Iunie',
          'Iulie','August','Septembrie','Octombrie','Noiembrie','Decembrie'
      )
      and cell_address ~
            '^(?:[B-Z]|A[A-F])(?:17[7-9]|18[0-9]|19[0-9]|200)$';

    if v_source_cells <> 8759 then
        raise exception
            'Expected 8759 PZU workbook source cells, found %.',
            v_source_cells;
    end if;

    select
        count(*),
        count(distinct mp.source_cell_id),
        count(distinct mp.interval_id),
        count(*) filter (where mp.record_status = 'unclassified')
    into
        v_loaded_rows,
        v_distinct_sources,
        v_distinct_intervals,
        v_unclassified_rows
    from core.market_price mp
    join core.settlement_interval si
      on si.interval_id = mp.interval_id
    where mp.run_id = 1
      and mp.market_code = 'PZU'
      and si.market_code = 'RO'
      and si.local_date >= date '2026-01-01'
      and si.local_date < date '2027-01-01';

    if v_loaded_rows <> 8758 then
        raise exception
            'Expected 8758 loaded PZU facts, found %.',
            v_loaded_rows;
    end if;

    if v_distinct_sources <> 8758 then
        raise exception
            'Expected 8758 distinct loaded PZU source cells, found %.',
            v_distinct_sources;
    end if;

    if v_distinct_intervals <> 8758 then
        raise exception
            'Expected 8758 distinct loaded PZU intervals, found %.',
            v_distinct_intervals;
    end if;

    if v_unclassified_rows <> 8758 then
        raise exception
            'Expected all 8758 loaded PZU facts to be unclassified, found %.',
            v_unclassified_rows;
    end if;

    select count(*)
    into v_physical_intervals
    from core.settlement_interval
    where market_code = 'RO'
      and local_date >= date '2026-01-01'
      and local_date < date '2027-01-01';

    if v_physical_intervals <> 8760 then
        raise exception
            'Expected 8760 Romanian physical settlement intervals, found %.',
            v_physical_intervals;
    end if;

    select count(*)
    into v_missing_physical
    from core.settlement_interval si
    left join core.market_price mp
      on mp.interval_id = si.interval_id
     and mp.run_id = 1
     and mp.market_code = 'PZU'
    where si.market_code = 'RO'
      and si.local_date >= date '2026-01-01'
      and si.local_date < date '2027-01-01'
      and mp.interval_id is null;

    if v_missing_physical <> 2 then
        raise exception
            'Expected exactly 2 physical intervals without PZU facts, found %.',
            v_missing_physical;
    end if;

    select count(*)
    into v_october_ambiguous_source
    from raw.source_cell
    where source_cell_id = 76634
      and source_file_id = 1
      and sheet_name = 'Octombrie'
      and cell_address = 'Z180'
      and coalesce(cached_text, raw_text)::numeric = 709.7704640775::numeric;

    if v_october_ambiguous_source <> 1 then
        raise exception
            'Expected canonical ambiguous Octombrie!Z180 source cell exactly once, found %.',
            v_october_ambiguous_source;
    end if;

    if exists (
        select 1
        from core.market_price
        where run_id = 1
          and market_code = 'PZU'
          and source_cell_id = 76634
    ) then
        raise exception
            'Ambiguous Octombrie!Z180 source cell was incorrectly loaded.';
    end if;

    if (
        select count(*)
        from core.settlement_interval si
        left join core.market_price mp
          on mp.interval_id = si.interval_id
         and mp.run_id = 1
         and mp.market_code = 'PZU'
        where si.market_code = 'RO'
          and si.local_date = date '2026-10-25'
          and si.local_hour_label = 4
          and si.local_occurrence in (1, 2)
          and mp.interval_id is null
    ) <> 2 then
        raise exception
            'Expected both October repeated-hour physical intervals to remain without PZU facts.';
    end if;
end
$$;

select
    extract(month from si.local_date)::integer as month_no,
    count(*) as loaded_rows,
    count(distinct mp.interval_id) as distinct_intervals,
    count(distinct mp.source_cell_id) as distinct_source_cells,
    count(*) filter (
        where mp.record_status = 'unclassified'
    ) as unclassified_rows,
    min(mp.price_per_mwh) as min_price,
    max(mp.price_per_mwh) as max_price
from core.market_price mp
join core.settlement_interval si
  on si.interval_id = mp.interval_id
where mp.run_id = 1
  and mp.market_code = 'PZU'
  and si.market_code = 'RO'
  and si.local_date >= date '2026-01-01'
  and si.local_date < date '2027-01-01'
group by 1
order by 1;

select
    si.interval_id,
    si.local_date,
    si.local_hour_label,
    si.local_occurrence,
    si.interval_start_utc
from core.settlement_interval si
left join core.market_price mp
  on mp.interval_id = si.interval_id
 and mp.run_id = 1
 and mp.market_code = 'PZU'
where si.market_code = 'RO'
  and si.local_date >= date '2026-01-01'
  and si.local_date < date '2027-01-01'
  and mp.interval_id is null
order by si.interval_start_utc;
