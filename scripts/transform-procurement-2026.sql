/*
 * Load 2026 workbook acquisition schedule.
 * One neutral placeholder contract is used because the workbook supplies hourly
 * quantities but no authoritative supplier/product/pricing metadata.
 */
begin;

do $$
begin
 if exists(select 1 from core.contract where contract_reference='WORKBOOK_ACQUISITION_2026') then
   raise exception 'WORKBOOK_ACQUISITION_2026 already exists.';
 end if;
 if exists(select 1 from core.procurement_schedule where run_id=1) then
   raise exception 'Procurement schedule already contains run_id=1 rows.';
 end if;
end $$;

insert into core.contract(
 contract_reference,external_reference,counterparty_id,book_id,product_id,side,
 price_method,valid_from,valid_to,currency_code,active
)
select 'WORKBOOK_ACQUISITION_2026','Simulare_2026_wk39.xlsx::Achizitie',
       null,b.book_id,null,'buy','unclassified',
       date '2026-01-01',date '2026-12-31',null,true
from core.book b where b.book_code='SOURCING';

create temporary table tmp_procurement_2026 on commit drop as
with months(sheet_name,month_no) as (
 values ('Ianuarie',1),('Februarie',2),('Martie',3),('Aprilie',4),
        ('Mai',5),('Iunie',6),('Iulie',7),('August',8),
        ('Septembrie',9),('Octombrie',10),('Noiembrie',11),('Decembrie',12)
),
source_cells as (
 select m.sheet_name,m.month_no,sc.source_cell_id,sc.cell_address,sc.formula_text,
        coalesce(sc.cached_text,sc.raw_text) as value_text,
        dh.raw_text::int as day_of_month,
        ah.raw_text::int as local_hour_label
 from months m
 join raw.source_cell sc
   on sc.source_file_id=1 and sc.sheet_name=m.sheet_name
  and regexp_replace(sc.cell_address,'[^0-9]','','g')::int between 3 and 26
  and regexp_replace(sc.cell_address,'[0-9]','','g') ~ '^(?:[B-Z]|A[A-F])$'
 join raw.source_cell dh
   on dh.source_file_id=1 and dh.sheet_name=m.sheet_name
  and dh.cell_address=regexp_replace(sc.cell_address,'[0-9]','','g')||'2'
 join raw.source_cell ah
   on ah.source_file_id=1 and ah.sheet_name=m.sheet_name
  and ah.cell_address='A'||regexp_replace(sc.cell_address,'[^0-9]','','g')
),
mapped as (
 select s.*,
        make_date(2026,s.month_no,s.day_of_month) as local_date,
        (select count(*) from core.settlement_interval si
          where si.market_code='RO'
            and si.local_date=make_date(2026,s.month_no,s.day_of_month)
            and si.local_hour_label=s.local_hour_label) as candidate_count,
        (select min(si.interval_id) from core.settlement_interval si
          where si.market_code='RO'
            and si.local_date=make_date(2026,s.month_no,s.day_of_month)
            and si.local_hour_label=s.local_hour_label) as interval_id
 from source_cells s
)
select * from mapped;

do $$
declare v_source int;v_unique int;v_zero int;v_amb int;v_negative int;
begin
 select count(*) into v_source from tmp_procurement_2026;
 select count(*) into v_unique from tmp_procurement_2026 where candidate_count=1;
 select count(*) into v_zero from tmp_procurement_2026 where candidate_count=0;
 select count(*) into v_amb from tmp_procurement_2026 where candidate_count>1;
 select count(*) into v_negative from tmp_procurement_2026 where value_text::numeric<0;
 if v_source<>8760 or v_unique<>8758 or v_zero<>1 or v_amb<>1 or v_negative<>0 then
   raise exception 'Procurement source validation failed source %, unique %, zero %, ambiguous %, negative %',
    v_source,v_unique,v_zero,v_amb,v_negative;
 end if;
end $$;

insert into core.procurement_schedule(run_id,interval_id,contract_id,quantity_mwh,source_cell_id)
select 1,t.interval_id,c.contract_id,t.value_text::numeric,t.source_cell_id
from tmp_procurement_2026 t
cross join core.contract c
where c.contract_reference='WORKBOOK_ACQUISITION_2026'
  and t.candidate_count=1
order by t.interval_id;

insert into calc.quality_issue(
 run_id,rule_code,severity,source_reference,observed_value,expected_value,disposition,owner_name
)
select 1,'PROCUREMENT_DST_UNRESOLVED','medium',
       sheet_name||'!'||cell_address,
       'value='||value_text||'; local_date='||local_date||'; local_hour='||local_hour_label||'; candidates='||candidate_count,
       'Exactly one physical settlement interval','open','Trading + settlement'
from tmp_procurement_2026 where candidate_count<>1;

commit;

select extract(month from si.local_date)::int as month_no,
       count(*) as rows,sum(ps.quantity_mwh) as loaded_mwh
from core.procurement_schedule ps
join core.settlement_interval si on si.interval_id=ps.interval_id
where ps.run_id=1
group by 1 order by 1;
