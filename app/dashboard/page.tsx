import { requireUser } from "@/lib/auth/user";
import {
  loadDashboardData,
  type PublishedMetric,
  type ReviewIssue,
} from "@/lib/reporting/dashboard";
import { approveRun, publishRun, reviewQualityIssue } from "./actions";

type SearchParams = Promise<{
  password?: string;
  governance?: string;
  governanceError?: string;
}>;

const monthFormatter = new Intl.DateTimeFormat("en", { month: "short" });

function number(value: number | string | null | undefined) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function format(value: number | string, maximumFractionDigits = 1) {
  return number(value).toLocaleString("en-US", { maximumFractionDigits });
}

function metricMap(rows: PublishedMetric[]) {
  const byMonth = new Map<string, Map<string, PublishedMetric>>();
  for (const row of rows) {
    const month = byMonth.get(row.month_start) ?? new Map<string, PublishedMetric>();
    month.set(row.metric_code, row);
    byMonth.set(row.month_start, month);
  }
  return byMonth;
}

function metricValue(month: Map<string, PublishedMetric>, code: string) {
  return month.get(code)?.numeric_value ?? 0;
}

function issueClass(issue: ReviewIssue) {
  return issue.severity === "high" || issue.severity === "critical"
    ? "issue-card issue-blocking"
    : "issue-card";
}

export default async function Dashboard({ searchParams }: { searchParams: SearchParams }) {
  const user = await requireUser();
  const params = await searchParams;
  const data = await loadDashboardData(user);
  const months = metricMap(data.monthly);
  const isApprover = data.role === "approver" || data.role === "admin";

  return (
    <section className="dashboard">
      <div className="dashboard-heading">
        <div>
          <p className="eyebrow">POWER PORTFOLIO</p>
          <h1>Power portfolio</h1>
          <p className="lead dashboard-lead">
            Approved portfolio results, physical exposure and governance status.
          </p>
        </div>
        <div className="role-badge">{data.role}</div>
      </div>

      {params.password === "updated" && (
        <p role="status" className="notice">Your password has been updated.</p>
      )}
      {params.governance && <p role="status" className="notice">{params.governance}</p>}
      {params.governanceError && <p role="alert" className="error-panel">{params.governanceError}</p>}
      {data.error && (
        <p role="alert" className="error-panel">
          Reporting data could not be loaded. The authenticated workspace remains available.
        </p>
      )}

      {data.publishedRun ? (
        <>
          <div className="run-strip">
            <div>
              <span className="label">Published run</span>
              <strong>#{data.publishedRun.run_id} · {data.publishedRun.model_year}</strong>
            </div>
            <div>
              <span className="label">Scenario</span>
              <strong>{data.publishedRun.scenario_code}</strong>
            </div>
            <div>
              <span className="label">Method</span>
              <strong>{data.publishedRun.method_version}</strong>
            </div>
            <div>
              <span className="label">Published</span>
              <strong>{new Date(data.publishedRun.published_at).toLocaleString("en-GB")}</strong>
            </div>
          </div>

          <div className="kpi-grid">
            <article className="kpi-card">
              <span>Sourcing total</span>
              <strong>€{format(data.publishedRun.sourcing_total_eur, 0)}</strong>
              <small>Approved annual result</small>
            </article>
            <article className="kpi-card">
              <span>Optimisation margin</span>
              <strong>€{format(data.publishedRun.optimisation_margin_eur, 0)}</strong>
              <small>Annual workbook-equivalent margin</small>
            </article>
            <article className="kpi-card">
              <span>Origination margin</span>
              <strong>€{format(data.publishedRun.origination_margin_eur, 0)}</strong>
              <small>Annual aggregate margin</small>
            </article>
            <article className="kpi-card">
              <span>Transaction cost</span>
              <strong>{format(data.publishedRun.transaction_cost_ron, 0)} RON</strong>
              <small>Transaction and guarantee cost</small>
            </article>
          </div>

          <section className="panel">
            <div className="panel-heading">
              <div>
                <p className="eyebrow">MONTHLY EXPOSURE</p>
                <h2>Physical and sourcing view</h2>
              </div>
              <span className="muted">Workbook-equivalent publication</span>
            </div>
            <div className="table-wrap">
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Month</th>
                    <th>Base result (RON)</th>
                    <th>Retail load (MWh)</th>
                    <th>PZU buy (MWh)</th>
                    <th>PZU sell (MWh)</th>
                    <th>PZU buy price</th>
                    <th>Fixed long</th>
                    <th>Fixed short</th>
                  </tr>
                </thead>
                <tbody>
                  {[...months.entries()].map(([monthStart, month]) => (
                    <tr key={monthStart}>
                      <td>{monthFormatter.format(new Date(`${monthStart}T12:00:00Z`))}</td>
                      <td>{format(metricValue(month, "monthly_base_sourcing_ron"), 0)}</td>
                      <td>{format(metricValue(month, "retail_total_mwh"), 0)}</td>
                      <td>{format(metricValue(month, "pzu_buy_mwh"), 1)}</td>
                      <td>{format(metricValue(month, "pzu_sell_mwh"), 1)}</td>
                      <td>{format(metricValue(month, "pzu_weighted_buy_price"), 2)}</td>
                      <td>{format(metricValue(month, "fixed_long_mwh"), 1)}</td>
                      <td>{format(metricValue(month, "fixed_short_mwh"), 1)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <section className="panel">
            <div className="panel-heading">
              <div>
                <p className="eyebrow">PUBLISHED QUALITY</p>
                <h2>Known exceptions</h2>
              </div>
              <strong>{data.publishedRun.open_issue_count} open</strong>
            </div>
            {data.publishedIssues.length ? (
              <div className="issue-summary-grid">
                {data.publishedIssues.map((issue) => (
                  <article className="summary-card" key={`${issue.issue_code}-${issue.disposition}`}>
                    <span className={`severity severity-${issue.severity}`}>{issue.severity}</span>
                    <strong>{issue.issue_code}</strong>
                    <small>{issue.issue_count} · {issue.disposition}</small>
                  </article>
                ))}
              </div>
            ) : (
              <p className="muted">No published quality exceptions.</p>
            )}
          </section>
        </>
      ) : (
        <div className="empty-state publication-empty">
          <span className="status-dot" />
          <h2>No approved run has been published</h2>
          <p>
            Validated calculations stay private until the governance workflow approves and publishes a reporting snapshot.
          </p>
        </div>
      )}

      {isApprover && data.reviewRun && (
        <section className="panel governance-panel">
          <div className="panel-heading">
            <div>
              <p className="eyebrow">GOVERNANCE</p>
              <h2>Run #{data.reviewRun.run_id} review</h2>
            </div>
            <span className={`run-status run-status-${data.reviewRun.status}`}>
              {data.reviewRun.status}
            </span>
          </div>

          <div className="governance-stats">
            <div><span>Open issues</span><strong>{data.reviewRun.open_issue_count}</strong></div>
            <div><span>Blocking high/critical</span><strong>{data.reviewRun.blocking_issue_count}</strong></div>
            <div><span>Open medium</span><strong>{data.reviewRun.open_medium_issue_count}</strong></div>
          </div>

          <div className="governance-actions">
            <form action={approveRun}>
              <input type="hidden" name="runId" value={data.reviewRun.run_id} />
              <button disabled={!data.reviewRun.can_approve}>Approve run</button>
            </form>
            <form action={publishRun}>
              <input type="hidden" name="runId" value={data.reviewRun.run_id} />
              <button className="secondary" disabled={data.reviewRun.status !== "approved"}>Publish snapshot</button>
            </form>
          </div>

          <div className="issue-list">
            {data.reviewIssues.map((issue) => (
              <article className={issueClass(issue)} key={issue.issue_id}>
                <div className="issue-topline">
                  <div>
                    <span className={`severity severity-${issue.severity}`}>{issue.severity}</span>
                    <strong>{issue.rule_code}</strong>
                  </div>
                  <span className="disposition">{issue.disposition}</span>
                </div>
                <p>{issue.observed_value}</p>
                {issue.expected_value && <p className="muted">Expected: {issue.expected_value}</p>}
                <div className="issue-meta">
                  <span>{issue.source_reference ?? "No source reference"}</span>
                  <span>{issue.owner_name ?? "Unassigned"}</span>
                </div>
                {issue.disposition === "open" && (
                  <div className="issue-actions">
                    {(["accepted", "resolved", "rejected"] as const).map((disposition) => (
                      <form action={reviewQualityIssue} key={disposition}>
                        <input type="hidden" name="issueId" value={issue.issue_id} />
                        <input type="hidden" name="disposition" value={disposition} />
                        <button className="secondary" type="submit">{disposition}</button>
                      </form>
                    ))}
                  </div>
                )}
              </article>
            ))}
          </div>
        </section>
      )}
    </section>
  );
}
