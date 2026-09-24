import { AuthForm } from "@/components/auth-form";
import { isSupabaseConfigured } from "@/lib/supabase/config";
export const dynamic = "force-dynamic";
export default function ForgotPassword() { return <main className="auth-shell"><AuthForm mode="forgot" configured={isSupabaseConfigured()} /></main>; }
