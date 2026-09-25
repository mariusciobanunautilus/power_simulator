-- Power Simulator
-- Seed canonical Romanian hourly settlement intervals for calendar year 2026.
--
-- Time zone:
--   Europe/Bucharest
--
-- Design:
--   Each database row represents one real UTC hour.
--   Romanian local date/hour labels are derived from UTC.
--
-- This automatically preserves daylight-saving-time behaviour:
--
--   March 2026:
--     743 physical hours
--
--   October 2026:
--     745 physical hours
--
-- The repeated autumn hour is distinguished through local_occurrence:
--   first occurrence  = 1
--   repeated occurrence = 2
--
-- local_hour_label follows the workbook-style hour numbering:
--   00:00-01:00 local = hour 1
--   ...
--   23:00-00:00 local = hour 24
--
-- No artificial hour 25 is generated. The schema permits 25 for future
-- market conventions, while repeated physical hours are represented by
-- local_occurrence.


begin;


-- ============================================================
-- SAFETY GUARD
-- ============================================================

do $$
begin

    if exists (
        select 1
        from core.settlement_interval
        where market_code = 'RO'
          and local_date >= date '2026-01-01'
          and local_date < date '2027-01-01'
    ) then
        raise exception
            'Romanian settlement intervals already exist for calendar year 2026. Seed aborted.';
    end if;

end
$$;


-- ============================================================
-- GENERATE REAL UTC HOURS
-- ============================================================

with utc_hours as (

    select
        gs as interval_start_utc,
        gs + interval '1 hour' as interval_end_utc

    from generate_series(
        timestamptz '2025-12-31 22:00:00+00',
        timestamptz '2026-12-31 21:00:00+00',
        interval '1 hour'
    ) as gs

),

localized as (

    select
        interval_start_utc,
        interval_end_utc,

        interval_start_utc
            at time zone 'Europe/Bucharest'
            as local_start

    from utc_hours

),

numbered as (

    select
        interval_start_utc,
        interval_end_utc,
        local_start,

        local_start::date
            as local_date,

        (
            extract(hour from local_start)::smallint
            + 1
        )::smallint
            as local_hour_label,

        row_number() over (
            partition by local_start
            order by interval_start_utc
        )::smallint
            as local_occurrence

    from localized

)

insert into core.settlement_interval (
    market_code,
    interval_start_utc,
    interval_end_utc,
    local_date,
    local_hour_label,
    local_occurrence,
    duration_hours
)

select
    'RO',
    interval_start_utc,
    interval_end_utc,
    local_date,
    local_hour_label,
    local_occurrence,
    1.00000::numeric(10,5)

from numbered

where local_date >= date '2026-01-01'
  and local_date < date '2027-01-01'

order by interval_start_utc;


-- ============================================================
-- VALIDATION
-- ============================================================

do $$
declare
    total_hours integer;
    march_hours integer;
    october_hours integer;
    repeated_hour_rows integer;
    invalid_occurrences integer;
    invalid_duration_rows integer;
begin

    -- --------------------------------------------------------
    -- Annual hour count
    -- --------------------------------------------------------

    select count(*)
    into total_hours
    from core.settlement_interval
    where market_code = 'RO'
      and local_date >= date '2026-01-01'
      and local_date < date '2027-01-01';

    if total_hours <> 8760 then
        raise exception
            'Expected 8760 Romanian settlement intervals for 2026, found %',
            total_hours;
    end if;


    -- --------------------------------------------------------
    -- March DST shortening
    -- --------------------------------------------------------

    select count(*)
    into march_hours
    from core.settlement_interval
    where market_code = 'RO'
      and local_date >= date '2026-03-01'
      and local_date < date '2026-04-01';

    if march_hours <> 743 then
        raise exception
            'Expected 743 Romanian settlement intervals in March 2026, found %',
            march_hours;
    end if;


    -- --------------------------------------------------------
    -- October DST repetition
    -- --------------------------------------------------------

    select count(*)
    into october_hours
    from core.settlement_interval
    where market_code = 'RO'
      and local_date >= date '2026-10-01'
      and local_date < date '2026-11-01';

    if october_hours <> 745 then
        raise exception
            'Expected 745 Romanian settlement intervals in October 2026, found %',
            october_hours;
    end if;


    -- --------------------------------------------------------
    -- Exactly one repeated physical local hour
    -- --------------------------------------------------------

    select count(*)
    into repeated_hour_rows
    from core.settlement_interval
    where market_code = 'RO'
      and local_date >= date '2026-01-01'
      and local_date < date '2027-01-01'
      and local_occurrence = 2;

    if repeated_hour_rows <> 1 then
        raise exception
            'Expected exactly 1 repeated local-hour row in 2026, found %',
            repeated_hour_rows;
    end if;


    -- --------------------------------------------------------
    -- Occurrence range
    -- --------------------------------------------------------

    select count(*)
    into invalid_occurrences
    from core.settlement_interval
    where market_code = 'RO'
      and local_date >= date '2026-01-01'
      and local_date < date '2027-01-01'
      and local_occurrence not in (1, 2);

    if invalid_occurrences <> 0 then
        raise exception
            'Found % settlement intervals with invalid local_occurrence',
            invalid_occurrences;
    end if;


    -- --------------------------------------------------------
    -- Duration
    -- --------------------------------------------------------

    select count(*)
    into invalid_duration_rows
    from core.settlement_interval
    where market_code = 'RO'
      and local_date >= date '2026-01-01'
      and local_date < date '2027-01-01'
      and duration_hours <> 1;

    if invalid_duration_rows <> 0 then
        raise exception
            'Found % settlement intervals with duration other than one hour',
            invalid_duration_rows;
    end if;

end
$$;


commit;


-- ============================================================
-- RESULT PREVIEW: MONTHLY PHYSICAL HOURS
-- ============================================================

select
    date_trunc(
        'month',
        local_date::timestamp
    )::date as month_start,

    count(*) as physical_hours

from core.settlement_interval

where market_code = 'RO'
  and local_date >= date '2026-01-01'
  and local_date < date '2027-01-01'

group by 1

order by 1;


-- ============================================================
-- RESULT PREVIEW: DST EXCEPTIONS
-- ============================================================

select
    local_date,
    count(*) as physical_hours

from core.settlement_interval

where market_code = 'RO'
  and local_date >= date '2026-01-01'
  and local_date < date '2027-01-01'

group by local_date

having count(*) <> 24

order by local_date;