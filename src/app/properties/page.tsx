import { EmptyState, MobileShell } from "../../design/mobile-shell";

export default function PropertiesPage() {
  return <MobileShell><div className="page-heading"><p className="eyebrow">EVLƏRİNİZ</p><h1>Mənzillər</h1><p>İcazəniz olan bütün evlər burada görünəcək.</p></div><EmptyState title="Ev siyahısı yüklənməyib" detail="İcazəli evlər yalnız giriş və server bağlantısı tamamlandıqdan sonra göstəriləcək." /></MobileShell>;
}
