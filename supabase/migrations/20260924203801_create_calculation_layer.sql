-- Power Simulator
-- Calculation, reconciliation and control layer


-- ============================================================
-- CALC: LEDGER LINE
-- ============================================================

create table calc.ledger_line (
    ledger_line_id bigint generated always as identity primary key,

    run_id bigint not null
        references core.model_run(run_id),

    month_start date not null,

    book_id bigint not null
        references core.book(book_id),

    component_code text not null,

    entry_side text not null
        check (entry_side in ('debit', 'credit')),

    amount_ron numeric(20,4) not null
        check (amount_ron >= 0),

    quantity_mwh numeric(20,8),

    source_cell_id bigint
        references raw.source_cell(source_cell_id),

    calculation_rule text not null,

    calculated_at timestamptz not null default now(),

    unique (
        run_id,
        month_start,
        book_id,
        component_code,
        entry_side,
        calculation_rule
    )
);

comment on table calc.ledger_line is
'Financial calculation ledger. Costs are debits and revenues are credits; physical direction is not inferred from monetary sign.';


-- ============================================================
-- CALC: METRIC DEFINITION
-- ============================================================

create table calc.metric_definition (
    metric_code text primary key,

    label text not null,

    unit text not null,

    grain text not null,

    signed_convention text not null,

    rule_version text not null,

    description text not null,

    active boolean not null default true
);

comment on table calc.metric_definition is
'Controlled KPI catalogue defining meaning, units, grain and calculation-version semantics.';


-- ============================================================
-- CALC: METRIC RESULT
-- ============================================================

create table calc.metric_result (
    run_id bigint not null
        references core.model_run(run_id),

    metric_code text not null
        references calc.metric_definition(metric_code),

    period_start date not null,

    period_end date not null,

    book_id bigint not null
        references core.book(book_id),

    numeric_value numeric(24,8) not null,

    calculated_at timestamptz not null default now(),

    check (period_end >= period_start),

    primary key (
        run_id,
        metric_code,
        period_start,
        book_id
    )
);

comment on table calc.metric_result is
'Reconciled KPI result by model run, reporting period and book.';


-- ============================================================
-- CALC: RECONCILIATION RESULT
-- ============================================================

create table calc.reconciliation_result (
    reconciliation_id bigint generated always as identity primary key,

    run_id bigint not null
        references core.model_run(run_id),

    reconciliation_code text not null,

    period_start date,
    period_end date,

    source_value numeric(24,8),

    recalculated_value numeric(24,8),

    difference_value numeric(24,8),

    tolerance numeric(24,8),

    status text not null
        check (
            status in (
                'matched',
                'within_tolerance',
                'mismatch',
                'not_comparable'
            )
        ),

    reason text,

    owner_name text,

    created_at timestamptz not null default now(),

    check (
        period_end is null
        or period_start is null
        or period_end >= period_start
    )
);

comment on table calc.reconciliation_result is
'Comparison between workbook/source results and recalculated model values. Differences are recorded rather than silently replaced.';


-- ============================================================
-- CALC: OVERRIDE DECISION
-- ============================================================

create table calc.override_decision (
    override_id bigint generated always as identity primary key,

    run_id bigint not null
        references core.model_run(run_id),

    target_name text not null,

    prior_value text,

    replacement_value text not null,

    reason text not null,

    owner_name text not null,

    created_at timestamptz not null default now(),

    approved_by text,

    approved_at timestamptz,

    source_cell_id bigint
        references raw.source_cell(source_cell_id)
);

comment on table calc.override_decision is
'Governed manual overrides with prior value, replacement, justification and approval evidence.';


-- ============================================================
-- CALC: QUALITY ISSUE
-- ============================================================

create table calc.quality_issue (
    issue_id bigint generated always as identity primary key,

    run_id bigint not null
        references core.model_run(run_id),

    rule_code text not null,

    severity text not null
        check (
            severity in (
                'critical',
                'high',
                'medium',
                'low'
            )
        ),

    source_reference text,

    observed_value text,

    expected_value text,

    disposition text not null default 'open'
        check (
            disposition in (
                'open',
                'accepted',
                'resolved',
                'rejected'
            )
        ),

    owner_name text,

    created_at timestamptz not null default now(),

    resolved_at timestamptz
);

comment on table calc.quality_issue is
'Data-quality, reconciliation and model-control exceptions requiring explicit disposition.';


-- ============================================================
-- CALC VIEW: HOURLY POSITION
-- ============================================================

create view calc.hourly_position
with (security_invoker = true)
as
with volume as (
    select
        hv.run_id,
        hv.interval_id,

        coalesce(
            sum(hv.quantity_mwh)
            filter (where hv.measure_code = 'total_load'),
            0
        ) as total_load_mwh,

        coalesce(
            sum(hv.quantity_mwh)
            filter (where hv.measure_code = 'indexed_load'),
            0
        ) as indexed_load_mwh,

        sum(hv.quantity_mwh)
            filter (where hv.measure_code = 'fixed_load')
            as sourced_fixed_load_mwh,

        coalesce(
            sum(hv.quantity_mwh)
            filter (where hv.measure_code = 'renewable_output'),
            0
        ) as renewable_mwh,

        coalesce(
            sum(hv.quantity_mwh)
            filter (where hv.measure_code = 'other_supply'),
            0
        ) as other_supply_mwh

    from core.hourly_volume hv

    group by
        hv.run_id,
        hv.interval_id
),

procurement as (
    select
        ps.run_id,
        ps.interval_id,
        sum(ps.quantity_mwh) as contracted_mwh

    from core.procurement_schedule ps

    group by
        ps.run_id,
        ps.interval_id
),

combined as (
    select
        v.run_id,
        v.interval_id,

        v.total_load_mwh,
        v.indexed_load_mwh,

        coalesce(
            v.sourced_fixed_load_mwh,
            v.total_load_mwh - v.indexed_load_mwh
        ) as fixed_load_mwh,

        coalesce(p.contracted_mwh, 0) as contracted_mwh,

        v.renewable_mwh,
        v.other_supply_mwh

    from volume v

    left join procurement p
        on p.run_id = v.run_id
       and p.interval_id = v.interval_id
)

select
    c.*,

    c.contracted_mwh
        + c.renewable_mwh
        + c.other_supply_mwh
        - c.fixed_load_mwh
        as fixed_net_mwh,

    c.contracted_mwh
        + c.renewable_mwh
        + c.other_supply_mwh
        - c.total_load_mwh
        as market_net_mwh

from combined c;

comment on view calc.hourly_position is
'Hourly physical position. Positive net position means long/sell; negative means short/buy.';


-- ============================================================
-- CALC VIEW: HOURLY MARKET VALUE
-- ============================================================

create view calc.hourly_market_value
with (security_invoker = true)
as
select
    hp.run_id,
    hp.interval_id,

    hp.market_net_mwh,

    mp.price_per_mwh as pzu_ron_per_mwh,

    greatest(
        hp.market_net_mwh,
        0
    ) as sold_mwh,

    greatest(
        -hp.market_net_mwh,
        0
    ) as bought_mwh,

    greatest(
        hp.market_net_mwh,
        0
    ) * mp.price_per_mwh
        as sale_cashflow_ron,

    greatest(
        -hp.market_net_mwh,
        0
    ) * mp.price_per_mwh
        as purchase_cashflow_ron

from calc.hourly_position hp

join core.market_price mp
    on mp.run_id = hp.run_id
   and mp.interval_id = hp.interval_id
   and mp.market_code = 'PZU'
   and mp.currency_code = 'RON';

comment on view calc.hourly_market_value is
'Hourly PZU physical buy/sell volumes and valuation. Physical direction remains volume-driven even when market prices are negative.';


-- ============================================================
-- CALC VIEW: MONTHLY BOOK LEDGER
-- ============================================================

create view calc.monthly_book_ledger
with (security_invoker = true)
as
select
    l.run_id,
    l.month_start,
    l.book_id,

    sum(
        case
            when l.entry_side = 'credit'
            then l.amount_ron
            else 0
        end
    ) as revenue_ron,

    sum(
        case
            when l.entry_side = 'debit'
            then l.amount_ron
            else 0
        end
    ) as cost_ron,

    sum(
        case
            when l.entry_side = 'credit'
            then l.amount_ron
            else -l.amount_ron
        end
    ) as result_ron

from calc.ledger_line l

group by
    l.run_id,
    l.month_start,
    l.book_id;

comment on view calc.monthly_book_ledger is
'Monthly revenue, cost and net result by model run and commercial book.';


-- ============================================================
-- INDEXES
-- ============================================================

create index ix_ledger_run_month_book
    on calc.ledger_line(
        run_id,
        month_start,
        book_id
    );

create index ix_metric_result_run
    on calc.metric_result(
        run_id,
        metric_code
    );

create index ix_reconciliation_run
    on calc.reconciliation_result(
        run_id,
        reconciliation_code
    );

create index ix_override_run
    on calc.override_decision(run_id);

create index ix_quality_issue_run
    on calc.quality_issue(
        run_id,
        severity,
        disposition
    );