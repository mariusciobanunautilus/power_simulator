
drop policy if exists "workspace users can read published runs"
on api.published_run;

create policy "workspace users can read published runs"
on api.published_run
for select
to authenticated
using (
    coalesce(
        ((select auth.jwt()) -> 'app_metadata' ->> 'power_simulator_role'),
        ''
    ) in ('viewer', 'approver', 'admin')
);

drop policy if exists "workspace users can read published monthly metrics"
on api.published_monthly;

create policy "workspace users can read published monthly metrics"
on api.published_monthly
for select
to authenticated
using (
    coalesce(
        ((select auth.jwt()) -> 'app_metadata' ->> 'power_simulator_role'),
        ''
    ) in ('viewer', 'approver', 'admin')
);

drop policy if exists "workspace users can read published issue summaries"
on api.published_issue_summary;

create policy "workspace users can read published issue summaries"
on api.published_issue_summary
for select
to authenticated
using (
    coalesce(
        ((select auth.jwt()) -> 'app_metadata' ->> 'power_simulator_role'),
        ''
    ) in ('viewer', 'approver', 'admin')
);
