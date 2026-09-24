import { requireUser } from "@/lib/auth/user";
import { SignOut } from "@/components/sign-out";
export const dynamic = "force-dynamic";
export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const user = await requireUser();
  return <main className="workspace"><header><span className="brand">POWER SIMULATOR</span><div className="user-menu"><span>{user.email}</span><SignOut /></div></header>{children}</main>;
}
