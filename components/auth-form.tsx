"use client";
import Link from "next/link";
import { useActionState, useState } from "react";
import { login, signup, forgotPassword, updatePassword, type FormState } from "@/app/auth/actions";
const modes = {
  login: { title: "Welcome back", description: "Sign in to your Power Simulator workspace.", action: login, button: "Sign in" },
  signup: { title: "Create your account", description: "Start your Power Simulator workspace.", action: signup, button: "Create account" },
  forgot: { title: "Reset your password", description: "We’ll email you a link to choose a new password.", action: forgotPassword, button: "Send reset link" },
  update: { title: "Choose a new password", description: "Use at least 12 characters to secure your account.", action: updatePassword, button: "Save password" },
};
export function AuthForm({ mode, next = "/dashboard", configured = true }: { mode: keyof typeof modes; next?: string; configured?: boolean }) {
  const details = modes[mode];
  const [email, setEmail] = useState("");
  const [state, action, pending] = useActionState<FormState, FormData>(details.action, {});
  return <section className="auth-card">
    <p className="eyebrow">POWER SIMULATOR</p><h1>{details.title}</h1><p className="muted">{details.description}</p>
    {!configured && <p className="notice" role="status">Sign-in is not configured yet. Please contact the app owner.</p>}
    <form action={action}>
      <input type="hidden" name="next" value={next} />
      {mode !== "update" && <label>Email address<input name="email" type="email" value={email} onChange={event => setEmail(event.target.value)} autoComplete="email" maxLength={254} required /></label>}
      {mode !== "forgot" && <label>Password<input name="password" type="password" autoComplete={mode === "login" ? "current-password" : "new-password"} minLength={mode === "login" ? 1 : 12} maxLength={128} required /></label>}
      {mode === "update" && <label>Confirm password<input name="confirmPassword" type="password" autoComplete="new-password" minLength={12} maxLength={128} required /></label>}
      {state.error && <p className="error" role="alert">{state.error}</p>}
      {state.message && <p className="notice" role="status">{state.message}</p>}
      <button disabled={pending || !configured}>{pending ? "Please wait…" : details.button}</button>
    </form>
    <nav className="auth-links" aria-label="Account options">
      {mode === "login" ? <><Link href="/forgot-password">Forgot password?</Link><Link href="/signup">Create an account</Link></> : <Link href="/login">Back to sign in</Link>}
    </nav>
  </section>;
}
