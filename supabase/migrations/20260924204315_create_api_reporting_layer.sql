-- Power Simulator
-- Published reporting layer
-- Contains only intentionally released reporting snapshots.
-- No raw trading data is exposed from this schema.


-- ============================================================
-- API: PUBLISHED MONTHLY METRICS
-- ============================================================

create table api.published_monthly (
    publication_id bigint generated always as identity primary key,

    run_id bigint not null
        references core.model_run(run_id),

    month_start date not null,

    book_id bigint not null
        references core.book(book_id),

    metric_code text not null
        references calc.metric_definition(metric_code),

    numeric_value numeric(24,8) not null,

    unit text not null,

    published_at timestamptz not null default now(),

    published_by text,

    unique (
        run_id,
        month_start,
        book_id,
        metric_code
    )
);

comment on table api.published_monthly is
'Read-oriented snapshot of approved monthly KPI values intended for dashboards and applications.';


-- ============================================================
-- API: PUBLISHED ISSUE SUMMARY
-- ============================================================

create table api.published_issue_summary (
    publication_issue_id bigint generated always as identity primary key,

    run_id bigint not null
        references core.model_run(run_id),

    issue_code text not null,

    severity text not null
        check (
            severity in (
                'critical',
                'high',
                'medium',
                'low'
            )
        ),

    disposition text not null
        check (
            disposition in (
                'open',
                'accepted',
                'resolved',
                'rejected'
            )
        ),

    issue_count integer not null
        check (issue_count >= 0),

    published_at timestamptz not null default now(),

    unique (
        run_id,
        issue_code,
        severity,
        disposition
    )
);

comment on table api.published_issue_summary is
'Non-sensitive summary of published model and data-quality exceptions.';


-- ============================================================
-- SECURITY
-- ============================================================

alter table api.published_monthly
    enable row level security;

alter table api.published_issue_summary
    enable row level security;

-- Deliberately create no anon/authenticated policies yet.
-- Application access will be introduced later together with the
-- agreed authentication and authorization model.


-- ============================================================
-- INDEXES
-- ============================================================

create index ix_published_monthly_run_month
    on api.published_monthly(
        run_id,
        month_start
    );

create index ix_published_monthly_metric
    on api.published_monthly(
        metric_code,
        month_start
    );

create index ix_published_issue_run
    on api.published_issue_summary(
        run_id,
        severity,
        disposition
    );