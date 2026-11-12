import { EmptyState, MobileShell } from "../../design/mobile-shell";

export default function TodayPage() {
  return <MobileShell><div className="page-heading"><p className="eyebrow">GÜNLÜK BAXIŞ</p><h1>Bu gün</h1><p>Giriş, çıxış və hazırlıq işləri burada görünəcək.</p></div><EmptyState title="Bugünkü plan yüklənməyib" detail="Giriş, çıxış və hazırlıq işləri yalnız server məlumatı gəldikdən sonra göstəriləcək." /></MobileShell>;
}
