import { EmptyState, MobileShell } from "../../design/mobile-shell";

export default function CalendarPage() {
  return <MobileShell><div className="page-heading"><p className="eyebrow">TARİXLƏR</p><h1>Təqvim</h1><p>İcazəli evlər üçün agenda və bir evin ay görünüşü burada olacaq.</p></div><EmptyState title="Təqvim yüklənməyib" detail="İcazəli evlərin tarixləri yalnız server məlumatı gəldikdən sonra göstəriləcək. Tarix seçimi rezervasiya yaratmır." /></MobileShell>;
}
