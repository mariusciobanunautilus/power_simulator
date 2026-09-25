create or replace view calc.monthly_pzu_workbook
with (security_invoker = true)
as
with months(sheet_name, month_no, month_start, days_in_month) as (
    values
      ('Ianuarie',1,date '2026-01-01',31),
      ('Februarie',2,date '2026-02-01',28),
      ('Martie',3,date '2026-03-01',31),
      ('Aprilie',4,date '2026-04-01',30),
      ('Mai',5,date '2026-05-01',31),
      ('Iunie',6,date '2026-06-01',30),
      ('Iulie',7,date '2026-07-01',31),
      ('August',8,date '2026-08-01',31),
      ('Septembrie',9,date '2026-09-01',30),
      ('Octombrie',10,date '2026-10-01',31),
      ('Noiembrie',11,date '2026-11-01',30),
      ('Decembrie',12,date '2026-12-01',31)
),
hourly as (
    select
      1::bigint as run_id,
      m.month_start,
      m.sheet_name,
      p.source_cell_id as position_source_cell_id,
      v.source_cell_id as value_source_cell_id,
      coalesce(p.cached_text,p.raw_text)::numeric as position_mwh,
      coalesce(v.cached_text,v.raw_text)::numeric as value_ron
    from months m
    join raw.source_cell v
      on v.source_file_id=1
     and v.sheet_name=m.sheet_name
     and regexp_replace(v.cell_address,'[^0-9]','','g')::integer between 207 and 230
     and regexp_replace(v.cell_address,'[0-9]','','g') ~ '^(?:[B-Z]|A[A-F])$'
    join raw.source_cell dh
      on dh.source_file_id=1
     and dh.sheet_name=m.sheet_name
     and dh.cell_address=regexp_replace(v.cell_address,'[0-9]','','g')||'206'
     and dh.raw_text::integer between 1 and m.days_in_month
    join raw.source_cell p
      on p.source_file_id=v.source_file_id
     and p.sheet_name=v.sheet_name
     and p.cell_address=
        regexp_replace(v.cell_address,'[0-9]','','g') ||
        (regexp_replace(v.cell_address,'[^0-9]','','g')::integer - 61)::text
)
select
  run_id,
  month_start,
  count(*) as source_hour_rows,
  sum(greatest(position_mwh,0)) as sell_mwh,
  sum(greatest(-position_mwh,0)) as buy_mwh,
  sum(greatest(value_ron,0)) as workbook_sale_value_ron,
  sum(greatest(-value_ron,0)) as workbook_purchase_value_ron,
  sum(value_ron) as workbook_net_value_ron,
  sum(greatest(value_ron,0))/nullif(sum(greatest(position_mwh,0)),0) as workbook_weighted_sell_price,
  sum(greatest(-value_ron,0))/nullif(sum(greatest(-position_mwh,0)),0) as workbook_weighted_buy_price
from hourly
group by run_id,month_start;

comment on view calc.monthly_pzu_workbook is
'Workbook-equivalent monthly PZU summary. Physical buy/sell MWh comes from Pozitie - PZU sign. Value buckets reproduce Excel SUMIF on signed value cells, so negative market prices may classify cashflow differently from physical direction. This convention is intentionally separate from normalized physical-direction valuation.';
