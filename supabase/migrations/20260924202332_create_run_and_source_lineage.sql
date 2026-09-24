-- Power Simulator
-- Model run versioning and raw source lineage

-- ============================================================
-- CORE: MODEL RUN
-- ============================================================

create table core.model_run (
    run_id bigint generated always as identity primary key,

    model_year integer not null
        check (model_year between 2000 and 2100),

    scenario_code text not null,

    as_of_utc timestamptz not null,

    method_version text not null,

    status text not null default 'draft'
        check (
            status in (
                'draft',
                'validated',
                'approved',
                'published',
                'rejected'
            )
        ),

    created_by text,
    created_at timestamptz not null default now(),

    approved_by text,
    approved_at timestamptz,

    unique (
        model_year,
        scenario_code,
        as_of_utc,
        method_version
    )
);

comment on table core.model_run is
'One versioned execution of the Power Simulator model for a year, scenario, as-of timestamp and calculation method.';


-- ============================================================
-- RAW: SOURCE FILE
-- ============================================================

create table raw.source_file (
    source_file_id bigint generated always as identity primary key,

    run_id bigint not null
        references core.model_run(run_id),

    filename text not null,

    storage_path text,

    sha256 char(64) not null,

    file_size_bytes bigint
        check (file_size_bytes is null or file_size_bytes >= 0),

    source_system text,

    owner_name text,

    uploaded_by text,

    uploaded_at timestamptz not null default now(),

    unique (run_id, sha256)
);

comment on table raw.source_file is
'Immutable manifest of source files used by a model run, including hash and Storage location.';


-- ============================================================
-- RAW: SOURCE CELL
-- ============================================================

create table raw.source_cell (
    source_cell_id bigint generated always as identity primary key,

    source_file_id bigint not null
        references raw.source_file(source_file_id),

    sheet_name text not null,

    cell_address text not null,

    raw_text text,

    formula_text text,

    cached_text text,

    number_format text,

    value_status text not null
        check (
            value_status in (
                'manual',
                'formula',
                'blank',
                'error'
            )
        ),

    parse_error text,

    unique (
        source_file_id,
        sheet_name,
        cell_address
    )
);

comment on table raw.source_cell is
'Cell-level workbook evidence preserving original values, formulas, cached results and parsing status.';


-- ============================================================
-- RAW: FORMULA REFERENCES
-- ============================================================

create table raw.formula_reference (
    formula_reference_id bigint generated always as identity primary key,

    source_cell_id bigint not null
        references raw.source_cell(source_cell_id)
        on delete cascade,

    token_ordinal integer not null
        check (token_ordinal > 0),

    reference_text text not null,

    resolved_sheet_name text,

    resolved_range text,

    parse_status text not null default 'resolved'
        check (
            parse_status in (
                'resolved',
                'partial',
                'unresolved'
            )
        ),

    unique (
        source_cell_id,
        token_ordinal
    )
);

comment on table raw.formula_reference is
'Individual formula reference tokens extracted from workbook formulas for dependency analysis.';


-- ============================================================
-- RAW: IMPORT BATCH
-- ============================================================

create table raw.import_batch (
    batch_id bigint generated always as identity primary key,

    run_id bigint not null
        references core.model_run(run_id),

    source_file_id bigint
        references raw.source_file(source_file_id),

    source_type text not null,

    source_period_start date,

    source_period_end date,

    started_at timestamptz not null default now(),

    completed_at timestamptz,

    rows_received bigint not null default 0
        check (rows_received >= 0),

    rows_loaded bigint not null default 0
        check (rows_loaded >= 0),

    rows_rejected bigint not null default 0
        check (rows_rejected >= 0),

    batch_checksum text,

    status text not null default 'started'
        check (
            status in (
                'started',
                'parsed',
                'loaded',
                'failed',
                'rejected'
            )
        ),

    check (
        source_period_end is null
        or source_period_start is null
        or source_period_end >= source_period_start
    )
);

comment on table raw.import_batch is
'One ingestion execution for a source file or external data feed.';


-- ============================================================
-- RAW: IMPORT REJECT
-- ============================================================

create table raw.import_reject (
    reject_id bigint generated always as identity primary key,

    batch_id bigint not null
        references raw.import_batch(batch_id)
        on delete cascade,

    source_location text,

    error_code text not null,

    offending_value text,

    error_message text not null,

    remediation text,

    created_at timestamptz not null default now()
);

comment on table raw.import_reject is
'Rows, cells or records rejected during ingestion. Rejected source data must never disappear silently.';


-- ============================================================
-- INDEXES
-- ============================================================

create index ix_source_file_run
    on raw.source_file(run_id);

create index ix_source_cell_file
    on raw.source_cell(source_file_id);

create index ix_formula_reference_cell
    on raw.formula_reference(source_cell_id);

create index ix_import_batch_run
    on raw.import_batch(run_id);

create index ix_import_reject_batch
    on raw.import_reject(batch_id);