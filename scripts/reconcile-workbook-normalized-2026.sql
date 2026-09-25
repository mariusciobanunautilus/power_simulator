/*
 * Reconcile workbook-equivalent PZU metrics with normalized physical calculations,
 * then run technical validation gates. This script moves run 1 to validated only.
 * Approval/publication remains a human governance action.
 */
begin;

delete from calc.reconciliation_result
where run_id=1
  and reconciliation_code in (
    'PZU_BUY_MWH_WORKBOOK_VS_NORMALIZED',
    'PZU_SELL_MWH_WORKBOOK_VS_NORMALIZED',
    'PZU_WEIGHTED_BUY_PRICE_WORKBOOK_VS_NORMALIZED'
  );

with normalized as (
  select date_trunc('month',si.local_date)::date as month_start,
         sum(greatest(-hp.market_net_mwh,0)) as buy_mwh,
         sum(greatest(hp.market_net_mwh,0)) as sell_mwh,
         sum(greatest(-hp.market_net_mwh,0)*mp.price_per_mwh)
           / nullif(sum(greatest(-hp.market_net_mwh,0)),0) as weighted_buy_price
  from calc.hourly_position hp
  join core.settlement_interval si on si.interval_id=hp.interval_id
  join core.market_price mp
    on mp.run_id=hp.run_id and mp.interval_id=hp.interval_id
   and mp.market_code='PZU' and mp.currency_code='RON'
  where hp.run_id=1
  group by 1
),
pairs as (
 select w.month_start,w.buy_mwh as wb_buy,w.sell_mwh as wb_sell,
        w.workbook_weighted_buy_price as wb_price,
        n.buy_mwh as norm_buy,n.sell_mwh as norm_sell,n.weighted_buy_price as norm_price
 from calc.monthly_pzu_workbook w join normalized n using(month_start)
)
insert into calc.reconciliation_result(
 run_id,reconciliation_code,period_start,period_end,
 source_value,recalculated_value,difference_value,tolerance,status,reason,owner_name
)
select 1,x.code,p.month_start,(p.month_start+interval '1 month - 1 day')::date,
       x.source_value,x.recalc_value,x.recalc_value-x.source_value,x.tolerance,
       case when abs(x.recalc_value-x.source_value)<=x.tolerance then 'within_tolerance' else 'mismatch' end,
       'Workbook-equivalent path preserves saved rounded/formula outputs; normalized path recomputes physical direction from source-backed core facts. March/October also reflect unresolved DST source mappings; negative market prices can change workbook cash-sign buckets.',
       'Trading + settlement'
from pairs p
cross join lateral(values
 ('PZU_BUY_MWH_WORKBOOK_VS_NORMALIZED',p.wb_buy,p.norm_buy,0.001::numeric),
 ('PZU_SELL_MWH_WORKBOOK_VS_NORMALIZED',p.wb_sell,p.norm_sell,0.001::numeric),
 ('PZU_WEIGHTED_BUY_PRICE_WORKBOOK_VS_NORMALIZED',p.wb_price,p.norm_price,0.01::numeric)
) x(code,source_value,recalc_value,tolerance);

do $$
declare v_raw int;v_pzu int;v_hv int;v_proc int;v_ledger_months int;
        v_metric_results int;v_recon int;v_issues int;v_critical int;
begin
 select count(*) into v_raw from raw.source_cell where source_file_id=1;
 select count(*) into v_pzu from core.market_price where run_id=1 and market_code='PZU';
 select count(*) into v_hv from core.hourly_volume where run_id=1;
 select count(*) into v_proc from core.procurement_schedule where run_id=1;
 select count(distinct month_start) into v_ledger_months
 from calc.monthly_book_ledger mbl join core.book b on b.book_id=mbl.book_id
 where mbl.run_id=1 and b.book_code='SOURCING';
 select count(*) into v_metric_results from calc.metric_result where run_id=1;
 select count(*) into v_recon from calc.reconciliation_result where run_id=1;
 select count(*) into v_issues from calc.quality_issue where run_id=1;
 select count(*) into v_critical from calc.quality_issue
  where run_id=1 and severity='critical' and disposition='open';

 if v_raw<>93052 then raise exception 'Raw source count expected 93052, found %',v_raw; end if;
 if v_pzu<>8758 then raise exception 'PZU count expected 8758, found %',v_pzu; end if;
 if v_hv<>26274 then raise exception 'Hourly volume count expected 26274, found %',v_hv; end if;
 if v_proc<>8758 then raise exception 'Procurement count expected 8758, found %',v_proc; end if;
 if v_ledger_months<>12 then raise exception 'Ledger months expected 12, found %',v_ledger_months; end if;
 if v_metric_results<70 then raise exception 'Metric result count unexpectedly low: %',v_metric_results; end if;
 if v_recon<50 then raise exception 'Reconciliation count unexpectedly low: %',v_recon; end if;
 if v_issues<8 then raise exception 'Quality issue count unexpectedly low: %',v_issues; end if;
 if v_critical<>0 then raise exception 'Open critical issues block validation: %',v_critical; end if;
end $$;

update core.model_run
set status='validated'
where run_id=1 and status='draft';

commit;

select run_id,scenario_code,method_version,status,approved_by,approved_at
from core.model_run where run_id=1;
