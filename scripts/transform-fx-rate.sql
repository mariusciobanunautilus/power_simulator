-- Power Simulator
-- Transform workbook FX conventions into core.fx_rate.
--
-- Workbook evidence:
--
--   Books result!D3  = 5.24
--     Sourcing Book conversion assumption.
--
--   Books result!D22 = 5.24
--     Optimisation Book conversion assumption.
--
--   Books result!D41 = 5.24
--     Origination Book conversion assumption.
--
--   Costuri tranzationare formulas use 5.10
--     Guarantee / SGB conversion convention.
--
--   Books result!G26 formula uses 5.10
--     February optimisation exception.
--
--   2026!F50 formula uses 4.97
--     Annual saved RON-to-EUR result conversion.
--
-- The workbook does not provide effective dates for these annual assumptions.
-- 2026-01-01 is therefore used as the model-year anchor except for the
-- February-specific optimisation exception, which uses 2026-02-01.
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
        from core.fx_rate
        where run_id = 1
          and rate_context in (
              'sourcing_book',
              'optimisation_book',
              'origination_book',
              'guarantee_sgb',
              'optimisation_february_exception',
              'annual_2026_saved_result'
          )
    ) then
        raise exception
            'FX transformation rows already exist for run_id = 1. Transformation aborted.';
    end if;

end
$$;


-- ============================================================
-- LOAD EXPLICIT 5.24 BOOK FX INPUTS
-- ============================================================

insert into core.fx_rate (
    run_id,
    rate_date,
    rate_purpose,
    ron_per_eur,
    source_cell_id,
    rate_context,
    source_basis,
    source_note
)
select
    1::bigint as run_id,
    date '2026-01-01' as rate_date,
    'reporting'::text as rate_purpose,
    coalesce(sc.cached_text, sc.raw_text)::numeric as ron_per_eur,
    sc.source_cell_id,
    case sc.cell_address
        when 'D3'  then 'sourcing_book'
        when 'D22' then 'optimisation_book'
        when 'D41' then 'origination_book'
    end as rate_context,
    'explicit_input'::text as source_basis,
    case sc.cell_address
        when 'D3' then
            'Explicit 1 EUR = 5.24 RON input for the 2026 Sourcing Book. 2026-01-01 is a model-year anchor because the workbook provides no effective date.'
        when 'D22' then
            'Explicit 1 EUR = 5.24 RON input for the 2026 Sourcing Book optimisation section. 2026-01-01 is a model-year anchor because the workbook provides no effective date.'
        when 'D41' then
            'Explicit 1 EUR = 5.24 RON input for the 2026 Origination Book. 2026-01-01 is a model-year anchor because the workbook provides no effective date.'
    end as source_note
from raw.source_cell sc
where sc.source_file_id = 1
  and sc.sheet_name = 'Books result'
  and sc.cell_address in (
      'D3',
      'D22',
      'D41'
  );


-- ============================================================
-- LOAD 5.10 GUARANTEE / SGB FORMULA CONVENTION
-- ============================================================

insert into core.fx_rate (
    run_id,
    rate_date,
    rate_purpose,
    ron_per_eur,
    source_cell_id,
    rate_context,
    source_basis,
    source_note
)
select
    1::bigint,
    date '2026-01-01',
    'guarantee',
    5.10::numeric,
    sc.source_cell_id,
    'guarantee_sgb',
    'embedded_formula',
    '5.10 RON/EUR is embedded directly in the Costuri tranzationare SGB formula. 2026-01-01 is a model-year anchor because the workbook provides no effective date.'
from raw.source_cell sc
where sc.source_file_id = 1
  and sc.sheet_name = 'Costuri tranzationare'
  and sc.cell_address = 'C56'
  and sc.formula_text like '%/5.1%';


-- ============================================================
-- LOAD FEBRUARY OPTIMISATION 5.10 EXCEPTION
-- ============================================================

insert into core.fx_rate (
    run_id,
    rate_date,
    rate_purpose,
    ron_per_eur,
    source_cell_id,
    rate_context,
    source_basis,
    source_note
)
select
    1::bigint,
    date '2026-02-01',
    'reporting',
    5.10::numeric,
    sc.source_cell_id,
    'optimisation_february_exception',
    'embedded_formula',
    'February optimisation margin uses an embedded divisor of 5.10 in Books result!G26 instead of the section-level 5.24 input.'
from raw.source_cell sc
where sc.source_file_id = 1
  and sc.sheet_name = 'Books result'
  and sc.cell_address = 'G26'
  and sc.formula_text like '%/5.1%';


-- ============================================================
-- LOAD ANNUAL 4.97 CONVERSION
-- ============================================================

insert into core.fx_rate (
    run_id,
    rate_date,
    rate_purpose,
    ron_per_eur,
    source_cell_id,
    rate_context,
    source_basis,
    source_note
)
select
    1::bigint,
    date '2026-01-01',
    'reporting',
    4.97::numeric,
    sc.source_cell_id,
    'annual_2026_saved_result',
    'embedded_formula',
    'Annual 2026 saved result converts 2026!F49 from RON to EUR using an embedded divisor of 4.97 in 2026!F50. The workbook does not label the economic purpose of this rate.'
from raw.source_cell sc
where sc.source_file_id = 1
  and sc.sheet_name = '2026'
  and sc.cell_address = 'F50'
  and sc.formula_text like '%/4.97%';


-- ============================================================
-- VALIDATION
-- ============================================================

do $$
declare
    fx_rows integer;
    explicit_rows integer;
    embedded_rows integer;
    rate_524_rows integer;
    rate_510_rows integer;
    rate_497_rows integer;
begin

    select count(*)
    into fx_rows
    from core.fx_rate
    where run_id = 1
      and rate_context in (
          'sourcing_book',
          'optimisation_book',
          'origination_book',
          'guarantee_sgb',
          'optimisation_february_exception',
          'annual_2026_saved_result'
      );

    if fx_rows <> 6 then
        raise exception
            'Expected 6 workbook FX records, found %',
            fx_rows;
    end if;


    select count(*)
    into explicit_rows
    from core.fx_rate
    where run_id = 1
      and source_basis = 'explicit_input'
      and rate_context in (
          'sourcing_book',
          'optimisation_book',
          'origination_book'
      );

    if explicit_rows <> 3 then
        raise exception
            'Expected 3 explicit FX input records, found %',
            explicit_rows;
    end if;


    select count(*)
    into embedded_rows
    from core.fx_rate
    where run_id = 1
      and source_basis = 'embedded_formula'
      and rate_context in (
          'guarantee_sgb',
          'optimisation_february_exception',
          'annual_2026_saved_result'
      );

    if embedded_rows <> 3 then
        raise exception
            'Expected 3 embedded-formula FX records, found %',
            embedded_rows;
    end if;


    select count(*)
    into rate_524_rows
    from core.fx_rate
    where run_id = 1
      and ron_per_eur = 5.24
      and rate_context in (
          'sourcing_book',
          'optimisation_book',
          'origination_book'
      );

    if rate_524_rows <> 3 then
        raise exception
            'Expected 3 FX records at 5.24 RON/EUR, found %',
            rate_524_rows;
    end if;


    select count(*)
    into rate_510_rows
    from core.fx_rate
    where run_id = 1
      and ron_per_eur = 5.10
      and rate_context in (
          'guarantee_sgb',
          'optimisation_february_exception'
      );

    if rate_510_rows <> 2 then
        raise exception
            'Expected 2 FX records at 5.10 RON/EUR, found %',
            rate_510_rows;
    end if;


    select count(*)
    into rate_497_rows
    from core.fx_rate
    where run_id = 1
      and ron_per_eur = 4.97
      and rate_context = 'annual_2026_saved_result';

    if rate_497_rows <> 1 then
        raise exception
            'Expected 1 FX record at 4.97 RON/EUR, found %',
            rate_497_rows;
    end if;

end
$$;


commit;


-- ============================================================
-- RESULT PREVIEW
-- ============================================================

select
    fx.rate_date,
    fx.rate_purpose,
    fx.rate_context,
    fx.ron_per_eur,
    fx.source_basis,
    sc.sheet_name,
    sc.cell_address,
    sc.formula_text,
    fx.source_note
from core.fx_rate fx
left join raw.source_cell sc
    on sc.source_cell_id = fx.source_cell_id
where fx.run_id = 1
  and fx.rate_context in (
      'sourcing_book',
      'optimisation_book',
      'origination_book',
      'guarantee_sgb',
      'optimisation_february_exception',
      'annual_2026_saved_result'
  )
order by
    fx.rate_date,
    fx.rate_context;