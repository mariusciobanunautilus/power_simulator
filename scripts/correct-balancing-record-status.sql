/*
 * Power Simulator
 * Correct unsupported balancing actual/forecast inference
 *
 * Problem
 * -------
 * core.balancing_month for run_id = 1 currently contains:
 *
 *   January-August  -> actual
 *   September-Dec   -> forecast
 *
 * Those statuses were inferred from model_run.as_of_utc.
 * The workbook source does not provide an authoritative
 * actual/forecast indicator for this balancing block.
 *
 * Correct source-backed state:
 *
 *   record_status = 'unclassified'
 *
 * for all 12 balancing months in run_id = 1.
 *
 * Preconditions:
 *   - exactly 12 balancing rows exist
 *   - exactly 8 are currently actual
 *   - exactly 4 are currently forecast
 *   - no manual_override or unclassified rows already exist
 *
 * The transaction aborts if the database differs from that
 * investigated state.
 */


begin;


/*
 * ============================================================
 * 1. PRE-CORRECTION SAFETY GUARDS
 * ============================================================
 */

do $$
declare
    v_total_rows integer;
    v_actual_rows integer;
    v_forecast_rows integer;
    v_manual_override_rows integer;
    v_unclassified_rows integer;
begin

    select count(*)
    into v_total_rows
    from core.balancing_month
    where run_id = 1;


    if v_total_rows <> 12 then
        raise exception
            'Safety guard failed: expected 12 balancing rows for run_id = 1, found %.',
            v_total_rows;
    end if;


    select count(*)
    into v_actual_rows
    from core.balancing_month
    where run_id = 1
      and record_status = 'actual';


    if v_actual_rows <> 8 then
        raise exception
            'Safety guard failed: expected 8 actual rows before correction, found %.',
            v_actual_rows;
    end if;


    select count(*)
    into v_forecast_rows
    from core.balancing_month
    where run_id = 1
      and record_status = 'forecast';


    if v_forecast_rows <> 4 then
        raise exception
            'Safety guard failed: expected 4 forecast rows before correction, found %.',
            v_forecast_rows;
    end if;


    select count(*)
    into v_manual_override_rows
    from core.balancing_month
    where run_id = 1
      and record_status = 'manual_override';


    if v_manual_override_rows <> 0 then
        raise exception
            'Safety guard failed: expected 0 manual_override rows before correction, found %.',
            v_manual_override_rows;
    end if;


    select count(*)
    into v_unclassified_rows
    from core.balancing_month
    where run_id = 1
      and record_status = 'unclassified';


    if v_unclassified_rows <> 0 then
        raise exception
            'Safety guard failed: expected 0 unclassified rows before correction, found %.',
            v_unclassified_rows;
    end if;

end
$$;


/*
 * ============================================================
 * 2. CORRECT RECORD STATUS
 * ============================================================
 */

do $$
declare
    v_updated integer;
begin

    update core.balancing_month
    set record_status = 'unclassified'
    where run_id = 1
      and record_status in ('actual', 'forecast');


    get diagnostics v_updated = row_count;


    if v_updated <> 12 then
        raise exception
            'Correction failed: expected to update 12 balancing rows, updated %.',
            v_updated;
    end if;

end
$$;


/*
 * ============================================================
 * 3. POST-CORRECTION VALIDATION
 * ============================================================
 */

do $$
declare
    v_total_rows integer;
    v_unclassified_rows integer;
    v_non_unclassified_rows integer;
begin

    select count(*)
    into v_total_rows
    from core.balancing_month
    where run_id = 1;


    if v_total_rows <> 12 then
        raise exception
            'Post-correction validation failed: expected 12 balancing rows, found %.',
            v_total_rows;
    end if;


    select count(*)
    into v_unclassified_rows
    from core.balancing_month
    where run_id = 1
      and record_status = 'unclassified';


    if v_unclassified_rows <> 12 then
        raise exception
            'Post-correction validation failed: expected 12 unclassified rows, found %.',
            v_unclassified_rows;
    end if;


    select count(*)
    into v_non_unclassified_rows
    from core.balancing_month
    where run_id = 1
      and record_status <> 'unclassified';


    if v_non_unclassified_rows <> 0 then
        raise exception
            'Post-correction validation failed: % rows still have a non-unclassified status.',
            v_non_unclassified_rows;
    end if;

end
$$;


/*
 * ============================================================
 * 4. COMMIT
 * ============================================================
 */

commit;


/*
 * ============================================================
 * 5. RESULT PREVIEW
 * ============================================================
 */

select
    month_start,
    record_status,
    deficit_mwh,
    deficit_ron_per_mwh,
    excess_mwh,
    excess_ron_per_mwh,
    redistribution_income_ron
from core.balancing_month
where run_id = 1
order by month_start;


select
    record_status,
    count(*) as row_count
from core.balancing_month
where run_id = 1
group by record_status
order by record_status;