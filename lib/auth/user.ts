import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured } from "@/lib/supabase/config";
import { safeNext } from "./navigation";

export const getVerifiedUser = cache(async () => {
  if (!isSupabaseConfigured()) return null;
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getUser();
  return error || !data.user || data.user.is_anonymous ? null : data.user;
});
export async function requireUser(next = "/dashboard") {
  const user = await getVerifiedUser();
  if (!user) redirect(`/login?next=${encodeURIComponent(safeNext(next))}`);
  return user;
}
