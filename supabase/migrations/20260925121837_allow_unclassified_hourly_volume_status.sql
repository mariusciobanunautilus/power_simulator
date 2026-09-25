/*
 * Power Simulator
 * Allow source-backed hourly volume rows whose workbook
 * actual/forecast classification is not authoritative.
 */

alter table core.hourly_volume
    drop constraint if exists hourly_volume_record_status_check;

alter table core.hourly_volume
    add constraint hourly_volume_record_status_check
    check (
        record_status = any (
            array[
                'actual'::text,
                'forecast'::text,
                'manual_override'::text,
                'unclassified'::text
            ]
        )
    );

comment on column core.hourly_volume.record_status is
    'Source classification. Use unclassified when the workbook does not authoritatively identify the row as actual, forecast, or manual override.';
