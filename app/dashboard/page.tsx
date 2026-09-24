import { requireUser } from "@/lib/auth/user";
export default async function Dashboard({ searchParams }: { searchParams: Promise<{ password?: string }> }) {
  await requireUser();
  const params = await searchParams;
  return <section className="dashboard"><p className="eyebrow">YOUR WORKSPACE</p><h1>Power portfolio</h1>{params.password === "updated" && <p role="status" className="notice">Your password has been updated.</p>}<div className="empty-state"><span className="status-dot" /><h2>Your workspace is ready</h2><p>Portfolio data and simulation tools will appear here once connected.</p></div></section>;
}
