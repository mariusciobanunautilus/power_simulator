/*
 * Power Simulator
 * Allow evidence-neutral balancing status.
 *
 * The source workbook does not identify balancing months as
 * actual or forecast. Calendar-derived inference is therefore
 * unsupported.
 *
 * "unclassified" means:
 *   source evidence exists,
 *   but actual/forecast status has not been authoritatively supplied.
 */

alter table core.balancing_month
drop constraint balancing_month_record_status_check;


alter table core.balancing_month
add constraint balancing_month_record_status_check
check (
    record_status in (
        'actual',
        'forecast',
        'manual_override',
        'unclassified'
    )
);


comment on column core.balancing_month.record_status is
'Source-backed observation status. Use unclassified when the source does not authoritatively identify actual versus forecast; never infer status from calendar position or model run date.';