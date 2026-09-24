import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { isPublicPath } from "@/lib/auth/navigation";
import { isSupabaseConfigured, supabaseConfig } from "./config";

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });
  let authenticated = false;
  if (isSupabaseConfigured()) {
    const { url, key } = supabaseConfig();
    const client = createServerClient(url, key, {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll(values, headers) {
          values.forEach(({ name, value }) => request.cookies.set(name, value));
          response = NextResponse.next({ request });
          values.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
          Object.entries(headers ?? {}).forEach(([name, value]) => response.headers.set(name, value));
        },
      },
    });
    // Auth server validation also rejects revoked/invalid sessions.
    const { data, error } = await client.auth.getUser();
    authenticated = !error && Boolean(data.user && !data.user.is_anonymous);
  }
  if (!authenticated && !isPublicPath(request.nextUrl.pathname)) {
    let denied: NextResponse;
    if (request.nextUrl.pathname.startsWith("/api/")) {
      denied = NextResponse.json({ error: "Authentication required" }, { status: 401 });
    } else {
      const url = request.nextUrl.clone();
      url.pathname = "/login";
      url.search = "";
      url.searchParams.set("next", request.nextUrl.pathname + request.nextUrl.search);
      denied = NextResponse.redirect(url);
    }
    response.cookies.getAll().forEach(cookie => denied.cookies.set(cookie));
    response = denied;
  }
  response.headers.set("Cache-Control", "private, no-store, max-age=0");
  response.headers.set("Pragma", "no-cache");
  response.headers.set("Expires", "0");
  return response;
}
