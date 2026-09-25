/*
 * Seed source-backed KPI definitions/results and known quality issues.
 */
begin;

insert into calc.metric_definition(
 metric_code,label,unit,grain,signed_convention,rule_version,description,active
) values
('retail_total_mwh','Retail total load','MWh','month','positive volume','workbook_equivalent_v1','Monthly total load from source-backed hourly total_load.',true),
('fixed_long_mwh','Fixed position long','MWh','month','positive long magnitude','workbook_equivalent_v1','Workbook fixed-position positive volume from Books result long column.',true),
('fixed_short_mwh','Fixed position short','MWh','month','positive short magnitude','workbook_equivalent_v1','Workbook fixed-position short magnitude from Books result short column.',true),
('pzu_buy_mwh','PZU physical buy volume','MWh','month','positive buy magnitude','workbook_equivalent_v1','Workbook Pozitie - PZU negative volume magnitude.',true),
('pzu_sell_mwh','PZU physical sell volume','MWh','month','positive sell magnitude','workbook_equivalent_v1','Workbook Pozitie - PZU positive volume.',true),
('pzu_weighted_buy_price','PZU workbook weighted buy price','RON/MWh','month','positive price','workbook_equivalent_v1','Workbook purchase-value bucket divided by physical buy MWh. Preserves Excel SUMIF cash-sign convention.',true),
('monthly_base_sourcing_ron','Monthly base sourcing result','RON','month','signed profit/loss','workbook_equivalent_v1','Workbook 2026 monthly sales total minus purchase total reconstructed in calc.ledger_line.',true),
('sourcing_total_eur','Sourcing total','EUR','year','signed result','workbook_equivalent_v1','Books result annual sourcing total including optimization margin.',true),
('optimisation_margin_eur','Optimisation margin','EUR','year','signed margin','workbook_equivalent_v1','Books result annual Sourcing Book - optimisation margin.',true),
('origination_margin_eur','Origination margin','EUR','year','signed margin','workbook_equivalent_v1','Books result annual Origination Book total margin.',true),
('transaction_cost_ron','Transaction and guarantee cost','RON','year','positive cost','workbook_equivalent_v1','Costuri tranzationare annual TOTAL COSTURI; excluded from sourcing total.',true)
on conflict(metric_code) do update set
 label=excluded.label,unit=excluded.unit,grain=excluded.grain,
 signed_convention=excluded.signed_convention,rule_version=excluded.rule_version,
 description=excluded.description,active=excluded.active;

insert into calc.metric_result(run_id,metric_code,period_start,period_end,book_id,numeric_value)
select 1,'retail_total_mwh',date_trunc('month',si.local_date)::date,
       (date_trunc('month',si.local_date)+interval '1 month - 1 day')::date,
       b.book_id,sum(hv.quantity_mwh)
from core.hourly_volume hv
join core.settlement_interval si on si.interval_id=hv.interval_id
cross join core.book b
where hv.run_id=1 and hv.measure_code='total_load' and b.book_code='PORTFOLIO_TOTAL'
group by 3,4,b.book_id
on conflict(run_id,metric_code,period_start,book_id) do update
set period_end=excluded.period_end,numeric_value=excluded.numeric_value,calculated_at=now();

with months(month_start,long_cell,short_cell) as (
 values
 (date '2026-01-01','H6','I6'),(date '2026-02-01','H7','I7'),
 (date '2026-03-01','H8','I8'),(date '2026-04-01','H9','I9'),
 (date '2026-05-01','H10','I10'),(date '2026-06-01','H11','I11'),
 (date '2026-07-01','H12','I12'),(date '2026-08-01','H13','I13'),
 (date '2026-09-01','H14','I14'),(date '2026-10-01','H15','I15'),
 (date '2026-11-01','H16','I16'),(date '2026-12-01','H17','I17')
),
vals as (
 select m.month_start,
        coalesce(l.cached_text,l.raw_text)::numeric as long_mwh,
        abs(coalesce(s.cached_text,s.raw_text)::numeric) as short_mwh
 from months m
 join raw.source_cell l on l.source_file_id=1 and l.sheet_name='Books result' and l.cell_address=m.long_cell
 join raw.source_cell s on s.source_file_id=1 and s.sheet_name='Books result' and s.cell_address=m.short_cell
)
insert into calc.metric_result(run_id,metric_code,period_start,period_end,book_id,numeric_value)
select 1,x.metric_code,v.month_start,(v.month_start+interval '1 month - 1 day')::date,b.book_id,x.value
from vals v
cross join lateral(values ('fixed_long_mwh',v.long_mwh),('fixed_short_mwh',v.short_mwh)) x(metric_code,value)
cross join core.book b where b.book_code='SOURCING'
on conflict(run_id,metric_code,period_start,book_id) do update
set period_end=excluded.period_end,numeric_value=excluded.numeric_value,calculated_at=now();

insert into calc.metric_result(run_id,metric_code,period_start,period_end,book_id,numeric_value)
select 1,x.metric_code,p.month_start,(p.month_start+interval '1 month - 1 day')::date,b.book_id,x.value
from calc.monthly_pzu_workbook p
cross join lateral(values
 ('pzu_buy_mwh',p.buy_mwh),
 ('pzu_sell_mwh',p.sell_mwh),
 ('pzu_weighted_buy_price',p.workbook_weighted_buy_price)
) x(metric_code,value)
cross join core.book b where b.book_code='SOURCING'
on conflict(run_id,metric_code,period_start,book_id) do update
set period_end=excluded.period_end,numeric_value=excluded.numeric_value,calculated_at=now();

insert into calc.metric_result(run_id,metric_code,period_start,period_end,book_id,numeric_value)
select 1,'monthly_base_sourcing_ron',mbl.month_start,
       (mbl.month_start+interval '1 month - 1 day')::date,mbl.book_id,mbl.result_ron
from calc.monthly_book_ledger mbl join core.book b on b.book_id=mbl.book_id
where mbl.run_id=1 and b.book_code='SOURCING'
on conflict(run_id,metric_code,period_start,book_id) do update
set period_end=excluded.period_end,numeric_value=excluded.numeric_value,calculated_at=now();

insert into calc.metric_result(run_id,metric_code,period_start,period_end,book_id,numeric_value)
select 1,'sourcing_total_eur',date '2026-01-01',date '2026-12-31',b.book_id,
       coalesce(sc.cached_text,sc.raw_text)::numeric
from raw.source_cell sc cross join core.book b
where sc.source_file_id=1 and sc.sheet_name='Books result' and sc.cell_address='E18'
  and b.book_code='SOURCING'
on conflict(run_id,metric_code,period_start,book_id) do update
set period_end=excluded.period_end,numeric_value=excluded.numeric_value,calculated_at=now();

insert into calc.metric_result(run_id,metric_code,period_start,period_end,book_id,numeric_value)
select 1,'optimisation_margin_eur',date '2026-01-01',date '2026-12-31',b.book_id,
       coalesce(sc.cached_text,sc.raw_text)::numeric
from raw.source_cell sc cross join core.book b
where sc.source_file_id=1 and sc.sheet_name='Books result' and sc.cell_address='G37'
  and b.book_code='OPTIMISATION'
on conflict(run_id,metric_code,period_start,book_id) do update
set period_end=excluded.period_end,numeric_value=excluded.numeric_value,calculated_at=now();

insert into calc.metric_result(run_id,metric_code,period_start,period_end,book_id,numeric_value)
select 1,'origination_margin_eur',date '2026-01-01',date '2026-12-31',b.book_id,
       coalesce(sc.cached_text,sc.raw_text)::numeric
from raw.source_cell sc cross join core.book b
where sc.source_file_id=1 and sc.sheet_name='Books result' and sc.cell_address='G56'
  and b.book_code='ORIGINATION'
on conflict(run_id,metric_code,period_start,book_id) do update
set period_end=excluded.period_end,numeric_value=excluded.numeric_value,calculated_at=now();

insert into calc.metric_result(run_id,metric_code,period_start,period_end,book_id,numeric_value)
select 1,'transaction_cost_ron',date '2026-01-01',date '2026-12-31',b.book_id,
       coalesce(sc.cached_text,sc.raw_text)::numeric
from raw.source_cell sc cross join core.book b
where sc.source_file_id=1 and sc.sheet_name='Costuri tranzationare' and sc.cell_address='E27'
  and b.book_code='PORTFOLIO_TOTAL'
on conflict(run_id,metric_code,period_start,book_id) do update
set period_end=excluded.period_end,numeric_value=excluded.numeric_value,calculated_at=now();

insert into calc.quality_issue(run_id,rule_code,severity,source_reference,observed_value,expected_value,disposition,owner_name)
select 1,'WORKBOOK_CACHED_ERRORS','high','raw.source_cell','11 error-like cached/raw cells','0 unresolved workbook errors','open','Model owner'
where not exists(select 1 from calc.quality_issue where run_id=1 and rule_code='WORKBOOK_CACHED_ERRORS');
insert into calc.quality_issue(run_id,rule_code,severity,source_reference,observed_value,expected_value,disposition,owner_name)
select 1,'CONTRACT_METADATA_PLACEHOLDER','medium','WORKBOOK_ACQUISITION_2026','Quantity-only placeholder: supplier/product/currency/price method unavailable','Authoritative acquisition contract metadata','open','Trading + settlement'
where not exists(select 1 from calc.quality_issue where run_id=1 and rule_code='CONTRACT_METADATA_PLACEHOLDER');
insert into calc.quality_issue(run_id,rule_code,severity,source_reference,observed_value,expected_value,disposition,owner_name)
select 1,'HOURLY_ID_PRICE_UNAVAILABLE','medium','2026 sheet DAM+ID / Costuri tranzationare PZU+ID','No authoritative hourly ID price series in workbook','Hourly ID price source with interval lineage','open','Trading'
where not exists(select 1 from calc.quality_issue where run_id=1 and rule_code='HOURLY_ID_PRICE_UNAVAILABLE');
insert into calc.quality_issue(run_id,rule_code,severity,source_reference,observed_value,expected_value,disposition,owner_name)
select 1,'TRADE_DETAIL_UNAVAILABLE','medium','Books result optimisation/origination','Monthly aggregate margins only; no deal identifiers/counterparties','Deal-level trade records before core.trade population','open','Trading'
where not exists(select 1 from calc.quality_issue where run_id=1 and rule_code='TRADE_DETAIL_UNAVAILABLE');
insert into calc.quality_issue(run_id,rule_code,severity,source_reference,observed_value,expected_value,disposition,owner_name)
select 1,'PZU_OCTOBER_REPEATED_HOUR_UNRESOLVED','medium','Octombrie!Z180','One price source value has two physical hour-4 candidates','Authoritative occurrence mapping','open','Trading + settlement'
where not exists(select 1 from calc.quality_issue where run_id=1 and rule_code='PZU_OCTOBER_REPEATED_HOUR_UNRESOLVED');
insert into calc.quality_issue(run_id,rule_code,severity,source_reference,observed_value,expected_value,disposition,owner_name)
select 1,'HOURLY_VOLUME_DST_UNRESOLVED','medium','Martie/Octombrie hourly source blocks','3 spring no-interval + 3 autumn ambiguous volume cells','Authoritative DST mapping or source correction','open','Trading + settlement'
where not exists(select 1 from calc.quality_issue where run_id=1 and rule_code='HOURLY_VOLUME_DST_UNRESOLVED');

commit;

select metric_code,count(*) as result_rows
from calc.metric_result where run_id=1
group by metric_code order by metric_code;
