import Link from "next/link";
export default function Home() {
  return <main className="landing"><p className="eyebrow">POWER SIMULATOR</p><h1>A clear view of your<br />power portfolio.</h1><p className="lead">Your workspace for power portfolio analysis and simulation.</p><Link className="button" href="/dashboard">Open workspace <span aria-hidden="true">↗</span></Link><p className="muted">Sign in to access your workspace.</p></main>;
}
