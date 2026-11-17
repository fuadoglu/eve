import { EmptyState, MobileShell } from "../../design/mobile-shell";
import { CalendarAgenda } from "@/modules/reservations/calendar-agenda.tsx";
import { ReservationCreatePanel } from "@/modules/reservations/reservation-create-panel.tsx";
import { listReservableProperties, ReservationApiError } from "@/modules/reservations/supabase-reservation-api.ts";
import { CalendarApiError, listCalendarPropertyOptions } from "@/modules/reservations/supabase-calendar-api.ts";

export const dynamic = "force-dynamic";

export const metadata = {
  title: "Təqvim | Eve",
  robots: { index: false, follow: false },
};

export default async function CalendarPage() {
  let properties: Awaited<ReturnType<typeof listReservableProperties>> = [];
  let calendarProperties: Awaited<ReturnType<typeof listCalendarPropertyOptions>> = [];
  let loadFailed = false;
  let calendarLoadFailed = false;
  try { properties = await listReservableProperties(); }
  catch (error) {
    const diagnostic = error instanceof ReservationApiError
      ? error.code
      : error instanceof Error
        ? `${error.name}:${error.message.replace(/(Bearer\s+)[^\s]+|eyJ[a-zA-Z0-9_.-]+/g, "$1[redacted]").slice(0, 240)}`
        : "UNEXPECTED";
    console.error("reservation_property_context_load_failed", diagnostic);
    loadFailed = true; /* keep provider details out of the UI */
  }
  try { calendarProperties = await listCalendarPropertyOptions(); }
  catch (error) {
    const diagnostic = error instanceof CalendarApiError ? error.code : error instanceof Error ? error.name : "UNEXPECTED";
    console.error("calendar_property_options_load_failed", diagnostic);
    calendarLoadFailed = true;
  }
  return <MobileShell>
    <div className="page-heading"><p className="eyebrow">TARİXLƏR</p><h1>Təqvim və rezervasiya</h1><p>Rezervasiya serverdə təsdiqləndikdən sonra saxlanmış sayılır. Tarix seçimi təkbaşına rezervasiya yaratmır.</p></div>
    <CalendarAgenda properties={calendarProperties} loadError={calendarLoadFailed} />
    {loadFailed ? <EmptyState title="Evlər yüklənmədi" detail="Bağlantını yoxlayıb səhifəni yeniləyin." /> :
      properties.length === 0 ? <EmptyState title="Rezervasiya üçün ev tapılmadı" detail="Aktiv sessiyası və rezervasiya icazəsi olan evlər burada görünəcək." /> :
      <section aria-labelledby="calendar-create-title">
        <div className="page-heading"><h2 id="calendar-create-title">Yeni rezervasiya</h2><p>Yaradılacaq ev üçün formu seçin.</p></div>
        <div className="reservation-create-list">{properties.map((property) => <section className="reservation-create-property" key={property.id}>
          <h3>{property.name}</h3>
          <ReservationCreatePanel property={property} defaultCustodian={property.default_custodian} />
        </section>)}</div>
      </section>}
  </MobileShell>;
}
