import { beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";
const mock = vi.hoisted(() => ({ getUser: vi.fn(), create: vi.fn() }));
vi.mock("@supabase/ssr", () => ({ createServerClient: mock.create }));
import { updateSession } from "@/lib/supabase/proxy";
beforeEach(() => {
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://test.supabase.co");
  vi.stubEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", "sb_publishable_test");
  mock.create.mockReset(); mock.getUser.mockReset();
  mock.create.mockReturnValue({ auth: { getUser: mock.getUser } });
  mock.getUser.mockResolvedValue({ data: { user: null }, error: null });
});
describe("server route protection", () => {
  it("redirects signed-out page requests preserving destination", async () => {
    const r = await updateSession(new NextRequest("https://app.test/dashboard?year=2026"));
    expect(r.status).toBe(307);
    expect(new URL(r.headers.get("location")!).searchParams.get("next")).toBe("/dashboard?year=2026");
    expect(r.headers.get("cache-control")).toContain("no-store");
  });
  it("returns 401 for unauthenticated APIs", async () => {
    const r = await updateSession(new NextRequest("https://app.test/api/session"));
    expect(r.status).toBe(401);
    expect(await r.json()).toEqual({ error: "Authentication required" });
  });
  it("allows a verified user", async () => {
    mock.getUser.mockResolvedValue({ data: { user: { id: "verified", is_anonymous: false } }, error: null });
    expect((await updateSession(new NextRequest("https://app.test/dashboard"))).status).toBe(200);
  });
  it("rejects anonymous identities and rejected sessions", async () => {
    mock.getUser.mockResolvedValue({ data: { user: { is_anonymous: true } }, error: null });
    expect((await updateSession(new NextRequest("https://app.test/api/session"))).status).toBe(401);
    mock.getUser.mockResolvedValue({ data: { user: { id: "forged" } }, error: new Error("Invalid token") });
    expect((await updateSession(new NextRequest("https://app.test/api/session"))).status).toBe(401);
  });
  it("preserves refreshed cookies on redirects", async () => {
    mock.create.mockImplementation((_url, _key, options) => ({ auth: { getUser: async () => {
      options.cookies.setAll([{ name: "session", value: "", options: { maxAge: 0, path: "/" } }], { "Cache-Control": "private, no-store" });
      return { data: { user: null }, error: null };
    } } }));
    const r = await updateSession(new NextRequest("https://app.test/dashboard"));
    expect(r.cookies.get("session")?.value).toBe("");
    expect(r.headers.get("set-cookie")).toContain("Max-Age=0");
  });
  it("allows login when configuration is missing but fails closed for private routes", async () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "");
    expect((await updateSession(new NextRequest("https://app.test/login"))).status).toBe(200);
    expect((await updateSession(new NextRequest("https://app.test/api/session"))).status).toBe(401);
    expect(mock.create).not.toHaveBeenCalled();
  });
});
