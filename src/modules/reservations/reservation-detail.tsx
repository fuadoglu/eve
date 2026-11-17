"use client";

import { useEffect, useMemo, useRef, useState, type FormEvent } from "react";
import {
  formatAznMinor,
  parseAznMinor,
  parseReservationEnvelope,
  type ReservationDto,
} from "./reservation-contract.ts";
import { parseRentEntry, type RentEntry } from "../finance/rent-entry-contract.ts";
import { bakuDateToIso, bakuToday, depositTotals, refundableMinor } from "../finance/rent-money-view-model.ts";

const statusLabels: Record<ReservationDto["status"], string> = {
  hold: "Müvəqqəti saxlanılıb",
  confirmed: "Təsdiqlənib",
  checked_in: "Giriş edib",
  completed: "Tamamlanıb",
  cancelled: "Ləğv edilib",
  no_show: "Gəlməyib",
};

export function ReservationDetail({ reservation: initialReservation, propertyName, defaultCustodian }: { reservation: ReservationDto; propertyName: string; defaultCustodian: "owner" | "manager" }) {
  const [reservation, setReservation] = useState(initialReservation);
  const [entries, setEntries] = useState<RentEntry[]>([]);
  const [loadingEntries, setLoadingEntries] = useState(true);
  const [entriesError, setEntriesError] = useState("");
  const [kind, setKind] = useState<"rent_receipt" | "deposit_receipt" | "rent_refund" | "deposit_return">("rent_receipt");
  const [amount, setAmount] = useState("");
  const [custodian, setCustodian] = useState<"owner" | "manager" | "realtor">(defaultCustodian);
  const [date, setDate] = useState(() => bakuToday());
  const [note, setNote] = useState("");
  const [sourceId, setSourceId] = useState("");
  const [saving, setSaving] = useState(false);
  const [uncertain, setUncertain] = useState(false);
  const [formError, setFormError] = useState("");
  const [savedMessage, setSavedMessage] = useState("");
  const keyRef = useRef<{ fingerprint: string; key: string } | null>(null);
  const refundSources = useMemo(() => entries.filter((entry) =>
    (kind === "rent_refund" && ["rent_receipt", "deposit_to_rent"].includes(entry.kind))
    || (kind === "deposit_return" && entry.kind === "deposit_receipt"))
    .map((entry) => ({ entry, remaining: refundableMinor(entry, entries) })).filter((item) => item.remaining > 0), [entries, kind]);
  const deposit = useMemo(() => depositTotals(entries), [entries]);

  async function refreshEntries(): Promise<void> {
    setLoadingEntries(true);
    setEntriesError("");
    try {
      const all: RentEntry[] = [];
      let cursor: string | null = null;
      const seenCursors = new Set<string>();
      do {
        const query = new URLSearchParams({ limit: "100" });
        if (cursor) query.set("cursor", cursor);
        const response = await fetch(`/api/v1/reservations/${reservation.id}/money?${query}`, { credentials: "same-origin", cache: "no-store", headers: { "X-Eve-Same-Origin": "1" } });
        const body: unknown = await response.json();
        if (!response.ok || !isRecord(body) || !isRecord(body.data) || !Array.isArray(body.data.items)
            || !(body.data.next_cursor === null || typeof body.data.next_cursor === "string")) throw new Error("ledger_unavailable");
        const page = body.data.items.map(parseRentEntry);
        if (page.some((entry) => entry === null)) throw new Error("ledger_invalid");
        all.push(...page as RentEntry[]);
        cursor = body.data.next_cursor;
        if (cursor && (seenCursors.has(cursor) || seenCursors.size >= 99)) throw new Error("ledger_cursor_invalid");
        if (cursor) seenCursors.add(cursor);
      } while (cursor);
      setEntries(all);
    } catch {
      setEntriesError("Pul tarixçəsini yükləmək mümkün olmadı. Bağlantını yoxlayıb yenidən cəhd edin.");
    } finally { setLoadingEntries(false); }
  }

  useEffect(() => { void refreshEntries(); }, [reservation.id]);
  useEffect(() => { if (sourceId && !refundSources.some(({ entry }) => entry.id === sourceId)) setSourceId(""); }, [sourceId, refundSources]);

  async function refreshReservation(): Promise<void> {
    const response = await fetch(`/api/v1/reservations/${reservation.id}`, { credentials: "same-origin", cache: "no-store", headers: { "X-Eve-Same-Origin": "1" } });
    const body: unknown = await response.json();
    const envelope = parseReservationEnvelope(body);
    if (!response.ok || !envelope || envelope.data.id !== reservation.id) throw new Error("balance_unavailable");
    setReservation(envelope.data);
  }

  async function submitMoney(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    const amountMinor = parseAznMinor(amount, false);
    const source = refundSources.find(({ entry }) => entry.id === sourceId);
    if (amountMinor === null || amountMinor < 1 || amountMinor > Number.MAX_SAFE_INTEGER) { setFormError("Məbləği AZN ilə ən çox 2 onluq rəqəmlə yazın."); return; }
    if (note.length > 1000) { setFormError("Qeyd 1000 simvoldan çox ola bilməz."); return; }
    if ((kind === "rent_refund" || kind === "deposit_return") && (!source || amountMinor > source.remaining)) {
      setFormError("Qaytarma məbləği seçilmiş ilkin qeydin qaytarıla bilən qalığını aşa bilməz."); return;
    }
    let occurredAt: string;
    try { occurredAt = bakuDateToIso(date); } catch { setFormError("Tarixi yoxlayın."); return; }
    const selectedCustodian = source?.entry.custodian ?? custodian;
    const contactId = source?.entry.contact_id ?? (selectedCustodian === "realtor" ? reservation.commission?.contact_id : undefined);
    if (selectedCustodian === "realtor" && !contactId) { setFormError("Realtor kontaktı tapılmadı. Rezervasiyanın realtor məlumatını yoxlayın."); return; }
    const payload = { kind, amount_minor: amountMinor, custodian: selectedCustodian,
      ...(contactId ? { contact_id: contactId } : {}), ...(sourceId ? { original_id: sourceId } : {}),
      occurred_at: occurredAt, ...(note.trim() ? { note: note.trim() } : {}) };
    const fingerprint = JSON.stringify(payload);
    if (!keyRef.current || keyRef.current.fingerprint !== fingerprint) keyRef.current = { fingerprint, key: crypto.randomUUID().replaceAll("-", "") };
    setSaving(true); setFormError(""); setSavedMessage("");
    try {
      let response: Response;
      try {
        response = await fetch(`/api/v1/reservations/${reservation.id}/money`, { method: "POST", credentials: "same-origin", cache: "no-store",
          headers: { "Content-Type": "application/json", "Idempotency-Key": keyRef.current.key, "X-Eve-Same-Origin": "1" }, body: JSON.stringify(payload) });
      } catch { setUncertain(true); setFormError("Bağlantı yoxdur. Son dəyişiklik hələ saxlanılmayıb."); return; }
      let body: unknown;
      try { body = await response.json(); } catch { throw new Error("save_response_invalid"); }
      const savedEntry = isRecord(body) && isRecord(body.data) ? parseRentEntry(body.data) : null;
      if (!response.ok) {
        const outcomeMayBeUnknown = response.status >= 500 || [408, 425, 429].includes(response.status);
        setUncertain(outcomeMayBeUnknown);
        if (outcomeMayBeUnknown) {
          setFormError("Server cavabı qeyri-müəyyəndir. Dəyişiklik etmədən eyni sorğu açarı ilə təkrar yoxlayın.");
          return;
        }
        const serverMessage = isRecord(body) && isRecord(body.error) && typeof body.error.message === "string" ? body.error.message : "Pul qeydi serverdə qəbul edilmədi.";
        setFormError(serverMessage); return;
      }
      if (!savedEntry || savedEntry.reservation_id !== reservation.id) throw new Error("save_response_invalid");
      setUncertain(false);
      setSavedMessage("Pul qeydi saxlanıldı. Bu, bank köçürməsi deyil.");
      keyRef.current = null;
      setAmount(""); setNote(""); setSourceId("");
      const refreshResults = await Promise.allSettled([refreshReservation(), refreshEntries()]);
      if (refreshResults[0]?.status === "rejected") setFormError("Pul qeydi saxlanıldı, amma server balansını yeniləmək mümkün olmadı. Səhifəni yeniləyin.");
    } catch { setUncertain(true); setFormError("Server cavabı təsdiqlənmədi. Təkrar cəhd eyni sorğu açarından istifadə edəcək."); }
    finally { setSaving(false); }
  }

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
      <details className="reservation-money-sheet">
        <summary>Pul qeydi əlavə et</summary>
        <form onSubmit={submitMoney}>
          <label>Məbləğ (AZN)<input inputMode="decimal" value={amount} onChange={(event) => setAmount(event.target.value)} required aria-label="Məbləğ (AZN)" disabled={saving || uncertain} /></label>
          <label>Əməliyyat növü<select value={kind} onChange={(event) => { setKind(event.target.value as typeof kind); setSourceId(""); }} disabled={saving || uncertain}>
            <option value="rent_receipt">Kirayə alındı</option><option value="deposit_receipt">Depozit alındı</option>
            <option value="rent_refund">Kirayə qaytarıldı</option><option value="deposit_return">Depozit qaytarıldı</option>
          </select></label>
          {(kind === "rent_refund" || kind === "deposit_return") && <label>İlkin pul qeydi<select value={sourceId} onChange={(event) => setSourceId(event.target.value)} required disabled={saving || uncertain}>
            <option value="">İlkin qeydi seçin</option>{refundSources.map(({ entry, remaining }) => <option key={entry.id} value={entry.id}>{formatAznMinor(remaining)} · {formatDate(entry.occurred_at.slice(0, 10))} · {entry.kind === "deposit_receipt" ? "depozit" : "kirayə"}</option>)}
          </select><span className="reservation-inline-note">Qaytarıla bilən limit: {sourceId ? formatAznMinor(refundSources.find(({ entry }) => entry.id === sourceId)?.remaining ?? 0) : "—"}</span></label>}
          {(kind === "rent_refund" || kind === "deposit_return") && sourceId
            ? <p>Pulu alan: {refundSources.find(({ entry }) => entry.id === sourceId)?.entry.custodian === "realtor" ? "Realtor" : refundSources.find(({ entry }) => entry.id === sourceId)?.entry.custodian === "manager" ? "Menecer" : "Sahib"} (ilkin qeyddən)</p>
            : <label>Pulu alan<select value={custodian} onChange={(event) => setCustodian(event.target.value as typeof custodian)} disabled={saving || uncertain}><option value="owner">Sahib</option><option value="manager">Menecer</option>{reservation.commission?.contact_id && <option value="realtor">Realtor</option>}</select></label>}
          <label>Tarix<input type="date" value={date} onChange={(event) => setDate(event.target.value)} required disabled={saving || uncertain} /></label>
          <label>Qeyd (istəyə görə)<textarea value={note} maxLength={1000} onChange={(event) => setNote(event.target.value)} rows={2} disabled={saving || uncertain} /></label>
          {kind === "rent_refund" || kind === "deposit_return" ? <p>Bu qeyddən sonra server balansı yenilənəcək.</p> : <p>Serverdən gələn qalıq: {formatAznMinor(balance.remaining_minor)} · artıq ödəniş: {formatAznMinor(balance.overpaid_minor)}</p>}
          {formError && <p role="alert">{formError}</p>}{savedMessage && <p role="status">{savedMessage}</p>}
          <button type="submit" disabled={saving}>{saving ? "Saxlanılır…" : uncertain ? "Təkrar yoxla" : "Qeydə al"}</button>
        </form>
      </details>
      <section className="reservation-money-history" aria-labelledby="money-history-title">
        <h3 id="money-history-title">Pul tarixçəsi</h3>
        <dl className="reservation-deposit-summary"><div><dt>Depozit alınıb</dt><dd>{loadingEntries || entriesError ? "—" : formatAznMinor(deposit.received_minor)}</dd></div><div><dt>Depozit qaytarılıb</dt><dd>{loadingEntries || entriesError ? "—" : formatAznMinor(deposit.returned_minor)}</dd></div><div><dt>Saxlanılan depozit</dt><dd>{formatAznMinor(balance.deposit_held_minor)}</dd></div></dl>
        {loadingEntries ? <p>Yüklənir…</p> : entriesError ? <p role="alert">{entriesError} <button type="button" onClick={() => void refreshEntries()}>Yenidən yoxla</button></p>
          : entries.length === 0 ? <p>Hələ pul qeydi yoxdur.</p> : <ul>{entries.map((entry) => <li key={entry.id}><span>{entryLabel(entry.kind)}</span><span>{formatAznMinor(entry.amount_minor)}</span><time dateTime={entry.occurred_at}>{formatDate(entry.occurred_at.slice(0, 10))}</time><span>Pulu alan: {custodianLabel(entry.custodian)}</span>{entry.note && <span>{entry.note}</span>}</li>)}</ul>}
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

function entryLabel(kind: RentEntry["kind"]): string {
  return ({ rent_receipt: "Kirayə alındı", rent_refund: "Kirayə qaytarıldı", deposit_receipt: "Depozit alındı", deposit_return: "Depozit qaytarıldı", deposit_to_rent: "Depozit kirayəyə yönəldildi", deposit_to_damage: "Depozit zərərə yönəldildi", reversal: "Əvvəlki qeyd geri çevrildi" })[kind];
}
function custodianLabel(custodian: RentEntry["custodian"]): string { return custodian === "realtor" ? "Realtor" : custodian === "manager" ? "Menecer" : "Sahib"; }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }

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
