-- Power Simulator
-- Multi-cell lineage for monthly balancing inputs

create table core.balancing_month_lineage (
    run_id bigint not null,
    month_start date not null,

    source_role text not null
        check (
            source_role in (
                'month_label',
                'deficit_mwh',
                'deficit_ron_per_mwh',
                'excess_mwh',
                'excess_ron_per_mwh',
                'redistribution_income_ron'
            )
        ),

    source_cell_id bigint not null
        references raw.source_cell(source_cell_id),

    primary key (
        run_id,
        month_start,
        source_role
    ),

    foreign key (
        run_id,
        month_start
    )
        references core.balancing_month(
            run_id,
            month_start
        )
        on delete cascade,

    unique (
        run_id,
        month_start,
        source_cell_id
    )
);

comment on table core.balancing_month_lineage is
'Cell-level provenance for each field contributing to a monthly balancing record. One balancing record may originate from multiple workbook cells.';

comment on column core.balancing_month_lineage.source_role is
'Business field represented by the referenced workbook source cell.';

comment on column core.balancing_month.source_cell_id is
'Optional single-source lineage pointer retained for compatibility. Leave NULL when a balancing record is assembled from multiple source cells; use core.balancing_month_lineage instead.';

create index ix_balancing_month_lineage_cell
    on core.balancing_month_lineage(source_cell_id);