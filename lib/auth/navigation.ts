const origin = "https://power-simulator.invalid";
export function safeNext(value: unknown, fallback = "/dashboard"): string {
  if (typeof value !== "string" || !value.startsWith("/") || value.startsWith("//") || /[\\\u0000-\u0020]/.test(value)) return fallback;
  try {
    const url = new URL(value, origin);
    // Only app destinations, never auth routes or external URLs.
    if (url.origin !== origin || !(url.pathname === "/dashboard" || url.pathname.startsWith("/dashboard/") || url.pathname === "/update-password")) return fallback;
    return url.pathname + url.search;
  } catch { return fallback; }
}
export function isPublicPath(path: string) {
  return ["/", "/login", "/signup", "/forgot-password", "/auth/callback", "/auth/error"].includes(path);
}
