drop policy if exists "workspace users can read published runs"
on api.published_run;

create policy "authenticated users can read published runs"
on api.published_run
for select
to authenticated
using (true);

drop policy if exists "workspace users can read published monthly metrics"
on api.published_monthly;

create policy "authenticated users can read published monthly metrics"
on api.published_monthly
for select
to authenticated
using (true);

drop policy if exists "workspace users can read published issue summaries"
on api.published_issue_summary;

create policy "authenticated users can read published issue summaries"
on api.published_issue_summary
for select
to authenticated
using (true);
