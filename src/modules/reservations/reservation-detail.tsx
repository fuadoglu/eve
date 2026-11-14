import {
  formatAznMinor,
  type ReservationDto,
} from "./reservation-contract.ts";

const statusLabels: Record<ReservationDto["status"], string> = {
  hold: "Müvəqqəti saxlanılıb",
  confirmed: "Təsdiqlənib",
  checked_in: "Giriş edib",
  completed: "Tamamlanıb",
  cancelled: "Ləğv edilib",
  no_show: "Gəlməyib",
};

export function ReservationDetail({ reservation, propertyName }: { reservation: ReservationDto; propertyName: string }) {
  const { balance } = reservation;
  return (
    <article className="reservation-card" aria-labelledby="reservation-detail-title">
      <header className="reservation-detail-heading">
        <div>
          <p className="eyebrow">REZERVASİYA</p>
          <h2 id="reservation-detail-title">{reservation.guest_name}</h2>
          <p>{propertyName}</p>
        </div>
        <span className={`reservation-status reservation-status-${reservation.status}`}>{statusLabels[reservation.status]}</span>
      </header>
      <dl className="reservation-facts">
        <div><dt>Giriş</dt><dd>{formatDate(reservation.check_in)}{reservation.check_in_time ? ` · ${reservation.check_in_time}` : ""}</dd></div>
        <div><dt>Çıxış</dt><dd>{formatDate(reservation.check_out)}{reservation.check_out_time ? ` · ${reservation.check_out_time}` : ""}</dd></div>
        {reservation.guest_count !== undefined && <div><dt>Qonaqlar</dt><dd>{reservation.guest_count}</dd></div>}
        {reservation.guest_phone && <div><dt>Telefon</dt><dd><a href={`tel:${reservation.guest_phone}`}>{reservation.guest_phone}</a></dd></div>}
      </dl>
      <section className="reservation-balance" aria-labelledby="reservation-balance-title">
        <h3 id="reservation-balance-title">Pul xülasəsi</h3>
        <dl>
          <div><dt>Ümumi qiymət</dt><dd>{formatAznMinor(reservation.total_minor)}</dd></div>
          <div><dt>Kirayə alınıb</dt><dd>{formatAznMinor(balance.rent_received_minor)}</dd></div>
          <div className="reservation-balance-primary"><dt>Qalıb</dt><dd>{formatAznMinor(balance.remaining_minor)}</dd></div>
          {balance.overpaid_minor > 0 && <div><dt>Artıq ödəniş</dt><dd>{formatAznMinor(balance.overpaid_minor)}</dd></div>}
          {balance.rent_refunded_minor > 0 && <div><dt>Kirayə qaytarılıb</dt><dd>{formatAznMinor(balance.rent_refunded_minor)}</dd></div>}
          {balance.deposit_held_minor > 0 && <div><dt>Saxlanılan depozit</dt><dd>{formatAznMinor(balance.deposit_held_minor)}</dd></div>}
        </dl>
        <p className="reservation-inline-note">Balans serverdən alınıb.</p>
      </section>
      {reservation.commission && (
        <section className="reservation-note" aria-label="Realtor komissiyası">
          <h3>Realtor komissiyası</h3>
          <p>{formatCommission(reservation.commission)}</p>
        </section>
      )}
      {reservation.note && <section className="reservation-note"><h3>Qeyd</h3><p>{reservation.note}</p></section>}
    </article>
  );
}

function formatCommission(commission: NonNullable<ReservationDto["commission"]>): string {
  if (commission.kind === "fixed" && commission.fixed_minor !== undefined) {
    return `Sabit · ${formatAznMinor(commission.fixed_minor)}`;
  }
  const basisPoints = commission.percentage_basis_points ?? 0;
  const whole = Math.floor(basisPoints / 100);
  const fractional = basisPoints % 100;
  const percentage = fractional === 0 ? String(whole) : `${whole},${String(fractional).padStart(2, "0")}`;
  const basis = commission.basis_minor === undefined ? "" : ` · baza ${formatAznMinor(commission.basis_minor)}`;
  return `${percentage}%${basis}`;
}

function formatDate(value: string): string {
  const [year, month, day] = value.split("-").map(Number);
  return new Intl.DateTimeFormat("az-AZ", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" })
    .format(new Date(Date.UTC(year, month - 1, day)));
}
