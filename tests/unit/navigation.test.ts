import { describe, expect, it } from "vitest";
import { isPublicPath, safeNext } from "@/lib/auth/navigation";
describe("post-authentication redirects", () => {
  it.each(["https://evil.test", "//evil.test", "/\\evil.test", "/auth/callback", "/login", "/dashboard/../../login", "/dashboard\n", undefined, ["/dashboard"]])("rejects unsafe destination %s", value => expect(safeNext(value)).toBe("/dashboard"));
  it("keeps private paths and query strings", () => expect(safeNext("/dashboard/scenarios?year=2026")).toBe("/dashboard/scenarios?year=2026"));
  it("allows password recovery", () => expect(safeNext("/update-password")).toBe("/update-password"));
  it("does not expose arbitrary auth or API paths", () => {
    expect(isPublicPath("/auth/callback")).toBe(true);
    expect(isPublicPath("/auth/private")).toBe(false);
    expect(isPublicPath("/api/session")).toBe(false);
    expect(isPublicPath("/dashboard/report.csv")).toBe(false);
  });
});
