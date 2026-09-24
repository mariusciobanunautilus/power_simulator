import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { safeNext } from "@/lib/auth/navigation";
import { isSupabaseConfigured } from "@/lib/supabase/config";

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  if (code && isSupabaseConfigured()) {
    const client = await createClient();
    const { error } = await client.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(new URL(safeNext(request.nextUrl.searchParams.get("next")), request.url), { headers: { "Cache-Control": "private, no-store" } });
  }
  return NextResponse.redirect(new URL("/auth/error", request.url), { headers: { "Cache-Control": "private, no-store" } });
}
