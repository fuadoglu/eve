export const SETTLEMENT_KINDS = ["realtor_to_owner", "owner_to_realtor", "commission_offset"] as const;
export type SettlementKind = typeof SETTLEMENT_KINDS[number];

export type SettlementInput = {
  expected_version: number;
  contact_id: string;
  kind: SettlementKind;
  amount_minor: number;
  occurred_at?: string;
};
export type RealtorBalance = {
  version: number;
  contact_id: string;
  collected_minor: number;
  transferred_minor: number;
  commission_minor: number;
  commission_paid_minor: number;
  owner_due_minor: number;
  realtor_due_minor: number;
};
export type RealtorSettlement = {
  id: string;
  reservation_id: string;
  contact_id: string;
  kind: SettlementKind;
  amount_minor: number;
  occurred_at: string;
  balance_version: number;
  created_at: string;
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DATE_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;
function record(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
function safeMinor(value: unknown): value is number { return typeof value === "number" && Number.isSafeInteger(value) && value >= 0; }
function isUuid(value: unknown): value is string { return typeof value === "string" && UUID.test(value); }
function isDateTime(value: unknown): value is string { return typeof value === "string" && DATE_TIME.test(value) && Number.isFinite(Date.parse(value)); }

export function parseSettlementInput(value: unknown): SettlementInput | null {
  if (!record(value) || Object.keys(value).some((key) => !["expected_version", "contact_id", "kind", "amount_minor", "occurred_at"].includes(key))
      || typeof value.expected_version !== "number" || !Number.isSafeInteger(value.expected_version) || value.expected_version < 1
      || !isUuid(value.contact_id) || typeof value.kind !== "string" || !SETTLEMENT_KINDS.includes(value.kind as SettlementKind)
      || typeof value.amount_minor !== "number" || !Number.isSafeInteger(value.amount_minor) || value.amount_minor < 1 || value.amount_minor > 9007199254740991
      || (value.occurred_at !== undefined && !isDateTime(value.occurred_at))) return null;
  return value as SettlementInput;
}

export function parseRealtorBalance(value: unknown): RealtorBalance | null {
  if (!record(value) || Object.keys(value).some((key) => ![
    "version", "contact_id", "collected_minor", "transferred_minor", "commission_minor", "commission_paid_minor", "owner_due_minor", "realtor_due_minor",
  ].includes(key)) || typeof value.version !== "number" || !Number.isSafeInteger(value.version) || value.version < 1 || !isUuid(value.contact_id)
      || ![value.collected_minor, value.transferred_minor, value.commission_minor, value.commission_paid_minor,
        value.owner_due_minor, value.realtor_due_minor].every(safeMinor)
      || (Number(value.owner_due_minor) > 0 && Number(value.realtor_due_minor) > 0)) return null;
  return value as RealtorBalance;
}

export function parseRealtorSettlement(value: unknown): RealtorSettlement | null {
  if (!record(value) || Object.keys(value).some((key) => ![
    "id", "reservation_id", "contact_id", "kind", "amount_minor", "occurred_at", "balance_version", "created_at",
  ].includes(key)) || !isUuid(value.id) || !isUuid(value.reservation_id) || !isUuid(value.contact_id)
      || typeof value.kind !== "string" || !SETTLEMENT_KINDS.includes(value.kind as SettlementKind)
      || typeof value.amount_minor !== "number" || !Number.isSafeInteger(value.amount_minor) || value.amount_minor < 1
      || typeof value.balance_version !== "number" || !Number.isSafeInteger(value.balance_version) || value.balance_version < 1
      || !isDateTime(value.occurred_at) || !isDateTime(value.created_at)) return null;
  return value as RealtorSettlement;
}
