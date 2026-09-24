"use server";
import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { isSupabaseConfigured, siteOrigin } from "@/lib/supabase/config";
import { safeNext } from "@/lib/auth/navigation";
import { requireUser } from "@/lib/auth/user";

export type FormState = { error?: string; message?: string };
const unavailable = { error: "Sign-in is not configured yet. Please contact the app owner." };
function field(data: FormData, name: string) { const v = data.get(name); return typeof v === "string" ? v : ""; }
function validEmail(email: string) { return email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email); }
function validPassword(password: string) { return password.length >= 12 && password.length <= 128; }

export async function login(_: FormState, data: FormData): Promise<FormState> {
  if (!isSupabaseConfigured()) return unavailable;
  const email = field(data, "email").trim();
  const password = field(data, "password");
  if (!validEmail(email) || !password || password.length > 128) return { error: "Enter a valid email and password." };
  const client = await createClient();
  const { error } = await client.auth.signInWithPassword({ email, password });
  if (error) return { error: "Unable to sign in. Check your credentials and confirm your email, or try again later." };
  revalidatePath("/", "layout");
  redirect(safeNext(data.get("next")));
}
export async function signup(_: FormState, data: FormData): Promise<FormState> {
  if (!isSupabaseConfigured()) return unavailable;
  const email = field(data, "email").trim();
  const password = field(data, "password");
  if (!validEmail(email) || !validPassword(password)) return { error: "Enter a valid email and a password of 12–128 characters." };
  const client = await createClient();
  const { data: result, error } = await client.auth.signUp({ email, password, options: { emailRedirectTo: `${siteOrigin()}/auth/callback?next=/dashboard` } });
  if (error) return { error: "Unable to create your account. Please try again later." };
  if (result.session) { revalidatePath("/", "layout"); redirect("/dashboard"); }
  return { message: "Check your email for a confirmation link. Open it in this browser. If you already have an account, sign in instead." };
}
export async function forgotPassword(_: FormState, data: FormData): Promise<FormState> {
  if (!isSupabaseConfigured()) return unavailable;
  const email = field(data, "email").trim();
  if (!validEmail(email)) return { error: "Enter a valid email address." };
  const client = await createClient();
  // Deliberately do not reveal whether an account exists.
  await client.auth.resetPasswordForEmail(email, { redirectTo: `${siteOrigin()}/auth/callback?next=/update-password` });
  return { message: "If an account exists for this email, you will receive a reset link. Open it in this browser. If it does not arrive, try again later." };
}
export async function updatePassword(_: FormState, data: FormData): Promise<FormState> {
  await requireUser("/update-password");
  const password = field(data, "password");
  if (!validPassword(password)) return { error: "Use a password of 12–128 characters." };
  if (password !== field(data, "confirmPassword")) return { error: "The passwords do not match." };
  const client = await createClient();
  const { error } = await client.auth.updateUser({ password });
  if (error) return { error: "Unable to update your password. Request a new reset link and try again." };
  revalidatePath("/", "layout");
  redirect("/dashboard?password=updated");
}
export async function logout(): Promise<FormState> {
  const client = await createClient();
  const { error } = await client.auth.signOut({ scope: "local" });
  if (error) return { error: "Sign-out failed. Please try again." };
  revalidatePath("/", "layout");
  redirect("/login");
}
