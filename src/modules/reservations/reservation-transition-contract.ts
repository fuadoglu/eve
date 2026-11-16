const MAX_SAFE_MINOR = 9007199254740991;

export type TransitionFinancialDecision =
  | { mode: "keep_as_is" }
  | {
      mode: "adjust";
      rent_refunds?: Array<{ original_id: string; amount_minor: number }>;
      deposit_returns?: Array<{ original_id: string; amount_minor: number }>;
      commission_keep_minor?: number;
    };

export type ReservationLifecycleTransitionInput = {
  expected_version: number;
  action: "cancel" | "no_show" | "check_in" | "check_out";
  reason?: string;
  financial_decision?: TransitionFinancialDecision;
};

/** Parse the lifecycle-action subset of ReservationTransition. Server/DB code
 * must still verify the current state, entitlement, capability, money history,
 * schedule, idempotency and all transactional effects.
 */
export function parseReservationLifecycleTransition(value: unknown): ReservationLifecycleTransitionInput {
  if (!isRecord(value) || !hasOnlyKeys(value, ["expected_version", "action", "reason", "financial_decision"])
      || !isPositiveInteger(value.expected_version)
      || !isLifecycleAction(value.action)
      || ("reason" in value && (typeof value.reason !== "string" || [...value.reason].length > 2000))) {
    throw new TypeError("invalid_reservation_transition_input");
  }
  if ("financial_decision" in value) {
    if (value.action !== "cancel" && value.action !== "no_show") {
      throw new TypeError("financial_decision_not_allowed_for_action");
    }
    if (!isTransitionFinancialDecision(value.financial_decision)) {
      throw new TypeError("invalid_transition_financial_decision");
    }
  }
  return value as ReservationLifecycleTransitionInput;
}

function isTransitionFinancialDecision(value: unknown): value is TransitionFinancialDecision {
  if (!isRecord(value) || !hasOnlyKeys(value, ["mode", "rent_refunds", "deposit_returns", "commission_keep_minor"])) return false;
  if (value.mode === "keep_as_is") return Object.keys(value).length === 1;
  if (value.mode !== "adjust" || Object.keys(value).length < 2) return false;
  if ("rent_refunds" in value && !isReceiptAdjustments(value.rent_refunds)) return false;
  if ("deposit_returns" in value && !isReceiptAdjustments(value.deposit_returns)) return false;
  if ("commission_keep_minor" in value && !isNonnegativeMinor(value.commission_keep_minor)) return false;
  return true;
}

function isReceiptAdjustments(value: unknown): value is Array<{ original_id: string; amount_minor: number }> {
  return Array.isArray(value) && value.length >= 1 && value.length <= 100 && value.every((item) =>
    isRecord(item) && hasOnlyKeys(item, ["original_id", "amount_minor"])
      && isUuid(item.original_id) && isPositiveMinor(item.amount_minor));
}

function isLifecycleAction(value: unknown): value is ReservationLifecycleTransitionInput["action"] {
  return value === "cancel" || value === "no_show" || value === "check_in" || value === "check_out";
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

function isPositiveMinor(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 1 && value <= MAX_SAFE_MINOR;
}

function isNonnegativeMinor(value: unknown): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 && value <= MAX_SAFE_MINOR;
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}
