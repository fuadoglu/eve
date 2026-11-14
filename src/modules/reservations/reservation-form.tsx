"use client";

import { cloneElement, isValidElement, useRef, useState, type FormEvent } from "react";
import {
  getReservationIdempotencyState,
  mapReservationApiError,
  newReservationIdempotencyKey,
  parseAznMinor,
  parseReservationEnvelope,
  toReservationCreateInput,
  validateReservationDraft,
  type CreateReservationStatus,
  type ReservationContactOption,
  type ReservationDraft,
  type ReservationDraftErrors,
  type ReservationDto,
  type ReservationProvider,
  type ReservationPropertyContext,
} from "./reservation-contract.ts";

export function ReservationForm({
  property,
  defaultCustodian,
  contacts,
  provider,
  onCreated,
}: {
  property: ReservationPropertyContext;
  defaultCustodian: "owner" | "manager";
  contacts: ReservationContactOption[];
  provider: ReservationProvider;
  onCreated: (reservation: ReservationDto) => void;
}) {
  const [draft, setDraft] = useState<ReservationDraft>(() => createEmptyDraft(property, defaultCustodian));
  const [errors, setErrors] = useState<ReservationDraftErrors>({});
  const [submitting, setSubmitting] = useState(false);
  const [requestError, setRequestError] = useState<string | null>(null);
  const [submitStatus, setSubmitStatus] = useState<CreateReservationStatus>("confirmed");
  const keyRef = useRef<{ fingerprint: string; key: string } | null>(null);

  function update<K extends keyof ReservationDraft>(key: K, value: ReservationDraft[K]) {
    setDraft((current) => ({ ...current, [key]: value }));
    setErrors((current) => ({ ...current, [key]: undefined }));
    setRequestError(null);
  }

  async function submit(status: CreateReservationStatus) {
    const nextErrors = validateReservationDraft(draft, property);
    setErrors(nextErrors);
    setSubmitStatus(status);
    if (Object.keys(nextErrors).length > 0) return;
    if (status === "hold" && !["one_hour", "three_hours", "tomorrow_noon"].includes(draft.hold_duration)) {
      setErrors((current) => ({ ...current, hold_duration: "Müvəqqəti saxlanma müddətini seçin." }));
      return;
    }
    if (typeof navigator !== "undefined" && !navigator.onLine) {
      setRequestError("Bağlantı yoxdur. Son dəyişiklik hələ saxlanılmayıb.");
      return;
    }

    let input;
    try {
      input = toReservationCreateInput(draft, property, status, nextErrors);
    } catch {
      setRequestError("Məlumatları yoxlayın və yenidən cəhd edin.");
      return;
    }
    keyRef.current = getReservationIdempotencyState(input, keyRef.current, newReservationIdempotencyKey);
    setSubmitting(true);
    setRequestError(null);
    let created: ReservationDto | null = null;
    try {
      const response = parseReservationEnvelope(await provider.createReservation(input, keyRef.current.key));
      if (response.data.property_id !== property.id) throw new TypeError("reservation_property_scope_mismatch");
      created = response.data;
    } catch (error) {
      const mapped = mapReservationApiError(error);
      setErrors(mapped.fieldErrors);
      setRequestError(mapped.message);
    } finally {
      setSubmitting(false);
    }
    if (created) {
      try {
        onCreated(created);
      } catch {
        setRequestError("Rezervasiya yaradıldı, lakin ekran yenilənmədi. Siyahını yeniləyin.");
      }
    }
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    void submit("confirmed");
  }

  const guestCount = Number(draft.guest_count);
  const exceedsCapacity = Number.isSafeInteger(guestCount) && guestCount > property.max_guests;
  const totalMinorPreview = parseAznMinor(draft.total_azn);
  const receiptAmount = draft.receipt_azn.trim() ? parseAznMinor(draft.receipt_azn, false) : 0;

  return (
    <section className="reservation-card" aria-labelledby="reservation-form-title">
      <div className="reservation-heading">
        <p className="eyebrow">YENİ REZERVASİYA</p>
        <h2 id="reservation-form-title">{property.name}</h2>
        <p>Tarix və qonaq məlumatını daxil edin. Rezervasiya yalnız server təsdiqindən sonra yaranır.</p>
      </div>
      <form className="reservation-form" onSubmit={handleSubmit} noValidate>
        <div className="reservation-grid">
          <Field label="Giriş tarixi" error={errors.check_in}>
            <input type="date" required value={draft.check_in} aria-invalid={Boolean(errors.check_in)} onChange={(event) => update("check_in", event.currentTarget.value)} />
          </Field>
          <Field label="Çıxış tarixi" error={errors.check_out}>
            <input type="date" required min={draft.check_in || undefined} value={draft.check_out} aria-invalid={Boolean(errors.check_out)} onChange={(event) => update("check_out", event.currentTarget.value)} />
          </Field>
        </div>
        <Field label="Qonağın adı" error={errors.guest_name}>
          <input autoComplete="name" maxLength={150} required value={draft.guest_name} aria-invalid={Boolean(errors.guest_name)} onChange={(event) => update("guest_name", event.currentTarget.value)} />
        </Field>
        <div className="reservation-grid">
          <Field label="Telefon (istəyə bağlı)" error={errors.guest_phone}>
            <input type="tel" inputMode="tel" autoComplete="tel" placeholder="+994501234567" value={draft.guest_phone} aria-invalid={Boolean(errors.guest_phone)} onChange={(event) => update("guest_phone", event.currentTarget.value)} />
          </Field>
          <Field label="Qonaq sayı" error={errors.guest_count}>
            <input type="number" min={1} max={1000} step={1} inputMode="numeric" value={draft.guest_count} aria-invalid={Boolean(errors.guest_count)} onChange={(event) => update("guest_count", event.currentTarget.value)} />
          </Field>
        </div>
        {exceedsCapacity && (
          <label className="reservation-confirmation">
            <input type="checkbox" checked={draft.capacity_override_confirmed}
              aria-invalid={Boolean(errors.capacity_override_confirmed)}
              aria-describedby={errors.capacity_override_confirmed ? "reservation-capacity-error" : undefined}
              onChange={(event) => update("capacity_override_confirmed", event.currentTarget.checked)} />
            <span>{property.max_guests} nəfərlik tutumdan artıq qonaq sayını təsdiqləyirəm.</span>
          </label>
        )}
        {errors.capacity_override_confirmed && <p id="reservation-capacity-error" className="reservation-field-error" role="alert">{errors.capacity_override_confirmed}</p>}

        <div className="reservation-grid">
          <Field label="Giriş saatı" error={errors.check_in_time}>
            <input type="time" value={draft.check_in_time} aria-invalid={Boolean(errors.check_in_time)} onChange={(event) => update("check_in_time", event.currentTarget.value)} />
          </Field>
          <Field label="Çıxış saatı" error={errors.check_out_time}>
            <input type="time" value={draft.check_out_time} aria-invalid={Boolean(errors.check_out_time)} onChange={(event) => update("check_out_time", event.currentTarget.value)} />
          </Field>
        </div>
        <Field label="Ümumi qiymət (AZN)" error={errors.total_azn}>
          <input inputMode="decimal" autoComplete="off" placeholder="300,00" value={draft.total_azn} aria-invalid={Boolean(errors.total_azn)} onChange={(event) => update("total_azn", event.currentTarget.value)} />
        </Field>
        {totalMinorPreview === 0 && (
          <label className="reservation-confirmation">
            <input type="checkbox" checked={draft.free_stay}
              aria-invalid={Boolean(errors.free_stay)}
              aria-describedby={errors.free_stay ? "reservation-free-stay-error" : undefined}
              onChange={(event) => update("free_stay", event.currentTarget.checked)} />
            <span>Ödənişsiz qalma</span>
          </label>
        )}
        {errors.free_stay && <p id="reservation-free-stay-error" className="reservation-field-error" role="alert">{errors.free_stay}</p>}

        <details className="reservation-more">
          <summary>Əlavə məlumat</summary>
          <div className="reservation-more-content">
            <Field label="Alınan pul (AZN, istəyə bağlı)" error={errors.receipt_azn}>
              <input inputMode="decimal" autoComplete="off" placeholder="Boş saxlayın, sonra əlavə edin" value={draft.receipt_azn} aria-invalid={Boolean(errors.receipt_azn)} onChange={(event) => update("receipt_azn", event.currentTarget.value)} />
            </Field>
            <div className="reservation-grid">
              <Field label="Pulun növü">
                <select value={draft.receipt_kind} onChange={(event) => update("receipt_kind", event.currentTarget.value as ReservationDraft["receipt_kind"])}>
                  <option value="rent_receipt">Kirayə</option>
                  <option value="deposit_receipt">Depozit</option>
                </select>
              </Field>
              <Field label="Pulu alan">
                <select value={draft.custodian} onChange={(event) => update("custodian", event.currentTarget.value as ReservationDraft["custodian"])}>
                  <option value={defaultCustodian}>{defaultCustodian === "owner" ? "Sahib" : "Menecer"}</option>
                  {defaultCustodian !== "owner" && <option value="owner">Sahib</option>}
                  {contacts.length > 0 && <option value="realtor">Realtor</option>}
                </select>
              </Field>
            </div>
            {draft.custodian === "realtor" && (
              <Field label="Realtor" error={errors.receipt_contact_id}>
                <select value={draft.receipt_contact_id} aria-invalid={Boolean(errors.receipt_contact_id)} onChange={(event) => update("receipt_contact_id", event.currentTarget.value)}>
                  <option value="">Realtor seçin</option>
                  {contacts.map((contact) => <option key={contact.id} value={contact.id}>{contact.name}</option>)}
                </select>
              </Field>
            )}
            {receiptAmount !== null && receiptAmount > 0 && (
              <p className="reservation-inline-note">Pul qeydi rezervasiya ilə eyni əməliyyatda serverdə yazılacaq.</p>
            )}
            <Field label="Realtor komissiyası (istəyə bağlı)" error={errors.commission_contact_id}>
              <select value={draft.commission_contact_id} aria-invalid={Boolean(errors.commission_contact_id)} onChange={(event) => update("commission_contact_id", event.currentTarget.value)}>
                <option value="">Komissiya yoxdur</option>
                {contacts.map((contact) => <option key={contact.id} value={contact.id}>{contact.name}</option>)}
              </select>
            </Field>
            {draft.commission_contact_id && (
              <div className="reservation-grid">
                <Field label="Hesablama növü">
                  <select value={draft.commission_kind} onChange={(event) => update("commission_kind", event.currentTarget.value as ReservationDraft["commission_kind"])}>
                    <option value="percentage">Faiz</option>
                    <option value="fixed">Sabit məbləğ</option>
                  </select>
                </Field>
                <Field label={draft.commission_kind === "fixed" ? "Məbləğ (AZN)" : "Faiz (%)"} error={errors.commission_value}>
                  <input inputMode="decimal" autoComplete="off" placeholder={draft.commission_kind === "fixed" ? "20,00" : "10"} value={draft.commission_value} aria-invalid={Boolean(errors.commission_value)} onChange={(event) => update("commission_value", event.currentTarget.value)} />
                </Field>
              </div>
            )}
            <Field label="Qeyd (istəyə bağlı)" error={errors.note}>
              <textarea maxLength={2000} rows={3} value={draft.note} aria-invalid={Boolean(errors.note)} onChange={(event) => update("note", event.currentTarget.value)} />
            </Field>
            <fieldset className="reservation-hold-options">
              <legend>Müvəqqəti saxlama müddəti</legend>
              <select value={draft.hold_duration} onChange={(event) => update("hold_duration", event.currentTarget.value as ReservationDraft["hold_duration"])}>
                <option value="one_hour">1 saat</option>
                <option value="three_hours">3 saat</option>
                <option value="tomorrow_noon">Sabah saat 12:00</option>
              </select>
              <p className="reservation-inline-note">Vaxt Bakı vaxtı ilə hesablanır.</p>
            </fieldset>
          </div>
        </details>

        {requestError && <p className="reservation-request-error" role="alert">{requestError}</p>}
        <div className="reservation-actions">
          <button className="reservation-submit" type="submit" disabled={submitting} aria-busy={submitting}>
            {submitting && submitStatus === "confirmed" ? "Yoxlanılır…" : "Təsdiqlə"}
          </button>
          <button className="reservation-hold" type="button" disabled={submitting} onClick={() => void submit("hold")}>
            {submitting && submitStatus === "hold" ? "Yoxlanılır…" : "Müvəqqəti saxla"}
          </button>
        </div>
      </form>
    </section>
  );
}

function Field({ label, error, children }: { label: string; error?: string; children: React.ReactNode }) {
  const errorId = error ? `reservation-error-${label.toLowerCase().replace(/[^a-z0-9]+/g, "-")}` : undefined;
  const control = error && isValidElement(children)
    ? cloneElement(children as React.ReactElement<{ id?: string; "aria-describedby"?: string; "aria-invalid"?: boolean }>, {
      id: `reservation-field-${label.toLowerCase().replace(/[^a-z0-9]+/g, "-")}`,
      "aria-describedby": errorId,
      "aria-invalid": true,
    })
    : children;
  return (
    <label className="reservation-field">
      <span>{label}</span>
      {control}
      {error && <small id={errorId} className="reservation-field-error" role="alert">{error}</small>}
    </label>
  );
}

function createEmptyDraft(property: ReservationPropertyContext, defaultCustodian: "owner" | "manager"): ReservationDraft {
  return {
    guest_name: "",
    guest_phone: "",
    guest_count: "1",
    check_in: "",
    check_out: "",
    check_in_time: property.default_check_in,
    check_out_time: property.default_check_out,
    total_azn: "",
    free_stay: false,
    capacity_override_confirmed: false,
    hold_duration: "one_hour",
    receipt_azn: "",
    receipt_kind: "rent_receipt",
    custodian: defaultCustodian,
    receipt_contact_id: "",
    commission_contact_id: "",
    commission_kind: "percentage",
    commission_value: "",
    note: "",
  };
}
