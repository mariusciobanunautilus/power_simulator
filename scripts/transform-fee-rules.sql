-- Power Simulator
-- Transform workbook transaction-fee assumptions into core.fee_rule
--
-- Source workbook:
--   sheet: Costuri tranzationare
--
-- Variable tariffs:
--   rows 4,5,6,7,9   = purchase tariffs
--   rows 13,14       = sale tariffs
--
-- Fixed annual tariffs:
--   rows 19,20
--
-- Run used to determine model year:
--   core.model_run.run_id = 1


begin;


-- ============================================================
-- SAFETY GUARD
-- ============================================================
-- fee_rule is effective-dated reference data and does not contain
-- run_id, therefore do not insert a second 2026 tariff set.

do $$
begin
    if exists (
        select 1
        from core.fee_rule
        where valid_from = date '2026-01-01'
          and valid_to   = date '2026-12-31'
          and venue in (
              'OTC',
              'PCCB_FLEX',
              'TERMEN_BRM',
              'PZU_PI_BRM',
              'CV',
              'PZU',
              'OPCOM_ANNUAL',
              'BRM_ANNUAL'
          )
    ) then
        raise exception
            '2026 transaction fee rules already exist. Transformation aborted.';
    end if;
end
$$;


-- ============================================================
-- EXTRACT WORKBOOK SOURCE
-- ============================================================

with source_cells as (
    select
        sc.source_cell_id,

        regexp_replace(
            sc.cell_address,
            '\D',
            '',
            'g'
        )::integer as row_no,

        regexp_replace(
            sc.cell_address,
            '\d',
            '',
            'g'
        ) as column_code,

        coalesce(
            sc.cached_text,
            sc.raw_text
        ) as value_text

    from raw.source_cell sc

    where sc.source_file_id = 1
      and sc.sheet_name = 'Costuri tranzationare'
      and sc.cell_address ~ '^[ACE](4|5|6|7|9|13|14|19|20)$'
),

pivoted as (
    select
        row_no,

        max(value_text)
            filter (
                where column_code = 'A'
            ) as source_label,

        max(value_text)
            filter (
                where column_code = 'C'
            ) as rate_text,

        max(value_text)
            filter (
                where column_code = 'E'
            ) as fixed_amount_text,

        max(source_cell_id)
            filter (
                where column_code = 'C'
            ) as rate_source_cell_id,

        max(source_cell_id)
            filter (
                where column_code = 'E'
            ) as fixed_source_cell_id

    from source_cells

    group by row_no
),

prepared as (
    select
        case row_no
            when 4  then 'OTC'
            when 5  then 'PCCB_FLEX'
            when 6  then 'TERMEN_BRM'
            when 7  then 'PZU_PI_BRM'
            when 9  then 'CV'
            when 13 then 'OTC'
            when 14 then 'PZU'
            when 19 then 'OPCOM_ANNUAL'
            when 20 then 'BRM_ANNUAL'
        end as venue,

        case
            when row_no in (4,5,6,7,9)
                then 'buy'

            when row_no in (13,14)
                then 'sell'

            when row_no in (19,20)
                then 'both'
        end as direction,

        case
            when row_no in (4,5,6,7,9,13,14)
                then rate_text::numeric
            else null
        end as rate_per_mwh,

        case
            when row_no in (19,20)
                then fixed_amount_text::numeric
            else null
        end as fixed_amount,

        case
            when row_no in (4,5,6,7,9,13,14)
                then rate_source_cell_id
            else fixed_source_cell_id
        end as source_cell_id

    from pivoted
)

insert into core.fee_rule (
    venue,
    direction,
    product_id,
    valid_from,
    valid_to,
    rate_per_mwh,
    fixed_amount,
    currency_code,
    source_cell_id
)

select
    p.venue,
    p.direction,

    -- No workbook evidence currently identifies a specific
    -- core.product for these generic transaction tariffs.
    null as product_id,

    make_date(
        mr.model_year,
        1,
        1
    ) as valid_from,

    make_date(
        mr.model_year,
        12,
        31
    ) as valid_to,

    p.rate_per_mwh,
    p.fixed_amount,

    'RON'::char(3) as currency_code,

    p.source_cell_id

from prepared p

cross join core.model_run mr

where mr.run_id = 1

order by
    p.venue,
    p.direction;


-- ============================================================
-- VALIDATION
-- ============================================================

do $$
declare
    fee_rows integer;
    variable_rows integer;
    fixed_rows integer;
begin

    select count(*)
    into fee_rows
    from core.fee_rule
    where valid_from = date '2026-01-01'
      and valid_to   = date '2026-12-31';

    if fee_rows <> 9 then
        raise exception
            'Expected 9 fee rules for 2026, found %',
            fee_rows;
    end if;


    select count(*)
    into variable_rows
    from core.fee_rule
    where valid_from = date '2026-01-01'
      and valid_to   = date '2026-12-31'
      and rate_per_mwh is not null;

    if variable_rows <> 7 then
        raise exception
            'Expected 7 variable transaction tariffs, found %',
            variable_rows;
    end if;


    select count(*)
    into fixed_rows
    from core.fee_rule
    where valid_from = date '2026-01-01'
      and valid_to   = date '2026-12-31'
      and fixed_amount is not null;

    if fixed_rows <> 2 then
        raise exception
            'Expected 2 fixed annual tariffs, found %',
            fixed_rows;
    end if;

end
$$;


commit;


-- ============================================================
-- RESULT PREVIEW
-- ============================================================

select
    fee_rule_id,
    venue,
    direction,
    valid_from,
    valid_to,
    rate_per_mwh,
    fixed_amount,
    currency_code,
    source_cell_id

from core.fee_rule

where valid_from = date '2026-01-01'
  and valid_to   = date '2026-12-31'

order by
    case direction
        when 'buy'  then 1
        when 'sell' then 2
        when 'both' then 3
    end,
    venue;