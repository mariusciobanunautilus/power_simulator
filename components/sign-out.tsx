"use client";
import { useActionState } from "react";
import { logout } from "@/app/auth/actions";
export function SignOut() {
  const [state, action, pending] = useActionState(logout, {});
  return <form action={action}><button className="secondary" disabled={pending}>{pending ? "Signing out…" : "Sign out"}</button>{state.error && <p role="alert">{state.error}</p>}</form>;
}
