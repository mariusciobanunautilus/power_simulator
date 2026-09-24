# Power Simulator

Next.js App Router + TypeScript starter with Supabase Auth and server-protected routes. This repository was empty before this implementation. The dashboard is an authenticated starting point; portfolio calculations and data integration are not implemented yet.

## Connection status

The code is ready to connect, but **no production Supabase project has been selected or modified**. No keys or account data are committed. Browser tests use a local Auth test double; they do not establish that live email delivery or hosted Supabase settings are working.

## Run locally

Use Node.js 22 or later (24 recommended).

```sh
npm ci
cp .env.example .env.local
# Fill in all three variables in .env.local.
npm run dev
```

| Variable | Value |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Project URL from Supabase → Connect |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Publishable key (`sb_publishable_…`) from that project |
| `NEXT_PUBLIC_SITE_URL` | Canonical app origin, e.g. `http://localhost:3000` or `https://your-app.example` |

Use a publishable key. Never put a secret or service-role key in these variables. Set the variables before building for deployment. `.env.local` is ignored by Git.

## Supabase Auth configuration

In the selected Supabase project's dashboard:

1. Enable Email authentication under Authentication → Sign In / Providers. Enable new user sign-ups if this app should accept self-registration.
2. Enable email confirmation. Set the minimum password length to 12 to match this app.
3. Under Authentication → URL Configuration, set Site URL to the canonical app origin.
4. Add these Redirect URLs for development:
   - `http://localhost:3000/auth/callback?next=/dashboard`
   - `http://localhost:3000/auth/callback?next=/update-password`
5. Add the same two callback URLs with your exact production origin when deploying.
6. Keep Supabase's standard confirmation/reset email templates. This app uses PKCE with `/auth/callback` to exchange the returned code for a cookie session. Open confirmation and recovery links in the same browser where the flow started.
7. Configure SMTP for delivery to your intended users. With Supabase's default mail service, recipient restrictions and delivery limits may prevent general-user email delivery; verify delivery before launch.

No database migration is necessary for Auth. No existing tables, policies, users, or project settings have been changed. App access currently means any non-anonymous authenticated user in the selected Supabase project. If this must be an invitation-only or role-restricted workspace, configure that access model before connecting sensitive data.

## Routes

| Route | Access | Purpose |
| --- | --- | --- |
| `/` | Public | Landing page |
| `/login` | Public | Email/password login |
| `/signup` | Public | Registration and email confirmation |
| `/forgot-password` | Public | Request a recovery email |
| `/auth/callback` | Public | PKCE code exchange; rejects invalid or expired codes |
| `/auth/error` | Public | Recoverable confirmation error |
| `/dashboard` and children | Authenticated | Protected workspace |
| `/update-password` | Authenticated | Password update after recovery or sign-in |
| `/api/session` | Authenticated | Current user's ID/email; otherwise HTTP 401 |

Other non-static paths require authentication by default. Add intentional public paths in `lib/auth/navigation.ts`. Next.js static assets bypass Proxy.

## How protection works

- `proxy.ts` refreshes cookie sessions and checks `auth.getUser()` with the Auth server. A cookie's contents alone never authorise a request.
- Protected pages and the API also check the user at the server boundary. New Server Actions and APIs must call `requireUser()` / `getVerifiedUser()` themselves; a layout is not sufficient access control.
- Anonymous Supabase identities cannot enter the workspace.
- Unauthenticated page requests redirect to login; API requests receive JSON with HTTP 401.
- Auth redirects only allow dashboard destinations or `/update-password` on the same app.
- Responses passing through Proxy use `Cache-Control: private, no-store`; refreshed or cleared cookies survive redirects.
- Supabase clients are created per server request. Sign-out is a Server Action (POST), using Next.js origin validation, and clears this browser's session.
- When portfolio tables are added, enable RLS and explicit ownership/membership policies. Route guards do not protect direct database API access.

## Verification

```sh
npm run lint
npm run typecheck
npm test
npm run build
```

Browser tests use a dedicated local HTTP test double, not your Supabase project. Build with the matching test environment first:

```sh
npx playwright install chromium
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54329 \
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=test-publishable-key \
NEXT_PUBLIC_SITE_URL=http://localhost:3100 npm run build
npm run test:e2e
```

Rebuild with real environment settings before deploying. Never deploy the test build.

Coverage includes signed-out route denial, rejected/anonymous sessions, redirect safety, cookie preservation, invalid/valid login, reload persistence, authenticated API access, sign-out, signup confirmation, recovery/password update, and invalid callbacks.

After selecting the hosted project, verify actual sign-up → email → callback → dashboard, login, password recovery, and sign-out with a test account. A successful local test run does not verify provider configuration or email delivery.

## References

- [Supabase SSR setup](https://supabase.com/docs/guides/auth/server-side/creating-a-client)
- [Supabase SSR sessions and PKCE](https://supabase.com/docs/guides/auth/server-side/advanced-guide)
- [Redirect URL configuration](https://supabase.com/docs/guides/auth/redirect-urls)
- [Supabase email delivery](https://supabase.com/docs/guides/auth/auth-smtp)
