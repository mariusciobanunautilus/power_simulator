# Power Simulator

Power Simulator is a deterministic power-portfolio model built on Next.js, Supabase/Postgres, and an immutable workbook-evidence layer.

The current implementation covers the workbook-to-database flow through validated calculations, reconciliation, KPI generation, and a governed reporting/publication layer. The dashboard reads only intentionally published snapshots; it is not the calculation engine.

## Current implementation

The hosted Supabase project contains:

- immutable workbook evidence in `raw`;
- canonical books, products, settlement intervals, balancing, services, fees, guarantees, FX, market prices, hourly volumes, and procurement in `core`;
- normalized and workbook-equivalent position/valuation logic, ledger, metrics, reconciliations, quality issues, and governance audit events in `calc`;
- approved reporting snapshots and reviewer RPCs in the exposed `api` schema.

Run `1` is currently technically **validated**, not approved or published. The dashboard therefore shows no portfolio publication to ordinary viewers until an approver completes the governance workflow.

The database deliberately does **not** fabricate unsupported detail. Deal-level `core.trade`, authoritative hourly ID prices, and fully specified acquisition counterparties/pricing remain open source-data gaps.

## Application architecture

The application is Next.js App Router + TypeScript with Supabase Auth and server-protected routes.

The browser/server Supabase client uses the project publishable key. Never expose a service-role or secret key in frontend environment variables.

The reporting boundary is:

```text
raw evidence
    ↓
core operational facts
    ↓
calc deterministic calculations / reconciliation
    ↓
validated run
    ↓
human quality review
    ↓
approved run
    ↓
immutable api publication snapshot
    ↓
authenticated dashboard
```

The dashboard never reads `raw`, `core`, or `calc` as its ordinary reporting source.

## Roles

All non-anonymous authenticated users may read published reporting snapshots.

Approval/review actions require trusted JWT `app_metadata.power_simulator_role` with one of:

- `approver`
- `admin`

Users without one of those trusted app-metadata roles behave as `viewer`.

Do not use user-editable `user_metadata` for authorization.

Approver/admin actions available through the reporting schema:

- review a quality issue as `accepted`, `resolved`, or `rejected`;
- approve a validated run once no open high/critical issues remain;
- publish an approved run into immutable reporting snapshots.

Every quality review, approval, and publication action is recorded in `calc.run_governance_event`.

## Run locally

Use Node.js 22 or later.

```sh
npm ci
cp .env.example .env.local
# Fill in all three variables in .env.local.
npm run dev
```

| Variable | Value |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Hosted Power Simulator Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Publishable key (`sb_publishable_…`) |
| `NEXT_PUBLIC_SITE_URL` | Canonical app origin, e.g. `http://localhost:3000` |

`.env.local` is ignored by Git.

## Supabase Auth configuration

In Supabase:

1. Enable Email authentication.
2. Enable email confirmation if self-registration is allowed.
3. Set the minimum password length to at least 12.
4. Set the Site URL to the canonical application origin.
5. Add callback URLs for `/auth/callback?next=/dashboard` and `/auth/callback?next=/update-password`.
6. Configure SMTP before relying on production email delivery.
7. Assign approver/admin roles only through trusted app-metadata administration.

The security advisor currently also recommends enabling leaked-password protection in Supabase Auth.

## Reporting and publication security

The `api` schema is the only portfolio reporting schema exposed through PostgREST.

Published tables have RLS enabled and grant authenticated users read-only access:

- `api.published_run`
- `api.published_monthly`
- `api.published_issue_summary`

Reviewer-only views are filtered by trusted app metadata:

- `api.review_run`
- `api.review_quality_issue`

Mutating governance RPCs are restricted internally to approver/admin roles:

- `api.review_quality_issue(...)`
- `api.approve_run(...)`
- `api.publish_run(...)`

The publication RPC copies only approved metric snapshots and issue summaries into `api`; it does not expose raw workbook cells or operational trading facts.

## Routes

| Route | Access | Purpose |
| --- | --- | --- |
| `/` | Public | Landing page |
| `/login` | Public | Email/password login |
| `/signup` | Public | Registration and confirmation |
| `/forgot-password` | Public | Password recovery |
| `/auth/callback` | Public | PKCE code exchange |
| `/auth/error` | Public | Recoverable auth error |
| `/dashboard` | Authenticated | Published reporting; reviewer controls for approver/admin |
| `/update-password` | Authenticated | Password update |
| `/api/session` | Authenticated | Current session summary |

## Database workflow

The canonical project procedure is `Power_Simulator_Working_Procedure.md`.

Schema changes are versioned under:

```text
supabase/migrations/
```

Workbook transformations and deterministic validation scripts are under:

```text
scripts/
```

Important current scripts include:

- `transform-market-price-pzu-*.sql`
- `transform-hourly-volume-2026.sql`
- `transform-procurement-2026.sql`
- `transform-workbook-ledger-2026.sql`
- `validate-market-price-pzu-2026.sql`
- `seed-metrics-quality-2026.sql`
- `reconcile-workbook-normalized-2026.sql`

## Verification

Before merging or deploying application changes:

```sh
npm run lint
npm run typecheck
npm test
npm run build
```

The Playwright auth tests use a local HTTP test double, not the hosted Supabase project:

```sh
npx playwright install chromium
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54329 \
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=test-publishable-key \
NEXT_PUBLIC_SITE_URL=http://localhost:3100 npm run build
npm run test:e2e
```

A local test pass does not replace hosted-project checks for email delivery, RLS, app metadata, approval, and publication.

## Governance principle

Validation is technical. Approval is human. Publication is explicit.

A validated run must not become visible as the official dashboard result until material quality issues have been reviewed and an authorized approver publishes the snapshot.
