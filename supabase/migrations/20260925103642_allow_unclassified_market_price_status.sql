/*
 * Power Simulator
 * Allow evidence-neutral market price status.
 *
 * The workbook does not authoritatively classify PZU / market-price
 * observations as actual or forecast.
 *
 * "unclassified" means:
 *   source evidence exists,
 *   but actual/forecast status has not been authoritatively supplied.
 *
 * Status must not be inferred from calendar position, model run date,
 * workbook formatting, or apparent historical/forecast behaviour.
 */

alter table core.market_price
drop constraint market_price_record_status_check;

alter table core.market_price
add constraint market_price_record_status_check
check (
    record_status in (
        'actual',
        'forecast',
        'manual_override',
        'unclassified'
    )
);

comment on column core.market_price.record_status is
'Source-backed observation status. Use unclassified when the source does not authoritatively identify actual versus forecast; never infer status from calendar position, model run date, or workbook formatting.';