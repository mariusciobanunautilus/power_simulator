import { AuthForm } from "@/components/auth-form";
import { isSupabaseConfigured } from "@/lib/supabase/config";
export const dynamic = "force-dynamic";
export default function Signup() { return <main className="auth-shell"><AuthForm mode="signup" configured={isSupabaseConfigured()} /></main>; }
