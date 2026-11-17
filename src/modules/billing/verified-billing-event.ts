export type NormalizedVerifiedBillingEvent = {
  order_id: string;
  event_key: string;
  provider_transaction_id: string;
  amount_minor: number;
  currency: "AZN";
};

export type VerifiedBillingEventResult = {
  event_id: string;
  order_id: string;
  verification_state: "applied" | "verified" | "rejected";
  replay: boolean;
  entitlement_applied: boolean;
  manual_review_required: boolean;
  entitlement_replay?: boolean;
  rejection_code?: string;
};

/** Parse Eve's normalized, already-verified event. Provider wire fields are intentionally absent. */
export function parseNormalizedVerifiedBillingEvent(value: unknown): NormalizedVerifiedBillingEvent | null {
  if (!isRecord(value) || !hasOnlyKeys(value, ["order_id", "event_key", "provider_transaction_id", "amount_minor", "currency"])) return null;
  if (!isUuid(value.order_id) || !isOpaqueIdentifier(value.event_key, 255)
      || !isOpaqueIdentifier(value.provider_transaction_id, 160)
      || !isPositiveSafeInteger(value.amount_minor) || value.currency !== "AZN") return null;
  return {
    order_id: value.order_id,
    event_key: value.event_key,
    provider_transaction_id: value.provider_transaction_id,
    amount_minor: value.amount_minor,
    currency: "AZN",
  };
}

export function parseVerifiedBillingEventResult(value: unknown): VerifiedBillingEventResult | null {
  if (!isRecord(value) || !isUuid(value.event_id) || !isUuid(value.order_id)
      || !["applied", "verified", "rejected"].includes(String(value.verification_state))
      || typeof value.replay !== "boolean" || typeof value.entitlement_applied !== "boolean"
      || typeof value.manual_review_required !== "boolean"
      || (value.entitlement_replay !== undefined && typeof value.entitlement_replay !== "boolean")
      || (value.rejection_code !== undefined && typeof value.rejection_code !== "string")) return null;
  if (value.entitlement_applied && value.verification_state !== "applied") return null;
  if (value.manual_review_required && (value.verification_state !== "verified" || value.entitlement_applied)) return null;
  return value as unknown as VerifiedBillingEventResult;
}

function isOpaqueIdentifier(value: unknown, maxLength: number): value is string {
  return typeof value === "string" && value.length > 0 && value.length <= maxLength
    && value.trim() === value && !/[\u0000-\u001f\u007f]/.test(value);
}
function isPositiveSafeInteger(value: unknown): value is number { return typeof value === "number" && Number.isSafeInteger(value) && value > 0; }
function isUuid(value: unknown): value is string { return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value); }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
function hasOnlyKeys(value: Record<string, unknown>, allowed: readonly string[]): boolean { return Object.keys(value).every((key) => allowed.includes(key)); }
