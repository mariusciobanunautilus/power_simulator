-- Power Simulator
-- Extend FX rate context and provenance
--
-- Workbook evidence contains three distinct RON/EUR conventions:
--
--   5.24
--     Explicit workbook input.
--     Used across Sourcing, Optimisation and Origination book calculations.
--
--   5.10
--     Embedded formula constant.
--     Used for SGB / guarantee calculations and one February optimisation row.
--
--   4.97
--     Embedded formula constant.
--     Used for the annual 2026 RON-to-EUR result.
--
-- These rates must remain distinguishable without assigning unsupported
-- business meaning to formula constants that are not explicitly labelled.

begin;

-- ============================================================
-- REMOVE EXISTING PRIMARY KEY
-- ============================================================

alter table core.fx_rate
    drop constraint fx_rate_pkey;


-- ============================================================
-- ADD FX CONTEXT
-- ============================================================

alter table core.fx_rate
    add column rate_context text not null default 'default';


-- ============================================================
-- ADD SOURCE CLASSIFICATION
-- ============================================================

alter table core.fx_rate
    add column source_basis text not null default 'explicit_input'
        check (
            source_basis in (
                'explicit_input',
                'embedded_formula',
                'external_source',
                'manual_override'
            )
        );


-- ============================================================
-- ADD SOURCE NOTE
-- ============================================================

alter table core.fx_rate
    add column source_note text;


-- ============================================================
-- RECREATE PRIMARY KEY
-- ============================================================

alter table core.fx_rate
    add constraint fx_rate_pkey
        primary key (
            run_id,
            rate_date,
            rate_purpose,
            rate_context
        );


-- ============================================================
-- DOCUMENTATION
-- ============================================================

comment on column core.fx_rate.rate_context is
'Specific calculation context in which the FX rate is applied. Allows distinct workbook FX conventions to coexist for the same run and date.';

comment on column core.fx_rate.source_basis is
'Describes how the FX rate is evidenced: explicit workbook input, embedded formula constant, external source or manual override.';

comment on column core.fx_rate.source_note is
'Human-readable provenance and workbook-equivalent usage notes for the FX rate.';


commit;