-- Power Simulator
-- Transform guarantee / collateral exposures from workbook evidence
-- into core.guarantee_exposure with field-level lineage.
--
-- Source workbook:
--   sheet: Costuri tranzationare
--   header currency: A30 = Value ( RON )
--   exposure rows: 31:34
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
        from core.guarantee_exposure
        where run_id = 1
          and exposure_code in (
              'SGB_31',
              'SGB_32',
              'SGB_33',
              'SGB_34'
          )
    ) then
        raise exception
            'Guarantee exposures already exist for run_id = 1. Transformation aborted.';
    end if;
end
$$;


-- ============================================================
-- EXTRACT AND LOAD EXPOSURES
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
      and sc.cell_address ~ '^[A-G](31|32|33|34)$'
),

pivoted as (
    select
        row_no,

        max(value_text)
            filter (where column_code = 'A')
            as amount_text,

        max(value_text)
            filter (where column_code = 'B')
            as beneficiary,

        max(value_text)
            filter (where column_code = 'C')
            as bank_name,

        max(value_text)
            filter (where column_code = 'D')
            as guarantee_type,

        max(value_text)
            filter (where column_code = 'E')
            as annual_interest_rate_text,

        max(value_text)
            filter (where column_code = 'F')
            as annual_cost_text,

        max(value_text)
            filter (where column_code = 'G')
            as exposure_purpose

    from source_cells

    group by row_no
),

prepared as (
    select
        1::bigint as run_id,

        'SGB_' || row_no
            as exposure_code,

        nullif(
            btrim(beneficiary),
            ''
        ) as beneficiary,

        nullif(
            btrim(bank_name),
            ''
        ) as bank_name,

        nullif(
            btrim(guarantee_type),
            ''
        ) as guarantee_type,

        amount_text::numeric
            as amount,

        'RON'::char(3)
            as currency_code,

        annual_interest_rate_text::numeric
            as annual_interest_rate,

        nullif(
            btrim(exposure_purpose),
            ''
        ) as exposure_purpose,

        coalesce(
            annual_cost_text::numeric,
            0
        ) as annual_cost_ron

    from pivoted
)

insert into core.guarantee_exposure (
    run_id,
    exposure_code,
    beneficiary,
    guarantee_type,
    amount,
    currency_code,
    annual_cost_ron,
    source_cell_id,
    bank_name,
    annual_interest_rate,
    exposure_purpose
)

select
    run_id,
    exposure_code,
    beneficiary,
    guarantee_type,
    amount,
    currency_code,
    annual_cost_ron,

    -- Exposure is assembled from multiple workbook cells.
    -- Detailed provenance is stored separately.
    null as source_cell_id,

    bank_name,
    annual_interest_rate,
    exposure_purpose

from prepared

order by exposure_code;


-- ============================================================
-- LOAD FIELD-LEVEL LINEAGE
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
        ) as column_code

    from raw.source_cell sc

    where sc.source_file_id = 1
      and sc.sheet_name = 'Costuri tranzationare'
      and sc.cell_address ~ '^[A-G](31|32|33|34)$'
),

currency_source as (
    select
        source_cell_id
    from raw.source_cell
    where source_file_id = 1
      and sheet_name = 'Costuri tranzationare'
      and cell_address = 'A30'
),

field_lineage as (
    select
        1::bigint as run_id,

        'SGB_' || row_no
            as exposure_code,

        case column_code
            when 'A' then 'amount'
            when 'B' then 'beneficiary'
            when 'C' then 'bank_name'
            when 'D' then 'guarantee_type'
            when 'E' then 'annual_interest_rate'
            when 'F' then 'annual_cost_ron'
            when 'G' then 'exposure_purpose'
        end as source_role,

        source_cell_id

    from source_cells
),

currency_lineage as (
    select
        1::bigint as run_id,
        exposure_code,
        'currency_code'::text as source_role,
        cs.source_cell_id

    from (
        values
            ('SGB_31'),
            ('SGB_32'),
            ('SGB_33'),
            ('SGB_34')
    ) as exposures(exposure_code)

    cross join currency_source cs
),

combined as (
    select *
    from field_lineage

    union all

    select *
    from currency_lineage
)

insert into core.guarantee_exposure_lineage (
    run_id,
    exposure_code,
    source_role,
    source_cell_id
)

select
    run_id,
    exposure_code,
    source_role,
    source_cell_id

from combined

where source_role is not null
  and source_cell_id is not null

order by
    exposure_code,
    source_role;


-- ============================================================
-- VALIDATION
-- ============================================================

do $$
declare
    exposure_rows integer;
    lineage_rows integer;
    total_exposure numeric;
    total_annual_cost numeric;
begin

    select count(*)
    into exposure_rows
    from core.guarantee_exposure
    where run_id = 1
      and exposure_code like 'SGB_%';

    if exposure_rows <> 4 then
        raise exception
            'Expected 4 guarantee exposures, found %',
            exposure_rows;
    end if;


    select count(*)
    into lineage_rows
    from core.guarantee_exposure_lineage
    where run_id = 1
      and exposure_code like 'SGB_%';

    if lineage_rows <> 27 then
        raise exception
            'Expected 27 guarantee lineage records, found %',
            lineage_rows;
    end if;


    select sum(amount)
    into total_exposure
    from core.guarantee_exposure
    where run_id = 1
      and exposure_code like 'SGB_%';

    if total_exposure <> 21714221 then
        raise exception
            'Expected total guarantee exposure 21714221 RON, found %',
            total_exposure;
    end if;


    select sum(annual_cost_ron)
    into total_annual_cost
    from core.guarantee_exposure
    where run_id = 1
      and exposure_code like 'SGB_%';

    if total_annual_cost <> 434284.42 then
        raise exception
            'Expected annual financing cost 434284.42 RON, found %',
            total_annual_cost;
    end if;

end
$$;


commit;


-- ============================================================
-- RESULT PREVIEW
-- ============================================================

select
    ge.exposure_code,
    ge.beneficiary,
    ge.bank_name,
    ge.guarantee_type,
    ge.amount,
    ge.currency_code,
    ge.annual_interest_rate,
    ge.exposure_purpose,
    ge.annual_cost_ron,

    (
        select count(*)
        from core.guarantee_exposure_lineage gel
        where gel.run_id = ge.run_id
          and gel.exposure_code = ge.exposure_code
    ) as lineage_cells

from core.guarantee_exposure ge

where ge.run_id = 1
  and ge.exposure_code like 'SGB_%'

order by ge.exposure_code;