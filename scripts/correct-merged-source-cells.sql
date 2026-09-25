/*
 * Power Simulator
 * Correct merged-cell ingestion artefacts
 *
 * Source:
 *   Simulare_2026_wk39.xlsx
 *   source_file_id = 1
 *   run_id = 1
 *   import batch = 1
 *
 * Verified original state:
 *
 *   Workbook traversal                     93,112
 *   Merged follower cells                      60
 *   Canonical workbook source cells        93,052
 *
 *   raw.source_cell persisted              93,108
 *   Artificial persisted followers             56
 *
 *   raw.import_reject                           4
 *   False merged-cell rejects:
 *       2026!C2
 *       2026!C4
 *       2026!C5
 *       2026!A41
 *
 * Therefore:
 *
 *   93,108 - 56 = 93,052 canonical source cells
 *   4 false rejects removed
 *
 * Correct import-batch state:
 *
 *   rows_received = 93,052
 *   rows_loaded   = 93,052
 *   rows_rejected = 0
 *
 * All changes are transaction-protected and guarded.
 */


begin;


/*
 * ==============================================================
 * 1. IDENTIFY THE 56 ARTIFICIAL PERSISTED SOURCE CELLS
 * ==============================================================
 */

create temporary table _merged_source_cell_candidates
on commit drop
as
select
    source_cell_id,
    source_file_id,
    sheet_name,
    cell_address
from raw.source_cell
where source_file_id = 1
  and (
        (
            sheet_name = 'Books result'
            and cell_address in (
                'I4',
                'J4',

                'C40',
                'D40',
                'E40',
                'F40',
                'G40',
                'H40',
                'I40',
                'J40',

                'E4',

                'C21',
                'D21',
                'E21',
                'F21',
                'G21',
                'H21',
                'I21',
                'J21',

                'C2',
                'D2',
                'E2',
                'F2',
                'G2',
                'H2',
                'I2',
                'J2'
            )
        )

        or

        (
            sheet_name = 'Asumptions'
            and cell_address in (
                'C2',
                'E2',
                'H2',

                'D19',
                'F19',
                'H19',
                'J19',
                'L19',
                'N19',

                'K2',
                'L2',
                'M2',

                'Q19',
                'R19',
                'S19',
                'T19',
                'U19',
                'V19',
                'W19',

                'P2',
                'Q2',
                'R2',
                'S2',
                'T2'
            )
        )

        or

        (
            sheet_name = 'Sheet1'
            and cell_address in (
                'B14',
                'B5',
                'B6',
                'B7',
                'B8'
            )
        )
      );


/*
 * ==============================================================
 * 2. IDENTIFY THE 4 FALSE MERGED-CELL REJECTS
 * ==============================================================
 */

create temporary table _merged_reject_candidates
on commit drop
as
select
    reject_id,
    batch_id,
    source_location,
    error_code
from raw.import_reject
where batch_id = 1
  and error_code = 'CELL_PARSE_ERROR'
  and source_location in (
      '2026!C2',
      '2026!C4',
      '2026!C5',
      '2026!A41'
  );


/*
 * ==============================================================
 * 3. PRE-CORRECTION SOURCE-CELL SAFETY GUARDS
 * ==============================================================
 */

do $$
declare
    v_source_count bigint;
    v_candidate_count bigint;
    v_books_result_count bigint;
    v_asumptions_count bigint;
    v_sheet1_count bigint;
begin

    select count(*)
    into v_source_count
    from raw.source_cell
    where source_file_id = 1;


    if v_source_count <> 93108 then
        raise exception
            'Safety guard failed: expected 93108 source cells, found %.',
            v_source_count;
    end if;


    select count(*)
    into v_candidate_count
    from _merged_source_cell_candidates;


    if v_candidate_count <> 56 then
        raise exception
            'Safety guard failed: expected 56 artificial source cells, found %.',
            v_candidate_count;
    end if;


    select count(*)
    into v_books_result_count
    from _merged_source_cell_candidates
    where sheet_name = 'Books result';


    if v_books_result_count <> 27 then
        raise exception
            'Safety guard failed: expected 27 Books result followers, found %.',
            v_books_result_count;
    end if;


    select count(*)
    into v_asumptions_count
    from _merged_source_cell_candidates
    where sheet_name = 'Asumptions';


    if v_asumptions_count <> 24 then
        raise exception
            'Safety guard failed: expected 24 Asumptions followers, found %.',
            v_asumptions_count;
    end if;


    select count(*)
    into v_sheet1_count
    from _merged_source_cell_candidates
    where sheet_name = 'Sheet1';


    if v_sheet1_count <> 5 then
        raise exception
            'Safety guard failed: expected 5 Sheet1 followers, found %.',
            v_sheet1_count;
    end if;

end
$$;


/*
 * ==============================================================
 * 4. PRE-CORRECTION REJECT SAFETY GUARDS
 * ==============================================================
 */

do $$
declare
    v_reject_count bigint;
    v_total_batch_rejects bigint;
begin

    select count(*)
    into v_reject_count
    from _merged_reject_candidates;


    if v_reject_count <> 4 then
        raise exception
            'Safety guard failed: expected 4 false merged-cell rejects, found %.',
            v_reject_count;
    end if;


    select count(*)
    into v_total_batch_rejects
    from raw.import_reject
    where batch_id = 1;


    if v_total_batch_rejects <> 4 then
        raise exception
            'Safety guard failed: expected batch 1 to contain exactly 4 rejects, found %.',
            v_total_batch_rejects;
    end if;

end
$$;


/*
 * ==============================================================
 * 5. VERIFY IMPORT-BATCH ORIGINAL STATE
 * ==============================================================
 */

do $$
declare
    v_batch_count bigint;
begin

    select count(*)
    into v_batch_count
    from raw.import_batch
    where batch_id = 1
      and source_file_id = 1
      and run_id = 1
      and source_type = 'excel_workbook_cells'
      and status = 'loaded'
      and rows_received = 93112
      and rows_loaded = 93108
      and rows_rejected = 4;


    if v_batch_count <> 1 then
        raise exception
            'Safety guard failed: expected batch 1 state 93112 received / 93108 loaded / 4 rejected; matching rows found %.',
            v_batch_count;
    end if;

end
$$;


/*
 * ==============================================================
 * 6. VERIFY NO DOWNSTREAM REFERENCES TO THE 56 SOURCE CELLS
 * ==============================================================
 */

do $$
declare
    v_reference_count bigint;
begin

    select count(*)
    into v_reference_count
    from (

        select l.source_cell_id
        from calc.ledger_line l
        join _merged_source_cell_candidates c
          on c.source_cell_id = l.source_cell_id

        union all

        select o.source_cell_id
        from calc.override_decision o
        join _merged_source_cell_candidates c
          on c.source_cell_id = o.source_cell_id

        union all

        select b.source_cell_id
        from core.balancing_month b
        join _merged_source_cell_candidates c
          on c.source_cell_id = b.source_cell_id

        union all

        select bl.source_cell_id
        from core.balancing_month_lineage bl
        join _merged_source_cell_candidates c
          on c.source_cell_id = bl.source_cell_id

        union all

        select cp.source_cell_id
        from core.contract_price cp
        join _merged_source_cell_candidates c
          on c.source_cell_id = cp.source_cell_id

        union all

        select fr.source_cell_id
        from core.fee_rule fr
        join _merged_source_cell_candidates c
          on c.source_cell_id = fr.source_cell_id

        union all

        select fx.source_cell_id
        from core.fx_rate fx
        join _merged_source_cell_candidates c
          on c.source_cell_id = fx.source_cell_id

        union all

        select ge.source_cell_id
        from core.guarantee_exposure ge
        join _merged_source_cell_candidates c
          on c.source_cell_id = ge.source_cell_id

        union all

        select gel.source_cell_id
        from core.guarantee_exposure_lineage gel
        join _merged_source_cell_candidates c
          on c.source_cell_id = gel.source_cell_id

        union all

        select hv.source_cell_id
        from core.hourly_volume hv
        join _merged_source_cell_candidates c
          on c.source_cell_id = hv.source_cell_id

        union all

        select mp.source_cell_id
        from core.market_price mp
        join _merged_source_cell_candidates c
          on c.source_cell_id = mp.source_cell_id

        union all

        select ps.source_cell_id
        from core.procurement_schedule ps
        join _merged_source_cell_candidates c
          on c.source_cell_id = ps.source_cell_id

        union all

        select si.source_cell_id
        from core.service_income si
        join _merged_source_cell_candidates c
          on c.source_cell_id = si.source_cell_id

        union all

        select t.source_cell_id
        from core.trade t
        join _merged_source_cell_candidates c
          on c.source_cell_id = t.source_cell_id

        union all

        select f.source_cell_id
        from raw.formula_reference f
        join _merged_source_cell_candidates c
          on c.source_cell_id = f.source_cell_id

    ) referenced;


    if v_reference_count <> 0 then
        raise exception
            'Safety guard failed: % downstream references exist to artificial merged follower cells.',
            v_reference_count;
    end if;

end
$$;


/*
 * ==============================================================
 * 7. DELETE THE 56 ARTIFICIAL SOURCE CELLS
 * ==============================================================
 */

do $$
declare
    v_deleted bigint;
begin

    delete from raw.source_cell sc
    using _merged_source_cell_candidates c
    where sc.source_cell_id = c.source_cell_id;


    get diagnostics v_deleted = row_count;


    if v_deleted <> 56 then
        raise exception
            'Correction failed: expected to delete 56 source cells, deleted %.',
            v_deleted;
    end if;

end
$$;


/*
 * ==============================================================
 * 8. DELETE THE 4 FALSE IMPORT REJECTS
 * ==============================================================
 */

do $$
declare
    v_deleted bigint;
begin

    delete from raw.import_reject r
    using _merged_reject_candidates c
    where r.reject_id = c.reject_id;


    get diagnostics v_deleted = row_count;


    if v_deleted <> 4 then
        raise exception
            'Correction failed: expected to delete 4 false rejects, deleted %.',
            v_deleted;
    end if;

end
$$;


/*
 * ==============================================================
 * 9. CORRECT IMPORT-BATCH COUNTS
 * ==============================================================
 */

do $$
declare
    v_updated bigint;
begin

    update raw.import_batch
    set
        rows_received = 93052,
        rows_loaded = 93052,
        rows_rejected = 0
    where batch_id = 1
      and source_file_id = 1
      and run_id = 1
      and source_type = 'excel_workbook_cells'
      and status = 'loaded'
      and rows_received = 93112
      and rows_loaded = 93108
      and rows_rejected = 4;


    get diagnostics v_updated = row_count;


    if v_updated <> 1 then
        raise exception
            'Correction failed: expected to update exactly one import batch, updated %.',
            v_updated;
    end if;

end
$$;


/*
 * ==============================================================
 * 10. POST-CORRECTION VALIDATION
 * ==============================================================
 */

do $$
declare
    v_source_count bigint;
    v_remaining_source_candidates bigint;
    v_remaining_rejects bigint;
    v_batch_count bigint;
begin

    select count(*)
    into v_source_count
    from raw.source_cell
    where source_file_id = 1;


    if v_source_count <> 93052 then
        raise exception
            'Post-correction validation failed: expected 93052 source cells, found %.',
            v_source_count;
    end if;


    select count(*)
    into v_remaining_source_candidates
    from raw.source_cell sc
    join _merged_source_cell_candidates c
      on c.source_cell_id = sc.source_cell_id;


    if v_remaining_source_candidates <> 0 then
        raise exception
            'Post-correction validation failed: % artificial source cells remain.',
            v_remaining_source_candidates;
    end if;


    select count(*)
    into v_remaining_rejects
    from raw.import_reject
    where batch_id = 1;


    if v_remaining_rejects <> 0 then
        raise exception
            'Post-correction validation failed: % import rejects remain for batch 1.',
            v_remaining_rejects;
    end if;


    select count(*)
    into v_batch_count
    from raw.import_batch
    where batch_id = 1
      and source_file_id = 1
      and run_id = 1
      and source_type = 'excel_workbook_cells'
      and status = 'loaded'
      and rows_received = 93052
      and rows_loaded = 93052
      and rows_rejected = 0;


    if v_batch_count <> 1 then
        raise exception
            'Post-correction validation failed: corrected import batch state not found.';
    end if;

end
$$;


/*
 * ==============================================================
 * 11. COMMIT
 * ==============================================================
 */

commit;


/*
 * ==============================================================
 * 12. RESULT PREVIEW
 * ==============================================================
 */

select
    count(*) as canonical_source_cells
from raw.source_cell
where source_file_id = 1;


select
    batch_id,
    run_id,
    source_file_id,
    source_type,
    status,
    rows_received,
    rows_loaded,
    rows_rejected,
    completed_at
from raw.import_batch
where batch_id = 1;


select
    count(*) as remaining_batch_rejects
from raw.import_reject
where batch_id = 1;