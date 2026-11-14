import { EmptyState, MobileShell } from "../../design/mobile-shell";
import { ReservationCreatePanel } from "@/modules/reservations/reservation-create-panel.tsx";
import { listReservableProperties, ReservationApiError } from "@/modules/reservations/supabase-reservation-api.ts";

export const dynamic = "force-dynamic";

export default async function CalendarPage() {
  let properties: Awaited<ReturnType<typeof listReservableProperties>> = [];
  let loadFailed = false;
  try { properties = await listReservableProperties(); }
  catch (error) {
    console.error("reservation_property_context_load_failed", error instanceof ReservationApiError ? error.code : "UNEXPECTED");
    loadFailed = true; /* keep provider details out of the UI */
  }
  return <MobileShell><div className="page-heading"><p className="eyebrow">TARİXLƏR</p><h1>Təqvim və rezervasiya</h1><p>Rezervasiya serverdə təsdiqləndikdən sonra saxlanmış sayılır. Tarix seçimi təkbaşına rezervasiya yaratmır.</p></div>
    {loadFailed ? <EmptyState title="Evlər yüklənmədi" detail="Bağlantını yoxlayıb səhifəni yeniləyin." /> :
      properties.length === 0 ? <EmptyState title="Rezervasiya üçün ev tapılmadı" detail="Aktiv sessiyası və rezervasiya icazəsi olan evlər burada görünəcək." /> :
      <div className="reservation-create-list">{properties.map((property) => <section className="reservation-create-property" key={property.id}>
        <h2>{property.name}</h2>
        <ReservationCreatePanel property={property} defaultCustodian={property.default_custodian} />
      </section>)}</div>}
  </MobileShell>;
}
