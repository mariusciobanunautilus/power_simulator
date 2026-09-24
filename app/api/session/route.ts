import { NextResponse } from "next/server";
import { getVerifiedUser } from "@/lib/auth/user";
export const dynamic = "force-dynamic";
export async function GET() {
  const user = await getVerifiedUser();
  return NextResponse.json(user ? { user: { id: user.id, email: user.email } } : { error: "Authentication required" }, { status: user ? 200 : 401, headers: { "Cache-Control": "private, no-store" } });
}
