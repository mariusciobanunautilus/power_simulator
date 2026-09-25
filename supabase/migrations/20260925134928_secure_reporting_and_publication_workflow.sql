-- Power Simulator reporting and publication governance.

create table calc.run_governance_event (
    event_id bigint generated always as identity primary key,
    run_id bigint not null references core.model_run(run_id),
    issue_id bigint references calc.quality_issue(issue_id),
    event_type text not null
        check (event_type in ('quality_review', 'approved', 'published')),
    actor_user_id uuid not null,
    actor_role text not null,
    note text,
    details jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create index ix_run_governance_event_run_created
    on calc.run_governance_event(run_id, created_at desc);

create index ix_run_governance_event_issue
    on calc.run_governance_event(issue_id)
    where issue_id is not null;

comment on table calc.run_governance_event is
'Immutable audit trail for model quality review, approval, and publication actions.';

create table api.published_run (
    publication_run_id bigint generated always as identity primary key,
    run_id bigint not null unique references core.model_run(run_id),
    model_year integer not null,
    scenario_code text not null,
    as_of_utc timestamptz not null,
    method_version text not null,
    sourcing_total_eur numeric(24,8) not null,
    optimisation_margin_eur numeric(24,8) not null,
    origination_margin_eur numeric(24,8) not null,
    transaction_cost_ron numeric(24,8) not null,
    open_issue_count integer not null check (open_issue_count >= 0),
    high_or_critical_open_issue_count integer not null
        check (high_or_critical_open_issue_count >= 0),
    published_at timestamptz not null default now(),
    published_by text not null
);

comment on table api.published_run is
'Immutable published run header and approved annual headline metrics for the dashboard.';

alter table api.published_run enable row level security;

alter table api.published_monthly
    add column period_end date,
    add column book_code text,
    add column book_name text,
    add column metric_label text,
    add column grain text;

update api.published_monthly pm
set
    period_end = pm.month_start,
    book_code = b.book_code,
    book_name = b.book_name,
    metric_label = md.label,
    grain = md.grain
from core.book b, calc.metric_definition md
where b.book_id = pm.book_id
  and md.metric_code = pm.metric_code;

alter table api.published_monthly
    alter column period_end set not null,
    alter column book_code set not null,
    alter column book_name set not null,
    alter column metric_label set not null,
    alter column grain set not null;

alter table api.published_issue_summary
    add column published_by text;

update api.published_issue_summary
set published_by = 'legacy'
where published_by is null;

alter table api.published_issue_summary
    alter column published_by set not null;

create index ix_published_monthly_book
    on api.published_monthly(book_id);

revoke all on schema api from anon;
grant usage on schema api to authenticated, service_role;

revoke all on api.published_run from anon, authenticated;
revoke all on api.published_monthly from anon, authenticated;
revoke all on api.published_issue_summary from anon, authenticated;

grant select on api.published_run to authenticated, service_role;
grant select on api.published_monthly to authenticated, service_role;
grant select on api.published_issue_summary to authenticated, service_role;

create policy "workspace users can read published runs"
on api.published_run
for select
to authenticated
using (
    coalesce(
        (select auth.jwt() -> 'app_metadata' ->> 'power_simulator_role'),
        ''
    ) in ('viewer', 'approver', 'admin')
);

create policy "workspace users can read published monthly metrics"
on api.published_monthly
for select
to authenticated
using (
    coalesce(
        (select auth.jwt() -> 'app_metadata' ->> 'power_simulator_role'),
        ''
    ) in ('viewer', 'approver', 'admin')
);

create policy "workspace users can read published issue summaries"
on api.published_issue_summary
for select
to authenticated
using (
    coalesce(
        (select auth.jwt() -> 'app_metadata' ->> 'power_simulator_role'),
        ''
    ) in ('viewer', 'approver', 'admin')
);

grant usage on schema core, calc to authenticated;
grant select on core.model_run to authenticated;
grant select on calc.quality_issue to authenticated;

create or replace view api.review_run
with (security_invoker = true)
as
select
    mr.run_id,
    mr.model_year,
    mr.scenario_code,
    mr.as_of_utc,
    mr.method_version,
    mr.status,
    mr.created_at,
    mr.approved_by,
    mr.approved_at,
    count(qi.issue_id) filter (where qi.disposition = 'open')::integer
        as open_issue_count,
    count(qi.issue_id) filter (
        where qi.disposition = 'open'
          and qi.severity in ('critical', 'high')
    )::integer as blocking_issue_count,
    count(qi.issue_id) filter (
        where qi.disposition = 'open'
          and qi.severity = 'medium'
    )::integer as open_medium_issue_count,
    (
        mr.status = 'validated'
        and count(qi.issue_id) filter (
            where qi.disposition = 'open'
              and qi.severity in ('critical', 'high')
        ) = 0
    ) as can_approve
from core.model_run mr
left join calc.quality_issue qi
  on qi.run_id = mr.run_id
where coalesce(
        auth.jwt() -> 'app_metadata' ->> 'power_simulator_role',
        ''
      ) in ('approver', 'admin')
group by
    mr.run_id,
    mr.model_year,
    mr.scenario_code,
    mr.as_of_utc,
    mr.method_version,
    mr.status,
    mr.created_at,
    mr.approved_by,
    mr.approved_at;

create or replace view api.review_quality_issue
with (security_invoker = true)
as
select
    qi.issue_id,
    qi.run_id,
    qi.rule_code,
    qi.severity,
    qi.source_reference,
    qi.observed_value,
    qi.expected_value,
    qi.disposition,
    qi.owner_name,
    qi.created_at,
    qi.resolved_at
from calc.quality_issue qi
where coalesce(
        auth.jwt() -> 'app_metadata' ->> 'power_simulator_role',
        ''
      ) in ('approver', 'admin');

grant select on api.review_run to authenticated;
grant select on api.review_quality_issue to authenticated;

create or replace function api.review_quality_issue(
    p_issue_id bigint,
    p_disposition text,
    p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
    v_role text := coalesce(
        auth.jwt() -> 'app_metadata' ->> 'power_simulator_role',
        ''
    );
    v_run_id bigint;
    v_old_disposition text;
begin
    if v_uid is null or v_role not in ('approver', 'admin') then
        raise exception 'Power Simulator approver role required'
            using errcode = '42501';
    end if;

    if p_disposition not in ('accepted', 'resolved', 'rejected') then
        raise exception 'Unsupported quality issue disposition: %', p_disposition
            using errcode = '22023';
    end if;

    select qi.run_id, qi.disposition
    into v_run_id, v_old_disposition
    from calc.quality_issue qi
    where qi.issue_id = p_issue_id
    for update;

    if v_run_id is null then
        raise exception 'Quality issue % does not exist', p_issue_id
            using errcode = 'P0002';
    end if;

    update calc.quality_issue
    set
        disposition = p_disposition,
        resolved_at = now()
    where issue_id = p_issue_id;

    insert into calc.run_governance_event (
        run_id,
        issue_id,
        event_type,
        actor_user_id,
        actor_role,
        note,
        details
    )
    values (
        v_run_id,
        p_issue_id,
        'quality_review',
        v_uid,
        v_role,
        p_note,
        jsonb_build_object(
            'previous_disposition', v_old_disposition,
            'new_disposition', p_disposition
        )
    );

    return jsonb_build_object(
        'issue_id', p_issue_id,
        'run_id', v_run_id,
        'disposition', p_disposition
    );
end;
$$;

create or replace function api.approve_run(
    p_run_id bigint,
    p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
    v_role text := coalesce(
        auth.jwt() -> 'app_metadata' ->> 'power_simulator_role',
        ''
    );
    v_status text;
    v_blocking integer;
begin
    if v_uid is null or v_role not in ('approver', 'admin') then
        raise exception 'Power Simulator approver role required'
            using errcode = '42501';
    end if;

    select mr.status
    into v_status
    from core.model_run mr
    where mr.run_id = p_run_id
    for update;

    if v_status is null then
        raise exception 'Model run % does not exist', p_run_id
            using errcode = 'P0002';
    end if;

    if v_status <> 'validated' then
        raise exception 'Model run % must be validated before approval; current status is %',
            p_run_id, v_status
            using errcode = '22023';
    end if;

    select count(*)::integer
    into v_blocking
    from calc.quality_issue qi
    where qi.run_id = p_run_id
      and qi.disposition = 'open'
      and qi.severity in ('critical', 'high');

    if v_blocking > 0 then
        raise exception 'Model run % has % open high/critical quality issue(s)',
            p_run_id, v_blocking
            using errcode = '22023';
    end if;

    update core.model_run
    set
        status = 'approved',
        approved_by = v_uid::text,
        approved_at = now()
    where run_id = p_run_id;

    insert into calc.run_governance_event (
        run_id,
        event_type,
        actor_user_id,
        actor_role,
        note,
        details
    )
    values (
        p_run_id,
        'approved',
        v_uid,
        v_role,
        p_note,
        jsonb_build_object('previous_status', v_status, 'new_status', 'approved')
    );

    return jsonb_build_object(
        'run_id', p_run_id,
        'status', 'approved'
    );
end;
$$;

create or replace function api.publish_run(
    p_run_id bigint,
    p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_uid uuid := auth.uid();
    v_role text := coalesce(
        auth.jwt() -> 'app_metadata' ->> 'power_simulator_role',
        ''
    );
    v_status text;
    v_blocking integer;
    v_monthly_rows integer;
    v_issue_rows integer;
begin
    if v_uid is null or v_role not in ('approver', 'admin') then
        raise exception 'Power Simulator approver role required'
            using errcode = '42501';
    end if;

    select mr.status
    into v_status
    from core.model_run mr
    where mr.run_id = p_run_id
    for update;

    if v_status is null then
        raise exception 'Model run % does not exist', p_run_id
            using errcode = 'P0002';
    end if;

    if v_status <> 'approved' then
        raise exception 'Model run % must be approved before publication; current status is %',
            p_run_id, v_status
            using errcode = '22023';
    end if;

    if exists (
        select 1
        from api.published_run pr
        where pr.run_id = p_run_id
    ) then
        raise exception 'Model run % has already been published', p_run_id
            using errcode = '23505';
    end if;

    select count(*)::integer
    into v_blocking
    from calc.quality_issue qi
    where qi.run_id = p_run_id
      and qi.disposition = 'open'
      and qi.severity in ('critical', 'high');

    if v_blocking > 0 then
        raise exception 'Model run % has % open high/critical quality issue(s)',
            p_run_id, v_blocking
            using errcode = '22023';
    end if;

    insert into api.published_run (
        run_id,
        model_year,
        scenario_code,
        as_of_utc,
        method_version,
        sourcing_total_eur,
        optimisation_margin_eur,
        origination_margin_eur,
        transaction_cost_ron,
        open_issue_count,
        high_or_critical_open_issue_count,
        published_by
    )
    select
        mr.run_id,
        mr.model_year,
        mr.scenario_code,
        mr.as_of_utc,
        mr.method_version,
        max(res.numeric_value) filter (
            where res.metric_code = 'sourcing_total_eur'
        ),
        max(res.numeric_value) filter (
            where res.metric_code = 'optimisation_margin_eur'
        ),
        max(res.numeric_value) filter (
            where res.metric_code = 'origination_margin_eur'
        ),
        max(res.numeric_value) filter (
            where res.metric_code = 'transaction_cost_ron'
        ),
        (
            select count(*)::integer
            from calc.quality_issue qi
            where qi.run_id = mr.run_id
              and qi.disposition = 'open'
        ),
        (
            select count(*)::integer
            from calc.quality_issue qi
            where qi.run_id = mr.run_id
              and qi.disposition = 'open'
              and qi.severity in ('critical', 'high')
        ),
        v_uid::text
    from core.model_run mr
    left join calc.metric_result res
      on res.run_id = mr.run_id
    where mr.run_id = p_run_id
    group by
        mr.run_id,
        mr.model_year,
        mr.scenario_code,
        mr.as_of_utc,
        mr.method_version;

    insert into api.published_monthly (
        run_id,
        month_start,
        period_end,
        book_id,
        book_code,
        book_name,
        metric_code,
        metric_label,
        grain,
        numeric_value,
        unit,
        published_by
    )
    select
        res.run_id,
        res.period_start,
        res.period_end,
        res.book_id,
        b.book_code,
        b.book_name,
        res.metric_code,
        md.label,
        md.grain,
        res.numeric_value,
        md.unit,
        v_uid::text
    from calc.metric_result res
    join calc.metric_definition md
      on md.metric_code = res.metric_code
    join core.book b
      on b.book_id = res.book_id
    where res.run_id = p_run_id
      and md.active
      and md.grain = 'month';

    get diagnostics v_monthly_rows = row_count;

    insert into api.published_issue_summary (
        run_id,
        issue_code,
        severity,
        disposition,
        issue_count,
        published_by
    )
    select
        qi.run_id,
        qi.rule_code,
        qi.severity,
        qi.disposition,
        count(*)::integer,
        v_uid::text
    from calc.quality_issue qi
    where qi.run_id = p_run_id
    group by
        qi.run_id,
        qi.rule_code,
        qi.severity,
        qi.disposition;

    get diagnostics v_issue_rows = row_count;

    update core.model_run
    set status = 'published'
    where run_id = p_run_id;

    insert into calc.run_governance_event (
        run_id,
        event_type,
        actor_user_id,
        actor_role,
        note,
        details
    )
    values (
        p_run_id,
        'published',
        v_uid,
        v_role,
        p_note,
        jsonb_build_object(
            'previous_status', v_status,
            'new_status', 'published',
            'published_monthly_rows', v_monthly_rows,
            'published_issue_summary_rows', v_issue_rows
        )
    );

    return jsonb_build_object(
        'run_id', p_run_id,
        'status', 'published',
        'published_monthly_rows', v_monthly_rows,
        'published_issue_summary_rows', v_issue_rows
    );
end;
$$;

revoke execute on function api.review_quality_issue(bigint, text, text)
    from public, anon;
revoke execute on function api.approve_run(bigint, text)
    from public, anon;
revoke execute on function api.publish_run(bigint, text)
    from public, anon;

grant execute on function api.review_quality_issue(bigint, text, text)
    to authenticated;
grant execute on function api.approve_run(bigint, text)
    to authenticated;
grant execute on function api.publish_run(bigint, text)
    to authenticated;

comment on function api.review_quality_issue(bigint, text, text) is
'Approver/admin RPC for dispositioning a quality issue. Uses JWT app_metadata.power_simulator_role and writes an audit event.';

comment on function api.approve_run(bigint, text) is
'Approver/admin RPC that moves a validated run to approved only when no open high/critical issues remain.';

comment on function api.publish_run(bigint, text) is
'Approver/admin RPC that creates immutable published snapshots from an approved run and then marks the run published.';
