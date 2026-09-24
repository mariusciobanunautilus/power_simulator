-- Power Simulator
-- Extend guarantee exposure model with workbook attributes
-- and field-level source lineage.


-- ============================================================
-- EXTEND GUARANTEE EXPOSURE
-- ============================================================

alter table core.guarantee_exposure
    add column bank_name text,

    add column annual_interest_rate numeric(12,8)
        check (
            annual_interest_rate is null
            or annual_interest_rate >= 0
        ),

    add column exposure_purpose text;


comment on column core.guarantee_exposure.bank_name is
'Bank or financial institution associated with the guarantee or collateral exposure.';

comment on column core.guarantee_exposure.annual_interest_rate is
'Annual financing interest rate as represented by the source workbook.';

comment on column core.guarantee_exposure.exposure_purpose is
'Business purpose or workbook classification of the exposure, for example capacity, pre-financing or working-capital related.';

comment on column core.guarantee_exposure.source_cell_id is
'Optional single-source lineage pointer retained for compatibility. Leave NULL when a guarantee exposure is assembled from multiple workbook cells; use core.guarantee_exposure_lineage instead.';


-- ============================================================
-- GUARANTEE EXPOSURE FIELD-LEVEL LINEAGE
-- ============================================================

create table core.guarantee_exposure_lineage (
    run_id bigint not null,

    exposure_code text not null,

    source_role text not null
        check (
            source_role in (
                'beneficiary',
                'guarantee_type',
                'amount',
                'currency_code',
                'bank_name',
                'annual_interest_rate',
                'exposure_purpose',
                'annual_cost_ron'
            )
        ),

    source_cell_id bigint not null
        references raw.source_cell(source_cell_id),

    primary key (
        run_id,
        exposure_code,
        source_role
    ),

    foreign key (
        run_id,
        exposure_code
    )
        references core.guarantee_exposure(
            run_id,
            exposure_code
        )
        on delete cascade,

    unique (
        run_id,
        exposure_code,
        source_cell_id
    )
);


comment on table core.guarantee_exposure_lineage is
'Field-level workbook provenance for guarantee and collateral exposure records assembled from multiple source cells.';

comment on column core.guarantee_exposure_lineage.source_role is
'Business field represented by the referenced workbook source cell.';


-- ============================================================
-- INDEXES
-- ============================================================

create index ix_guarantee_exposure_lineage_cell
    on core.guarantee_exposure_lineage(source_cell_id);

create index ix_guarantee_exposure_bank
    on core.guarantee_exposure(bank_name);