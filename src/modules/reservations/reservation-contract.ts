export type ReservationStatus = "hold" | "confirmed" | "checked_in" | "completed" | "cancelled" | "no_show";
export type CreateReservationStatus = Extract<ReservationStatus, "hold" | "confirmed">;
export type HoldDuration = "one_hour" | "three_hours" | "tomorrow_noon";
export type ReceiptKind = "rent_receipt" | "deposit_receipt";
export type Custodian = "owner" | "manager" | "realtor";

export type ReservationBalance = {
  rent_received_minor: number;
  rent_refunded_minor: number;
  remaining_minor: number;
  overpaid_minor: number;
  deposit_held_minor: number;
};

export type ReservationDto = {
  id: string;
  property_id: string;
  current_placement_id: string;
  guest_name: string;
  guest_phone?: string | null;
  guest_count?: number;
  check_in: string;
  check_out: string;
  check_in_time?: string;
  check_out_time?: string;
  actual_check_in_at?: string | null;
  actual_check_out_at?: string | null;
  status: ReservationStatus;
  hold_expires_at?: string | null;
  total_minor: number;
  currency: "AZN";
  note?: string;
  commission?: CommissionDto | null;
  balance: ReservationBalance;
  version: number;
  created_at: string;
  updated_at: string;
};

export type CommissionDto = {
  contact_id: string;
  kind: "fixed" | "percentage";
  fixed_minor?: number;
  basis_minor?: number;
  percentage_basis_points?: number;
};

export type ReservationEnvelope = {
  data: ReservationDto;
  meta: { request_id: string };
};

export type ReservationCreateInput = {
  property_id: string;
  guest_name: string;
  guest_phone?: string;
  guest_count: number;
  check_in: string;
  check_out: string;
  check_in_time?: string;
  check_out_time?: string;
  status: CreateReservationStatus;
  hold_duration?: HoldDuration;
  total_minor: number;
  capacity_override_confirmed?: boolean;
  initial_receipt?: {
    amount_minor: number;
    kind: ReceiptKind;
    custodian: Custodian;
    contact_id?: string;
  };
  commission?: CommissionDto;
  note?: string;
  free_stay?: boolean;
};

export type ReservationPropertyContext = {
  id: string;
  name: string;
  max_guests: number;
  default_check_in: string;
  default_check_out: string;
};

export type ReservationContactOption = { id: string; name: string };

export type ReservationProvider = {
  createReservation(input: ReservationCreateInput, idempotencyKey: string): Promise<ReservationEnvelope>;
};

export type ReservationIdempotencyState = { fingerprint: string; key: string };
export type ReservationApiFieldError = { field: string; code: string; message: string };
export type ReservationApiError = { error: { code: string; field_errors?: ReservationApiFieldError[]; request_id?: string } };

export type ReservationDraft = {
  guest_name: string;
  guest_phone: string;
  guest_count: string;
  check_in: string;
  check_out: string;
  check_in_time: string;
  check_out_time: string;
  total_azn: string;
  free_stay: boolean;
  capacity_override_confirmed: boolean;
  hold_duration: HoldDuration;
  receipt_azn: string;
  receipt_kind: ReceiptKind;
  custodian: Custodian;
  receipt_contact_id: string;
  commission_contact_id: string;
  commission_kind: "fixed" | "percentage";
  commission_value: string;
  note: string;
};

export type ReservationDraftErrors = Partial<Record<keyof ReservationDraft, string>>;

export function parseAznMinor(value: string, allowZero = true): number | null {
  const normalized = value.trim();
  if (!/^(?:0|[1-9][0-9]*)(?:[,.][0-9]{1,2})?$/.test(normalized)) return null;
  const [major = "", fraction = ""] = normalized.replace(",", ".").split(".");
  const minor = Number(major) * 100 + Number((fraction + "00").slice(0, 2));
  if (!Number.isSafeInteger(minor) || minor > 9007199254740991 || (!allowZero && minor === 0)) return null;
  return minor;
}

export function parsePercentageBasisPoints(value: string): number | null {
  const normalized = value.trim().replace(",", ".");
  if (!/^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,2})?$/.test(normalized)) return null;
  const [major = "", fraction = ""] = normalized.split(".");
  const basisPoints = Number(major) * 100 + Number((fraction + "00").slice(0, 2));
  return Number.isSafeInteger(basisPoints) && basisPoints >= 1 && basisPoints <= 10000 ? basisPoints : null;
}

export function formatAznMinor(value: number): string {
  if (!Number.isSafeInteger(value) || value < 0) throw new TypeError("invalid_minor_amount");
  const digits = String(value).padStart(3, "0");
  const majorText = new Intl.NumberFormat("az-AZ", { maximumFractionDigits: 0 }).format(Number(digits.slice(0, -2)));
  const fraction = digits.slice(-2);
  const decimal = new Intl.NumberFormat("az-AZ").format(1.1).replace(/[0-9]/g, "");
  const suffix = new Intl.NumberFormat("az-AZ", { style: "currency", currency: "AZN", maximumFractionDigits: 0 })
    .format(0).replace(/0/g, "");
  return `${majorText}${decimal}${fraction}${suffix}`;
}

export function normalizePhoneE164(value: string): string | null {
  const trimmed = value.trim();
  if (!trimmed) return "";
  if (!trimmed.startsWith("+")) return null;
  const normalized = trimmed.replace(/[\s().-]/g, "");
  return /^\+[1-9][0-9]{7,14}$/.test(normalized) ? normalized : null;
}

export function validateReservationDraft(
  draft: ReservationDraft,
  property: ReservationPropertyContext,
): ReservationDraftErrors {
  const errors: ReservationDraftErrors = {};
  const guestName = draft.guest_name.trim();
  if (guestName.length < 1 || guestName.length > 150) errors.guest_name = "Qonağın adını 1–150 simvol arasında yazın.";
  if (draft.guest_phone && normalizePhoneE164(draft.guest_phone) === null) {
    errors.guest_phone = "Telefonu beynəlxalq formatda yazın, məsələn +994501234567.";
  }
  const guestCount = Number(draft.guest_count);
  if (!/^\d+$/.test(draft.guest_count) || !Number.isSafeInteger(guestCount) || guestCount < 1 || guestCount > 1000) {
    errors.guest_count = "Qonaq sayı 1–1000 arasında tam ədəd olmalıdır.";
  } else if (guestCount > property.max_guests && !draft.capacity_override_confirmed) {
    errors.capacity_override_confirmed = "Davam etmək üçün tutumdan artıq qonaq sayını təsdiqləyin.";
  }
  if (!isCalendarDate(draft.check_in)) errors.check_in = "Giriş tarixini seçin.";
  if (!isCalendarDate(draft.check_out)) errors.check_out = "Çıxış tarixini seçin.";
  if (isCalendarDate(draft.check_in) && isCalendarDate(draft.check_out) && draft.check_out <= draft.check_in) {
    errors.check_out = "Çıxış tarixi giriş tarixindən sonra olmalıdır.";
  }
  if (!isLocalTime(draft.check_in_time)) errors.check_in_time = "Giriş saatını yoxlayın.";
  if (!isLocalTime(draft.check_out_time)) errors.check_out_time = "Çıxış saatını yoxlayın.";

  const totalMinor = parseAznMinor(draft.total_azn);
  if (totalMinor === null) errors.total_azn = "Məbləği ən çox 2 onluq rəqəmlə yazın.";
  else if (totalMinor === 0 && !draft.free_stay) errors.free_stay = "Sıfır qiymət üçün ödənişsiz qalmanı təsdiqləyin.";

  if (draft.receipt_azn.trim() !== "" && parseAznMinor(draft.receipt_azn, false) === null) {
    errors.receipt_azn = "Alınan pulu müsbət məbləğ və ən çox 2 onluq rəqəmlə yazın.";
  }
  if (draft.receipt_azn.trim() !== "" && draft.custodian === "realtor" && !isUuid(draft.receipt_contact_id)) {
    errors.receipt_contact_id = "Pulu alan realtoru seçin.";
  }
  if (draft.commission_contact_id) {
    if (!isUuid(draft.commission_contact_id)) errors.commission_contact_id = "Realtoru seçin.";
    const commissionValue = draft.commission_value.trim();
    if (draft.commission_kind === "fixed") {
      if (parseAznMinor(commissionValue, false) === null) errors.commission_value = "Komissiya məbləğini qəpiklə dəqiq yazın.";
    } else if (parsePercentageBasisPoints(commissionValue) === null) {
      errors.commission_value = "Faizi 0,01–100 aralığında yazın.";
    }
  } else if (draft.commission_value.trim()) {
    errors.commission_contact_id = "Komissiya üçün realtor seçin.";
  }
  if (draft.note.length > 2000) errors.note = "Qeyd ən çox 2000 simvol ola bilər.";
  return errors;
}

export function toReservationCreateInput(
  draft: ReservationDraft,
  property: ReservationPropertyContext,
  status: CreateReservationStatus,
  errors = validateReservationDraft(draft, property),
): ReservationCreateInput {
  if (Object.keys(errors).length > 0) throw new TypeError("invalid_reservation_draft");
  const totalMinor = parseAznMinor(draft.total_azn);
  if (totalMinor === null) throw new TypeError("invalid_reservation_total");
  const input: ReservationCreateInput = {
    property_id: property.id,
    guest_name: draft.guest_name.trim(),
    guest_count: Number(draft.guest_count),
    check_in: draft.check_in,
    check_out: draft.check_out,
    check_in_time: draft.check_in_time,
    check_out_time: draft.check_out_time,
    status,
    total_minor: totalMinor,
  };
  const phone = normalizePhoneE164(draft.guest_phone);
  if (phone === null) throw new TypeError("invalid_reservation_phone");
  if (phone) input.guest_phone = phone;
  const note = draft.note.trim();
  if (note) input.note = note;
  if (totalMinor === 0) input.free_stay = true;
  if (Number(draft.guest_count) > property.max_guests) input.capacity_override_confirmed = true;
  if (status === "hold") input.hold_duration = draft.hold_duration;

  const receiptAmount = draft.receipt_azn.trim() === "" ? null : parseAznMinor(draft.receipt_azn, false);
  if (receiptAmount !== null) {
    input.initial_receipt = {
      amount_minor: receiptAmount,
      kind: draft.receipt_kind,
      custodian: draft.custodian,
      ...(draft.custodian === "realtor" ? { contact_id: draft.receipt_contact_id } : {}),
    };
  }
  if (draft.commission_contact_id) {
    input.commission = draft.commission_kind === "fixed"
      ? { contact_id: draft.commission_contact_id, kind: "fixed", fixed_minor: parseAznMinor(draft.commission_value, false)! }
      : { contact_id: draft.commission_contact_id, kind: "percentage", percentage_basis_points: parsePercentageBasisPoints(draft.commission_value)! };
  }
  return input;
}

export function parseReservationEnvelope(value: unknown): ReservationEnvelope {
  if (!isRecord(value) || !hasOnlyKeys(value, ["data", "meta"]) || !isRecord(value.data) || !isRecord(value.meta)) {
    throw new TypeError("invalid_reservation_envelope");
  }
  const dto = value.data;
  const dtoKeys = ["id", "property_id", "current_placement_id", "guest_name", "guest_phone", "guest_count",
    "check_in", "check_out", "check_in_time", "check_out_time", "actual_check_in_at", "actual_check_out_at",
    "status", "hold_expires_at", "total_minor", "currency", "note", "commission", "balance", "version",
    "created_at", "updated_at"];
  if (!isUuid(dto.id) || !isUuid(dto.property_id) || !isUuid(dto.current_placement_id)
      || !hasOnlyKeys(dto, dtoKeys)
      || typeof dto.guest_name !== "string" || dto.guest_name.length < 1 || dto.guest_name.length > 150
      || !isCalendarDate(dto.check_in) || !isCalendarDate(dto.check_out) || dto.check_out <= dto.check_in
      || !isReservationStatus(dto.status) || dto.currency !== "AZN"
      || !isInteger(dto.total_minor) || dto.total_minor < 0
      || !isInteger(dto.version) || dto.version < 1
      || !isDateTime(dto.created_at) || !isDateTime(dto.updated_at)
      || !isRecord(dto.balance) || !isBalance(dto.balance)
      || typeof value.meta.request_id !== "string" || value.meta.request_id.length < 1) {
    throw new TypeError("invalid_reservation_envelope");
  }
  if (dto.guest_phone !== undefined && dto.guest_phone !== null
      && (typeof dto.guest_phone !== "string" || !/^\+[1-9][0-9]{7,14}$/.test(dto.guest_phone))) {
    throw new TypeError("invalid_reservation_envelope");
  }
  if (dto.guest_count !== undefined && (!isInteger(dto.guest_count) || dto.guest_count < 1 || dto.guest_count > 1000)) {
    throw new TypeError("invalid_reservation_envelope");
  }
  if ((dto.check_in_time !== undefined && !isLocalTime(dto.check_in_time))
      || (dto.check_out_time !== undefined && !isLocalTime(dto.check_out_time))) {
    throw new TypeError("invalid_reservation_envelope");
  }
  if (dto.hold_expires_at !== undefined && dto.hold_expires_at !== null && !isDateTime(dto.hold_expires_at)) {
    throw new TypeError("invalid_reservation_envelope");
  }
  if (dto.note !== undefined && (typeof dto.note !== "string" || dto.note.length > 2000)) {
    throw new TypeError("invalid_reservation_envelope");
  }
  if (dto.commission !== undefined && dto.commission !== null && !isCommission(dto.commission)) {
    throw new TypeError("invalid_reservation_envelope");
  }
  if (!hasOnlyKeys(value.meta, ["request_id"])) throw new TypeError("invalid_reservation_envelope");
  return value as ReservationEnvelope;
}

export function newReservationIdempotencyKey(): string {
  return `reservation-${crypto.randomUUID()}`;
}

export function getReservationIdempotencyState(
  input: ReservationCreateInput,
  previous: ReservationIdempotencyState | null,
  createKey: () => string = newReservationIdempotencyKey,
): ReservationIdempotencyState {
  const fingerprint = JSON.stringify(input);
  return previous?.fingerprint === fingerprint
    ? previous
    : { fingerprint, key: createKey() };
}

export function mapReservationApiError(error: unknown): { message: string; fieldErrors: ReservationDraftErrors } {
  const envelope = isRecord(error) && isRecord(error.error) ? error.error : null;
  if (!envelope || typeof envelope.code !== "string") {
    return { message: "Sorğunun cavabı alınmadı. Daxil etdiyiniz məlumatlar bu formda saxlanıb; interneti yoxlayıb eyni məlumatla yenidən cəhd edin.", fieldErrors: {} };
  }
  if (envelope.code === "VALIDATION_ERROR") {
    const fieldErrors: ReservationDraftErrors = {};
    if (Array.isArray(envelope.field_errors)) {
      for (const item of envelope.field_errors) {
        if (!isRecord(item) || typeof item.field !== "string") continue;
        const mapped = mapReservationFieldError(item.field);
        if (mapped) fieldErrors[mapped.key] = mapped.message;
      }
    }
    return {
      message: Object.keys(fieldErrors).length ? "Server bəzi məlumatları qəbul etmədi. Sahələri yoxlayın." : "Məlumatları yoxlayıb yenidən cəhd edin.",
      fieldErrors,
    };
  }
  const messages: Record<string, string> = {
    DATE_CONFLICT: "Bu tarixlər artıq uyğun deyil. Təqvimi yeniləyin.",
    UNAUTHENTICATED: "Sessiyanız bitib. Yenidən daxil olun.",
    FORBIDDEN: "Bu əməliyyatı yerinə yetirmək üçün icazəniz yoxdur.",
    ENTITLEMENT_REQUIRED: "Davam etmək üçün bu evdə aktiv abunə lazımdır.",
    IDEMPOTENCY_MISMATCH: "Sorğunun məzmunu dəyişib. Məlumatları yoxlayıb yenidən göndərin.",
    RATE_LIMITED: "Bir az gözləyib yenidən cəhd edin.",
    PROVIDER_UNAVAILABLE: "Rezervasiya təsdiqlənmədi. Xidmət hazırda əlçatan deyil.",
  };
  return {
    message: messages[envelope.code] ?? "Rezervasiya təsdiqlənmədi. Məlumatları yoxlayıb yenidən cəhd edin.",
    fieldErrors: {},
  };
}

function isBalance(value: Record<string, unknown>): value is ReservationBalance {
  const keys = ["rent_received_minor", "rent_refunded_minor", "remaining_minor", "overpaid_minor", "deposit_held_minor"];
  return hasOnlyKeys(value, keys) && keys.every((key) => isInteger(value[key]) && (value[key] as number) >= 0);
}

function isCommission(value: unknown): value is CommissionDto {
  if (!isRecord(value) || !isUuid(value.contact_id)) return false;
  if (value.basis_minor !== undefined && (!isInteger(value.basis_minor) || value.basis_minor < 0)) return false;
  if (value.kind === "fixed") {
    return hasOnlyKeys(value, ["contact_id", "kind", "fixed_minor", "basis_minor"])
      && isInteger(value.fixed_minor) && value.fixed_minor > 0;
  }
  if (value.kind === "percentage") {
    return hasOnlyKeys(value, ["contact_id", "kind", "basis_minor", "percentage_basis_points"])
      && isInteger(value.percentage_basis_points)
      && value.percentage_basis_points >= 1 && value.percentage_basis_points <= 10000;
  }
  return false;
}

function isReservationStatus(value: unknown): value is ReservationStatus {
  return value === "hold" || value === "confirmed" || value === "checked_in"
    || value === "completed" || value === "cancelled" || value === "no_show";
}

function isLocalTime(value: unknown): value is string {
  return typeof value === "string" && /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value);
}

function isCalendarDate(value: unknown): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}

function isDateTime(value: unknown): value is string {
  return typeof value === "string"
    && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/i.test(value)
    && Number.isFinite(Date.parse(value));
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

function isInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, allowed: readonly string[]): boolean {
  return Object.keys(value).every((key) => allowed.includes(key));
}

function mapReservationFieldError(field: string): { key: keyof ReservationDraft; message: string } | null {
  const known: Record<string, { key: keyof ReservationDraft; message: string }> = {
    guest_name: { key: "guest_name", message: "Qonağın adını yoxlayın." },
    guest_phone: { key: "guest_phone", message: "Telefonu beynəlxalq formatda yazın." },
    guest_count: { key: "guest_count", message: "Qonaq sayını yoxlayın." },
    check_in: { key: "check_in", message: "Giriş tarixini yoxlayın." },
    check_out: { key: "check_out", message: "Çıxış tarixini yoxlayın." },
    check_in_time: { key: "check_in_time", message: "Giriş saatını yoxlayın." },
    check_out_time: { key: "check_out_time", message: "Çıxış saatını yoxlayın." },
    total_minor: { key: "total_azn", message: "Ümumi qiyməti yoxlayın." },
    free_stay: { key: "free_stay", message: "Ödənişsiz qalma seçimini yoxlayın." },
    capacity_override_confirmed: { key: "capacity_override_confirmed", message: "Tutumdan artıq qonaq sayını təsdiqləyin." },
    hold_duration: { key: "hold_duration", message: "Müvəqqəti saxlama müddətini seçin." },
    initial_receipt: { key: "receipt_azn", message: "Alınan pul məlumatını yoxlayın." },
    "initial_receipt.amount_minor": { key: "receipt_azn", message: "Alınan pul məbləğini yoxlayın." },
    "initial_receipt.contact_id": { key: "receipt_contact_id", message: "Realtoru seçin." },
    commission: { key: "commission_value", message: "Komissiya məlumatını yoxlayın." },
    "commission.contact_id": { key: "commission_contact_id", message: "Realtoru seçin." },
    note: { key: "note", message: "Qeydi yoxlayın." },
  };
  return known[field] ?? null;
}
