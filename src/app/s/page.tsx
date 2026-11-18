import type { Metadata } from "next";

export const metadata: Metadata = { title: "Tapşırıq keçidi — Eve", robots: { index: false, follow: false },
  referrer: "no-referrer" };
export default function Page() {
  return <main style={{ maxWidth: 480, margin: "4rem auto", padding: "1.5rem" }}>
    <h1>Tapşırıq keçidi</h1><p>Bu səhifəni yenilədinizsə, göndərilən keçidi yenidən açın.</p>
  </main>;
}
