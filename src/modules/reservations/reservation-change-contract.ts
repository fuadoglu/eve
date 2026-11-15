const MAX_SAFE_MINOR = 9007199254740991;

export type ReservationDatePricePatch = {
  expected_version: number;
  check_in?: string;
  check_out?: string;
  total_minor?: number;
  free_stay?: boolean;
};

export type ReservationMoveInput = {
  expected_version: number;
  to_property_id: string;
  new_total_minor: number;
  free_stay?: boolean;
  reason?: string;
};

/** Parse the date/price subset of ReservationPatch. This is client input validation;
 * authorization, overlap, version and atomicity remain server/database duties.
 */
export function parseReservationDatePricePatch(value: unknown): ReservationDatePricePatch {
  const allowed = ["expected_version", "check_in", "check_out", "total_minor", "free_stay"];
  if (!isRecord(value) || !hasOnlyKeys(value, allowed)
      || !isPositiveInteger(value.expected_version)
      || !["check_in", "check_out", "total_minor", "free_stay"].some((key) => key in value)) {
    throw new TypeError("invalid_reservation_date_price_patch");
  }
  if (("check_in" in value && !isCalendarDate(value.check_in))
      || ("check_out" in value && !isCalendarDate(value.check_out))
      || ("total_minor" in value && !isMinorAmount(value.total_minor))
      || ("free_stay" in value && typeof value.free_stay !== "boolean")) {
    throw new TypeError("invalid_reservation_date_price_patch");
  }
  if (value.total_minor === 0 && value.free_stay !== true) {
    throw new TypeError("zero_price_requires_free_stay_confirmation");
  }
  if (typeof value.check_in === "string" && typeof value.check_out === "string"
      && value.check_out <= value.check_in) {
    throw new TypeError("invalid_reservation_interval");
  }
  return value as ReservationDatePricePatch;
}

/** Parse ReservationMoveInput. Same-owner and property capability checks are server-only. */
export function parseReservationMoveInput(value: unknown): ReservationMoveInput {
  const allowed = ["expected_version", "to_property_id", "new_total_minor", "free_stay", "reason"];
  if (!isRecord(value) || !hasOnlyKeys(value, allowed)
      || !isPositiveInteger(value.expected_version)
      || !isUuid(value.to_property_id)
      || !isMinorAmount(value.new_total_minor)
      || ("free_stay" in value && typeof value.free_stay !== "boolean")
      || ("reason" in value && (typeof value.reason !== "string" || value.reason.length > 2000))) {
    throw new TypeError("invalid_reservation_move_input");
  }
  if (value.new_total_minor === 0 && value.free_stay !== true) {
    throw new TypeError("zero_price_requires_free_stay_confirmation");
  }
  return value as ReservationMoveInput;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function hasOnlyKeys(value: Record<string, unknown>, allowed: readonly string[]): boolean {
  return Object.keys(value).every((key) => allowed.includes(key));
}

function isPositiveInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 1;
}

function isMinorAmount(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 && value <= MAX_SAFE_MINOR;
}

function isCalendarDate(value: unknown): value is string {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return Number.isFinite(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}
