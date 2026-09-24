import { AuthForm } from "@/components/auth-form";
import { requireUser } from "@/lib/auth/user";
export const dynamic = "force-dynamic";
export default async function UpdatePassword() { await requireUser("/update-password"); return <main className="auth-shell"><AuthForm mode="update" /></main>; }
