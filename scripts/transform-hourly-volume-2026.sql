/*
 * Load source-backed 2026 hourly volume families.
 * Direct workbook blocks:
 *   Regenerabili             -> renewable_output, source_sign +1
 *   Prognoza totala consum   -> total_load, source_sign +1
 *   Prognoza consum indexati -> indexed_load, source_sign -1
 *
 * March hour 4 has no physical interval; October repeated hour 4 is ambiguous.
 * Only uniquely mapped source cells are loaded.
 */
begin;

do $$
begin
  if exists(select 1 from core.hourly_volume where run_id=1) then
    raise exception 'core.hourly_volume already contains run_id=1 rows.';
  end if;
end $$;

create temporary table tmp_hourly_volume_2026 on commit drop as
with months(sheet_name,month_no) as (
 values ('Ianuarie',1),('Februarie',2),('Martie',3),('Aprilie',4),
        ('Mai',5),('Iunie',6),('Iulie',7),('August',8),
        ('Septembrie',9),('Octombrie',10),('Noiembrie',11),('Decembrie',12)
),
blocks(measure_code,source_component_code,start_row,end_row,day_header_row,expected_sign) as (
 values
 ('renewable_output','regenerabili',31,54,30,1),
 ('total_load','prognoza_totala_consum',59,82,58,1),
 ('indexed_load','prognoza_consum_indexati',87,110,86,-1)
),
source_cells as (
 select m.sheet_name,m.month_no,b.measure_code,b.source_component_code,b.expected_sign,
        sc.source_cell_id,sc.cell_address,sc.formula_text,
        coalesce(sc.cached_text,sc.raw_text) as value_text,
        dh.raw_text::int as day_of_month,
        ah.raw_text::int as local_hour_label
 from months m cross join blocks b
 join raw.source_cell sc
   on sc.source_file_id=1 and sc.sheet_name=m.sheet_name
  and regexp_replace(sc.cell_address,'[^0-9]','','g')::int between b.start_row and b.end_row
  and regexp_replace(sc.cell_address,'[0-9]','','g') ~ '^(?:[B-Z]|A[A-F])$'
 join raw.source_cell dh
   on dh.source_file_id=1 and dh.sheet_name=m.sheet_name
  and dh.cell_address=regexp_replace(sc.cell_address,'[0-9]','','g')||b.day_header_row::text
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
declare v_source int;v_formula int;v_unique int;v_zero int;v_amb int;v_bad int;
begin
 select count(*) into v_source from tmp_hourly_volume_2026;
 select count(*) into v_formula from tmp_hourly_volume_2026 where formula_text is not null;
 select count(*) into v_unique from tmp_hourly_volume_2026 where candidate_count=1;
 select count(*) into v_zero from tmp_hourly_volume_2026 where candidate_count=0;
 select count(*) into v_amb from tmp_hourly_volume_2026 where candidate_count>1;
 if v_source<>26280 or v_formula<>0 or v_unique<>26274 or v_zero<>3 or v_amb<>3 then
   raise exception 'Hourly source validation failed source %, formula %, unique %, zero %, ambiguous %',
     v_source,v_formula,v_unique,v_zero,v_amb;
 end if;
 select count(*) into v_bad from tmp_hourly_volume_2026
  where (measure_code in ('renewable_output','total_load') and value_text::numeric<0)
     or (measure_code='indexed_load' and value_text::numeric>=0);
 if v_bad<>0 then raise exception 'Hourly source sign validation failed: % rows',v_bad; end if;
end $$;

insert into core.hourly_volume(
 run_id,interval_id,measure_code,book_id,source_component_code,
 quantity_mwh,source_sign,record_status,source_cell_id
)
select 1,interval_id,measure_code,null,source_component_code,
       abs(value_text::numeric),expected_sign::smallint,'unclassified',source_cell_id
from tmp_hourly_volume_2026
where candidate_count=1
order by interval_id,measure_code;

do $$
declare v_rows int;v_sources int;
begin
 select count(*),count(distinct source_cell_id) into v_rows,v_sources
 from core.hourly_volume where run_id=1;
 if v_rows<>26274 or v_sources<>26274 then
   raise exception 'Hourly-volume load validation failed rows %, sources %',v_rows,v_sources;
 end if;
end $$;

commit;

select measure_code,count(*) as rows,sum(quantity_mwh) as quantity_mwh
from core.hourly_volume where run_id=1
group by measure_code order by measure_code;
