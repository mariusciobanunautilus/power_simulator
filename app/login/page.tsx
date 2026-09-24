import { AuthForm } from "@/components/auth-form";
import { safeNext } from "@/lib/auth/navigation";
import { isSupabaseConfigured } from "@/lib/supabase/config";
export const dynamic = "force-dynamic";
export default async function Login({ searchParams }: { searchParams: Promise<{ next?: string }> }) {
  const params = await searchParams;
  return <main className="auth-shell"><AuthForm mode="login" next={safeNext(params.next)} configured={isSupabaseConfigured()} /></main>;
}
