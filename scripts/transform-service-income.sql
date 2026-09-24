-- Power Simulator
-- Transform monthly service income into core.service_income
-- and preserve the workbook annual-total mismatch as a reconciliation result.
--
-- Source workbook:
--   sheet: renew+services
--   monthly values: D2:O2
--   annual total: P2
--
-- Business interpretation:
--   B2 = Venituri servicii
--   C2 = RON
--
-- Run:
--   core.model_run.run_id = 1


begin;


-- ============================================================
-- SAFETY GUARD
-- ============================================================

do $$
begin
    if exists (
        select 1
        from core.service_income
        where run_id = 1
          and service_code = 'VENITURI_SERVICII'
    ) then
        raise exception
            'Service income already exists for run_id = 1 and service_code = VENITURI_SERVICII.';
    end if;

    if exists (
        select 1
        from calc.reconciliation_result
        where run_id = 1
          and reconciliation_code = 'SERVICE_INCOME_ANNUAL_TOTAL'
    ) then
        raise exception
            'Service income annual reconciliation already exists for run_id = 1.';
    end if;
end
$$;


-- ============================================================
-- LOAD MONTHLY SERVICE INCOME
-- ============================================================

with month_map(column_code, month_no) as (
    values
        ('D', 1),
        ('E', 2),
        ('F', 3),
        ('G', 4),
        ('H', 5),
        ('I', 6),
        ('J', 7),
        ('K', 8),
        ('L', 9),
        ('M', 10),
        ('N', 11),
        ('O', 12)
),

source_rows as (
    select
        sc.source_cell_id,

        regexp_replace(
            sc.cell_address,
            '\d',
            '',
            'g'
        ) as column_code,

        coalesce(
            sc.cached_text,
            sc.raw_text
        )::numeric as amount_ron

    from raw.source_cell sc

    where sc.source_file_id = 1
      and sc.sheet_name = 'renew+services'
      and sc.cell_address ~ '^[D-O]2$'
),

prepared as (
    select
        mr.run_id,

        make_date(
            mr.model_year,
            mm.month_no,
            1
        ) as month_start,

        'VENITURI_SERVICII'::text as service_code,

        sr.amount_ron,

        'RON'::char(3) as currency_code,

        sr.source_cell_id

    from source_rows sr

    join month_map mm
      on mm.column_code = sr.column_code

    cross join core.model_run mr

    where mr.run_id = 1
)

insert into core.service_income (
    run_id,
    month_start,
    service_code,
    counterparty_id,
    amount,
    currency_code,
    source_cell_id
)

select
    run_id,
    month_start,
    service_code,
    null as counterparty_id,
    amount_ron,
    currency_code,
    source_cell_id

from prepared

order by month_start;


-- ============================================================
-- RECORD ANNUAL-TOTAL RECONCILIATION
-- ============================================================

with workbook_total as (
    select
        coalesce(
            cached_text,
            raw_text
        )::numeric as total_ron

    from raw.source_cell

    where source_file_id = 1
      and sheet_name = 'renew+services'
      and cell_address = 'P2'
),

recalculated as (
    select
        sum(amount) as total_ron

    from core.service_income

    where run_id = 1
      and service_code = 'VENITURI_SERVICII'
)

insert into calc.reconciliation_result (
    run_id,
    reconciliation_code,
    period_start,
    period_end,
    source_value,
    recalculated_value,
    difference_value,
    tolerance,
    status,
    reason,
    owner_name
)

select
    1 as run_id,

    'SERVICE_INCOME_ANNUAL_TOTAL'
        as reconciliation_code,

    date '2026-01-01'
        as period_start,

    date '2026-12-31'
        as period_end,

    wt.total_ron
        as source_value,

    rc.total_ron
        as recalculated_value,

    rc.total_ron - wt.total_ron
        as difference_value,

    0
        as tolerance,

    case
        when rc.total_ron = wt.total_ron
        then 'matched'
        else 'mismatch'
    end
        as status,

    case
        when rc.total_ron = wt.total_ron
        then 'Workbook annual total matches the sum of monthly service income.'
        else
            'Workbook cell renew+services!P2 is a manually entered annual TOTAL and does not equal the sum of monthly service income cells D2:O2.'
    end
        as reason,

    'system'
        as owner_name

from workbook_total wt

cross join recalculated rc;


-- ============================================================
-- VALIDATION
-- ============================================================

do $$
declare
    service_rows integer;
    annual_total numeric;
    reconciliation_rows integer;
begin

    select count(*)
    into service_rows
    from core.service_income
    where run_id = 1
      and service_code = 'VENITURI_SERVICII';

    if service_rows <> 12 then
        raise exception
            'Expected 12 service-income rows, found %',
            service_rows;
    end if;


    select sum(amount)
    into annual_total
    from core.service_income
    where run_id = 1
      and service_code = 'VENITURI_SERVICII';

    if annual_total <> 543200 then
        raise exception
            'Expected monthly service-income total 543200 RON, found %',
            annual_total;
    end if;


    select count(*)
    into reconciliation_rows
    from calc.reconciliation_result
    where run_id = 1
      and reconciliation_code = 'SERVICE_INCOME_ANNUAL_TOTAL';

    if reconciliation_rows <> 1 then
        raise exception
            'Expected one service-income reconciliation row, found %',
            reconciliation_rows;
    end if;

end
$$;


commit;


-- ============================================================
-- RESULT PREVIEW
-- ============================================================

select
    si.month_start,
    si.service_code,
    si.amount as amount_ron,
    si.currency_code,
    si.source_cell_id
from core.service_income si
where si.run_id = 1
  and si.service_code = 'VENITURI_SERVICII'
order by si.month_start;


select
    reconciliation_code,
    source_value as workbook_total_ron,
    recalculated_value as calculated_total_ron,
    difference_value as difference_ron,
    tolerance,
    status,
    reason
from calc.reconciliation_result
where run_id = 1
  and reconciliation_code = 'SERVICE_INCOME_ANNUAL_TOTAL';