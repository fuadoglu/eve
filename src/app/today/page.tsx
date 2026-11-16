import { MobileShell } from "../../design/mobile-shell";
import { TodayView } from "@/modules/today/today-view.tsx";

export const dynamic = "force-dynamic";

export const metadata = {
  title: "Bu gün | Eve",
  robots: { index: false, follow: false },
};

export default function TodayPage() {
  return <MobileShell><div className="page-heading"><p className="eyebrow">GÜNLÜK BAXIŞ</p><h1>Bu gün</h1><p>Giriş, çıxış, gecikən tapşırıq və pul xatırlatmaları.</p></div><TodayView /></MobileShell>;
}
