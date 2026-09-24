// Local HTTP test double only. No real users, mail, credentials or Supabase project.
import { createServer } from "node:http";
const user = { id: "11111111-1111-4111-8111-111111111111", aud: "authenticated", role: "authenticated", email: "tester@example.com", email_confirmed_at: "2026-01-01T00:00:00Z", app_metadata: {}, user_metadata: {}, is_anonymous: false, created_at: "2026-01-01T00:00:00Z" };
const b64 = v => Buffer.from(JSON.stringify(v)).toString("base64url");
function session() {
  const exp = Math.floor(Date.now()/1000)+3600;
  return { access_token: `${b64({alg:"HS256",typ:"JWT"})}.${b64({sub:user.id,aud:"authenticated",role:"authenticated",exp})}.test-signature`, refresh_token: "test-refresh-token", token_type: "bearer", expires_in: 3600, expires_at: exp, user };
}
createServer(async (req,res) => {
  let text = ""; for await (const chunk of req) text += chunk;
  const body = text ? JSON.parse(text) : {};
  const url = new URL(req.url, "http://127.0.0.1:54329");
  res.setHeader("Content-Type", "application/json");
  const send = (status, value) => { res.statusCode=status; res.end(JSON.stringify(value)); };
  if (url.pathname === "/auth/v1/token") {
    if ((url.searchParams.get("grant_type") === "password" && body.password === "valid-password-123") || (url.searchParams.get("grant_type") === "pkce" && body.auth_code === "valid-code") || (url.searchParams.get("grant_type") === "refresh_token" && body.refresh_token === "test-refresh-token")) return send(200,session());
    return send(400,{error_code:"invalid_credentials",msg:"Invalid credentials"});
  }
  if (url.pathname === "/auth/v1/user") {
    if (!req.headers.authorization?.endsWith(".test-signature")) return send(401,{msg:"Invalid JWT"});
    return send(200,user);
  }
  if (url.pathname === "/auth/v1/signup") return send(200,{...user, email:body.email});
  if (["/auth/v1/recover","/auth/v1/logout"].includes(url.pathname)) return send(200,{});
  return send(200,{ok:true});
}).listen(54329,"127.0.0.1");
