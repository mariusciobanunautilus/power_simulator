create or replace view calc.hourly_position_workbook
with (security_invoker = true)
as
with months(sheet_name, month_no) as (
    values
      ('Ianuarie',1),('Februarie',2),('Martie',3),('Aprilie',4),
      ('Mai',5),('Iunie',6),('Iulie',7),('August',8),
      ('Septembrie',9),('Octombrie',10),('Noiembrie',11),('Decembrie',12)
),
source_position as (
    select
      1::bigint as run_id,
      m.sheet_name,
      m.month_no,
      sc.source_cell_id,
      sc.cell_address,
      sc.formula_text,
      coalesce(sc.cached_text,sc.raw_text)::numeric as market_net_mwh,
      dh.raw_text::integer as day_of_month,
      ah.raw_text::integer as local_hour_label
    from months m
    join raw.source_cell sc
      on sc.source_file_id=1
     and sc.sheet_name=m.sheet_name
     and regexp_replace(sc.cell_address,'[^0-9]','','g')::integer between 146 and 169
     and regexp_replace(sc.cell_address,'[0-9]','','g') ~ '^(?:[B-Z]|A[A-F])$'
    join raw.source_cell dh
      on dh.source_file_id=1
     and dh.sheet_name=m.sheet_name
     and dh.cell_address=regexp_replace(sc.cell_address,'[0-9]','','g')||'145'
    join raw.source_cell ah
      on ah.source_file_id=1
     and ah.sheet_name=m.sheet_name
     and ah.cell_address='A'||regexp_replace(sc.cell_address,'[^0-9]','','g')
),
mapped as (
    select
      sp.*,
      make_date(2026,sp.month_no,sp.day_of_month) as local_date,
      count(si.interval_id) as candidate_count,
      case when count(si.interval_id)=1 then min(si.interval_id) end as interval_id
    from source_position sp
    left join core.settlement_interval si
      on si.market_code='RO'
     and si.local_date=make_date(2026,sp.month_no,sp.day_of_month)
     and si.local_hour_label=sp.local_hour_label
    group by
      sp.run_id,sp.sheet_name,sp.month_no,sp.source_cell_id,sp.cell_address,
      sp.formula_text,sp.market_net_mwh,sp.day_of_month,sp.local_hour_label
)
select
  run_id,source_cell_id,sheet_name,cell_address,local_date,local_hour_label,
  candidate_count,interval_id,market_net_mwh,formula_text
from mapped;

comment on view calc.hourly_position_workbook is
'Workbook-equivalent PZU physical position from the saved monthly Pozitie - PZU cells. Preserves workbook rounding/formulas and source-cell lineage. candidate_count <> 1 remains unresolved and interval_id is null.';

create or replace view calc.hourly_market_value_workbook
with (security_invoker = true)
as
select
  hpw.run_id,
  hpw.interval_id,
  hpw.source_cell_id as position_source_cell_id,
  hpw.local_date,
  hpw.local_hour_label,
  hpw.market_net_mwh,
  mp.price_per_mwh as pzu_ron_per_mwh,
  mp.source_cell_id as price_source_cell_id,
  greatest(hpw.market_net_mwh,0) as sold_mwh,
  greatest(-hpw.market_net_mwh,0) as bought_mwh,
  greatest(hpw.market_net_mwh,0)*mp.price_per_mwh as sale_cashflow_ron,
  greatest(-hpw.market_net_mwh,0)*mp.price_per_mwh as purchase_cashflow_ron
from calc.hourly_position_workbook hpw
join core.market_price mp
  on mp.run_id=hpw.run_id
 and mp.interval_id=hpw.interval_id
 and mp.market_code='PZU'
 and mp.currency_code='RON'
where hpw.candidate_count=1;

comment on view calc.hourly_market_value_workbook is
'Workbook-equivalent PZU valuation using saved workbook PZU position cells and source-backed PZU prices.';
