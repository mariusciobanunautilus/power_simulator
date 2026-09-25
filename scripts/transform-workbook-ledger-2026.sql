/*
 * Reconstruct workbook-equivalent 2026 base sourcing ledger.
 * Purchase side: 2026 rows 4:24 and 26:29.
 * Sales side:    2026 rows 37:44.
 * Negative purchase values become credits; negative sales values become debits.
 */
begin;

do $$
begin
 if exists(
   select 1 from calc.ledger_line
   where run_id=1 and calculation_rule='workbook_2026_aggregate_row_v1'
 ) then raise exception 'Workbook 2026 aggregate ledger already loaded.'; end if;
end $$;

create temporary table tmp_workbook_ledger_2026 on commit drop as
with months(month_start,q_col,v_col) as (
 values
 (date '2026-01-01','G','I'),(date '2026-02-01','J','L'),
 (date '2026-03-01','M','O'),(date '2026-04-01','P','R'),
 (date '2026-05-01','S','U'),(date '2026-06-01','V','X'),
 (date '2026-07-01','Y','AA'),(date '2026-08-01','AB','AD'),
 (date '2026-09-01','AE','AG'),(date '2026-10-01','AH','AJ'),
 (date '2026-11-01','AK','AM'),(date '2026-12-01','AN','AP')
),
rows(section,row_no) as (
 select 'purchase',g from generate_series(4,24) g
 union all select 'purchase',g from generate_series(26,29) g
 union all select 'sales',g from generate_series(37,44) g
),
src as (
 select m.month_start,r.section,r.row_no,v.source_cell_id,
        coalesce(v.cached_text,v.raw_text) as value_text,
        coalesce(q.cached_text,q.raw_text) as quantity_text
 from months m cross join rows r
 join raw.source_cell v
   on v.source_file_id=1 and v.sheet_name='2026'
  and v.cell_address=m.v_col||r.row_no::text
 left join raw.source_cell q
   on q.source_file_id=1 and q.sheet_name='2026'
  and q.cell_address=m.q_col||r.row_no::text
 where coalesce(v.cached_text,v.raw_text) ~ '^-?[0-9]+([.][0-9]+)?$'
)
select month_start,section,row_no,source_cell_id,
       value_text::numeric as source_value_ron,
       case
         when section='purchase' and value_text::numeric>=0 then 'debit'
         when section='purchase' and value_text::numeric<0 then 'credit'
         when section='sales' and value_text::numeric>=0 then 'credit'
         else 'debit'
       end as entry_side,
       abs(value_text::numeric) as amount_ron,
       case when quantity_text ~ '^-?[0-9]+([.][0-9]+)?$'
            then abs(quantity_text::numeric) end as quantity_mwh
from src;

insert into calc.ledger_line(
 run_id,month_start,book_id,component_code,entry_side,amount_ron,
 quantity_mwh,source_cell_id,calculation_rule
)
select 1,t.month_start,b.book_id,
       upper('WB_'||t.section||'_R'||lpad(t.row_no::text,2,'0')),
       t.entry_side,t.amount_ron,t.quantity_mwh,t.source_cell_id,
       'workbook_2026_aggregate_row_v1'
from tmp_workbook_ledger_2026 t
cross join core.book b
where b.book_code='SOURCING';

insert into calc.reconciliation_result(
 run_id,reconciliation_code,period_start,period_end,
 source_value,recalculated_value,difference_value,tolerance,status,reason,owner_name
)
with months(month_start,result_cell) as (
 values
 (date '2026-01-01','I49'),(date '2026-02-01','L49'),
 (date '2026-03-01','O49'),(date '2026-04-01','R49'),
 (date '2026-05-01','U49'),(date '2026-06-01','X49'),
 (date '2026-07-01','AA49'),(date '2026-08-01','AD49'),
 (date '2026-09-01','AG49'),(date '2026-10-01','AJ49'),
 (date '2026-11-01','AM49'),(date '2026-12-01','AP49')
),
src as (
 select m.month_start,coalesce(sc.cached_text,sc.raw_text)::numeric as source_value
 from months m
 join raw.source_cell sc
   on sc.source_file_id=1 and sc.sheet_name='2026' and sc.cell_address=m.result_cell
),
calc as (
 select mbl.month_start,mbl.result_ron
 from calc.monthly_book_ledger mbl join core.book b on b.book_id=mbl.book_id
 where mbl.run_id=1 and b.book_code='SOURCING'
)
select 1,'BASE_SOURCING_MONTHLY_RESULT',
       s.month_start,(s.month_start+interval '1 month - 1 day')::date,
       s.source_value,c.result_ron,c.result_ron-s.source_value,0.01,
       case when abs(c.result_ron-s.source_value)<=0.01 then 'within_tolerance' else 'mismatch' end,
       'Workbook aggregate ledger reconstructed from 2026 purchase rows 4:24,26:29 and sales rows 37:44.',
       'system'
from src s join calc c using(month_start);

insert into calc.reconciliation_result(
 run_id,reconciliation_code,period_start,period_end,
 source_value,recalculated_value,difference_value,tolerance,status,reason,owner_name
)
select 1,'BASE_SOURCING_ANNUAL_F49_VS_MONTHLY_SUM',
       date '2026-01-01',date '2026-12-31',
       (select coalesce(cached_text,raw_text)::numeric from raw.source_cell
        where source_file_id=1 and sheet_name='2026' and cell_address='F49'),
       sum(mbl.result_ron),
       sum(mbl.result_ron)-
         (select coalesce(cached_text,raw_text)::numeric from raw.source_cell
          where source_file_id=1 and sheet_name='2026' and cell_address='F49'),
       0.01,'mismatch',
       'The annual 2026!F49 formula excludes monthly services and redistribution that are present in the twelve monthly result columns; preserve both values.',
       'Finance'
from calc.monthly_book_ledger mbl
join core.book b on b.book_id=mbl.book_id
where mbl.run_id=1 and b.book_code='SOURCING'
  and mbl.month_start between date '2026-01-01' and date '2026-12-01';

commit;

select month_start,revenue_ron,cost_ron,result_ron
from calc.monthly_book_ledger mbl
join core.book b on b.book_id=mbl.book_id
where mbl.run_id=1 and b.book_code='SOURCING'
order by month_start;
