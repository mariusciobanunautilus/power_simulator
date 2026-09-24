-- Power Simulator
-- Foundation schemas
-- Responsibility boundaries:
--   raw  = immutable source evidence and ingestion
--   core = normalized operational data
--   calc = calculations, reconciliation and approvals
--   api  = approved reporting outputs only

create schema if not exists raw authorization postgres;
create schema if not exists core authorization postgres;
create schema if not exists calc authorization postgres;
create schema if not exists api authorization postgres;

-- Keep all project schemas private by default.
-- Access will be granted deliberately in later migrations.

revoke all on schema raw from public;
revoke all on schema core from public;
revoke all on schema calc from public;
revoke all on schema api from public;

comment on schema raw is
'Immutable source files, source cells, import batches and ingestion evidence.';

comment on schema core is
'Normalized portfolio, contract, market and operational data.';

comment on schema calc is
'Calculated positions, ledger, reconciliation, metrics and approvals.';

comment on schema api is
'Approved reporting objects intentionally published to applications and dashboards.';