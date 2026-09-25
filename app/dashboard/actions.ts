"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireUser } from "@/lib/auth/user";
import { createClient } from "@/lib/supabase/server";
import { workspaceRole } from "@/lib/reporting/dashboard";

function toPositiveInteger(value: FormDataEntryValue | null, label: string) {
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number <= 0) {
    throw new Error(`${label} must be a positive integer.`);
  }
  return number;
}

function governanceError(message: string) {
  if (message.includes("approver role")) return "Approver role required.";
  if (message.includes("open high/critical")) return "Resolve or accept blocking issues before approval.";
  if (message.includes("must be validated")) return "Only validated runs can be approved.";
  if (message.includes("must be approved")) return "Approve the run before publication.";
  if (message.includes("already been published")) return "This run has already been published.";
  return "The governance action could not be completed.";
}

async function assertApprover() {
  const user = await requireUser();
  const role = workspaceRole(user);
  if (role !== "approver" && role !== "admin") {
    redirect("/dashboard?governanceError=Approver%20role%20required.");
  }
}

function finish(message: string) {
  revalidatePath("/dashboard");
  redirect(`/dashboard?governance=${encodeURIComponent(message)}`);
}

function fail(message: string) {
  redirect(`/dashboard?governanceError=${encodeURIComponent(governanceError(message))}`);
}

export async function reviewQualityIssue(formData: FormData) {
  await assertApprover();
  const issueId = toPositiveInteger(formData.get("issueId"), "Issue ID");
  const disposition = String(formData.get("disposition") ?? "");
  if (!new Set(["accepted", "resolved", "rejected"]).has(disposition)) {
    fail("Unsupported quality issue disposition.");
  }

  const supabase = await createClient();
  const { error } = await supabase.schema("api").rpc("review_quality_issue", {
    p_issue_id: issueId,
    p_disposition: disposition,
    p_note: "Reviewed from Power Simulator dashboard",
  });

  if (error) fail(error.message);
  finish(`Issue ${issueId} marked ${disposition}.`);
}

export async function approveRun(formData: FormData) {
  await assertApprover();
  const runId = toPositiveInteger(formData.get("runId"), "Run ID");
  const supabase = await createClient();
  const { error } = await supabase.schema("api").rpc("approve_run", {
    p_run_id: runId,
    p_note: "Approved from Power Simulator dashboard",
  });

  if (error) fail(error.message);
  finish(`Run ${runId} approved.`);
}

export async function publishRun(formData: FormData) {
  await assertApprover();
  const runId = toPositiveInteger(formData.get("runId"), "Run ID");
  const supabase = await createClient();
  const { error } = await supabase.schema("api").rpc("publish_run", {
    p_run_id: runId,
    p_note: "Published from Power Simulator dashboard",
  });

  if (error) fail(error.message);
  finish(`Run ${runId} published.`);
}
