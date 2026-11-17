import type { Metadata } from "next";
import { ScopedTaskLanding } from "@/modules/operations/scoped-task-landing.tsx";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Tapşırıq keçidi — Eve", robots: { index: false, follow: false },
  referrer: "no-referrer" };

export default async function Page({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  return <ScopedTaskLanding token={token} />;
}
