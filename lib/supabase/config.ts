export function isSupabaseConfigured() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  return Boolean(url && key && !url.includes("YOUR_PROJECT") && !key.includes("REPLACE_ME"));
}
export function supabaseConfig() {
  if (!isSupabaseConfigured()) throw new Error("Supabase connection is not configured.");
  return { url: process.env.NEXT_PUBLIC_SUPABASE_URL!, key: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY! };
}
export function siteOrigin() {
  const value = process.env.NEXT_PUBLIC_SITE_URL;
  if (!value) throw new Error("NEXT_PUBLIC_SITE_URL is required for email redirects.");
  const url = new URL(value);
  if (url.protocol !== "https:" && !(url.protocol === "http:" && ["localhost", "127.0.0.1"].includes(url.hostname))) {
    throw new Error("The site URL must use HTTPS outside localhost.");
  }
  return url.origin;
}
