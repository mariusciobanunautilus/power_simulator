import "server-only";

import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";

export type WorkspaceRole = "viewer" | "approver" | "admin";

export type PublishedRun = {
  run_id: number;
  model_year: number;
  scenario_code: string;
  as_of_utc: string;
  method_version: string;
  sourcing_total_eur: number | string;
  optimisation_margin_eur: number | string;
  origination_margin_eur: number | string;
  transaction_cost_ron: number | string;
  open_issue_count: number;
  high_or_critical_open_issue_count: number;
  published_at: string;
  published_by: string;
};

export type PublishedMetric = {
  run_id: number;
  month_start: string;
  period_end: string;
  book_code: string;
  book_name: string;
  metric_code: string;
  metric_label: string;
  grain: string;
  numeric_value: number | string;
  unit: string;
};

export type PublishedIssue = {
  run_id: number;
  issue_code: string;
  severity: string;
  disposition: string;
  issue_count: number;
};

export type ReviewRun = {
  run_id: number;
  model_year: number;
  scenario_code: string;
  as_of_utc: string;
  method_version: string;
  status: string;
  created_at: string;
  approved_by: string | null;
  approved_at: string | null;
  open_issue_count: number;
  blocking_issue_count: number;
  open_medium_issue_count: number;
  can_approve: boolean;
};

export type ReviewIssue = {
  issue_id: number;
  run_id: number;
  rule_code: string;
  severity: string;
  source_reference: string | null;
  observed_value: string | null;
  expected_value: string | null;
  disposition: string;
  owner_name: string | null;
  created_at: string;
  resolved_at: string | null;
};

export type DashboardData = {
  role: WorkspaceRole;
  publishedRun: PublishedRun | null;
  monthly: PublishedMetric[];
  publishedIssues: PublishedIssue[];
  reviewRun: ReviewRun | null;
  reviewIssues: ReviewIssue[];
  error: string | null;
};

function rows<T>(value: unknown): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

export function workspaceRole(user: User): WorkspaceRole {
  const value = user.app_metadata?.power_simulator_role;
  return value === "admin" || value === "approver" ? value : "viewer";
}

export async function loadDashboardData(user: User): Promise<DashboardData> {
  const role = workspaceRole(user);
  const canReview = role === "approver" || role === "admin";
  const supabase = await createClient();
  const api = supabase.schema("api");

  const publishedResult = await api
    .from("published_run")
    .select(
      "run_id,model_year,scenario_code,as_of_utc,method_version,sourcing_total_eur,optimisation_margin_eur,origination_margin_eur,transaction_cost_ron,open_issue_count,high_or_critical_open_issue_count,published_at,published_by",
    )
    .order("published_at", { ascending: false })
    .limit(1);

  const publishedRun = rows<PublishedRun>(publishedResult.data)[0] ?? null;
  let monthly: PublishedMetric[] = [];
  let publishedIssues: PublishedIssue[] = [];
  let reviewRun: ReviewRun | null = null;
  let reviewIssues: ReviewIssue[] = [];
  const errors: string[] = [];

  if (publishedResult.error) errors.push(publishedResult.error.message);

  if (publishedRun) {
    const [monthlyResult, issueResult] = await Promise.all([
      api
        .from("published_monthly")
        .select(
          "run_id,month_start,period_end,book_code,book_name,metric_code,metric_label,grain,numeric_value,unit",
        )
        .eq("run_id", publishedRun.run_id)
        .order("month_start", { ascending: true })
        .order("metric_code", { ascending: true }),
      api
        .from("published_issue_summary")
        .select("run_id,issue_code,severity,disposition,issue_count")
        .eq("run_id", publishedRun.run_id)
        .order("severity", { ascending: true })
        .order("issue_code", { ascending: true }),
    ]);

    monthly = rows<PublishedMetric>(monthlyResult.data);
    publishedIssues = rows<PublishedIssue>(issueResult.data);
    if (monthlyResult.error) errors.push(monthlyResult.error.message);
    if (issueResult.error) errors.push(issueResult.error.message);
  }

  if (canReview) {
    const reviewRunResult = await api
      .from("review_run")
      .select(
        "run_id,model_year,scenario_code,as_of_utc,method_version,status,created_at,approved_by,approved_at,open_issue_count,blocking_issue_count,open_medium_issue_count,can_approve",
      )
      .order("created_at", { ascending: false })
      .limit(1);

    reviewRun = rows<ReviewRun>(reviewRunResult.data)[0] ?? null;
    if (reviewRunResult.error) errors.push(reviewRunResult.error.message);

    if (reviewRun) {
      const reviewIssuesResult = await api
        .from("review_quality_issue")
        .select(
          "issue_id,run_id,rule_code,severity,source_reference,observed_value,expected_value,disposition,owner_name,created_at,resolved_at",
        )
        .eq("run_id", reviewRun.run_id)
        .order("severity", { ascending: true })
        .order("issue_id", { ascending: true });

      reviewIssues = rows<ReviewIssue>(reviewIssuesResult.data);
      if (reviewIssuesResult.error) errors.push(reviewIssuesResult.error.message);
    }
  }

  return {
    role,
    publishedRun,
    monthly,
    publishedIssues,
    reviewRun,
    reviewIssues,
    error: errors[0] ?? null,
  };
}
