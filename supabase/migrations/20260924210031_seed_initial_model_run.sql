-- Power Simulator
-- Initial workbook-equivalent model run
-- Source: Simulare_2026_wk39.xlsx

with new_run as (
    insert into core.model_run (
        model_year,
        scenario_code,
        as_of_utc,
        method_version,
        status,
        created_by
    )
    values (
        2026,
        'as_workbook',
        '2026-09-24 21:00:31+00',
        'workbook_equivalent_v1',
        'draft',
        'initial_import'
    )
    returning run_id
)

insert into raw.source_file (
    run_id,
    filename,
    storage_path,
    sha256,
    file_size_bytes,
    source_system,
    owner_name,
    uploaded_by
)
select
    run_id,
    'Simulare_2026_wk39.xlsx',
    null,
    '5f931168f0ae465963f4c43ab9cc74f5714c2d664a03b56a17ab2e412a2c32a6',
    1262697,
    'excel_workbook',
    null,
    'initial_import'
from new_run;