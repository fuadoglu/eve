export const RENT_ENTRY_KINDS = [
  "rent_receipt", "rent_refund", "deposit_receipt", "deposit_return",
  "deposit_to_rent", "deposit_to_damage", "reversal",
] as const;

export type RentEntryKind = typeof RENT_ENTRY_KINDS[number];
export type RentCustodian = "owner" | "manager" | "realtor";

export type RentEntryCreate = {
  kind: RentEntryKind;
  amount_minor: number;
  custodian: RentCustodian;
  contact_id?: string;
  original_id?: string;
  occurred_at?: string;
  note?: string;
};

export type RentEntry = {
  id: string;
  reservation_id: string;
  placement_id: string;
  property_id: string;
  kind: RentEntryKind;
  amount_minor: number;
  currency: "AZN";
  custodian: RentCustodian;
  contact_id?: string | null;
  original_id?: string | null;
  occurred_at: string;
  note?: string;
  actor_display_name?: string;
  version: number;
  created_at: string;
  updated_at: string;
};

export type RentEntryPage = { items: RentEntry[]; next_cursor: string | null };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DATE_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/;

export function parseRentEntryCreate(value: unknown): RentEntryCreate | null {
  if (!isRecord(value) || Object.keys(value).some((key) => ![
    "kind", "amount_minor", "custodian", "contact_id", "original_id", "occurred_at", "note",
  ].includes(key))) return null;
  if (typeof value.kind !== "string" || !RENT_ENTRY_KINDS.includes(value.kind as RentEntryKind)
      || !Number.isSafeInteger(value.amount_minor) || Number(value.amount_minor) < 1
      || !["owner", "manager", "realtor"].includes(String(value.custodian))) return null;
  if ((value.kind === "rent_refund" || value.kind === "deposit_return" || value.kind === "deposit_to_rent"
      || value.kind === "deposit_to_damage" || value.kind === "reversal") && !isUuid(value.original_id)) return null;
  if ((value.kind === "deposit_to_rent" || value.kind === "deposit_to_damage" || value.kind === "reversal")
      && (typeof value.note !== "string" || value.note.trim().length === 0)) return null;
  if (value.custodian === "realtor" && !isUuid(value.contact_id)) return null;
  if (value.contact_id !== undefined && !isUuid(value.contact_id)) return null;
  if (value.original_id !== undefined && !isUuid(value.original_id)) return null;
  if (value.occurred_at !== undefined && (typeof value.occurred_at !== "string"
      || !DATE_TIME.test(value.occurred_at) || !Number.isFinite(Date.parse(value.occurred_at)))) return null;
  if (value.note !== undefined && (typeof value.note !== "string" || value.note.length > 1000)) return null;
  return value as RentEntryCreate;
}

export function parseRentEntry(value: unknown): RentEntry | null {
  if (!isRecord(value) || !isUuid(value.id) || !isUuid(value.reservation_id)
      || !isUuid(value.placement_id) || !isUuid(value.property_id)
      || Object.keys(value).some((key) => ![
        "id", "reservation_id", "placement_id", "property_id", "kind", "amount_minor", "currency", "custodian",
        "contact_id", "original_id", "occurred_at", "note", "actor_display_name", "version", "created_at", "updated_at",
      ].includes(key))
      || typeof value.kind !== "string" || !RENT_ENTRY_KINDS.includes(value.kind as RentEntryKind)
      || !Number.isSafeInteger(value.amount_minor) || Number(value.amount_minor) < 1
      || value.currency !== "AZN" || !["owner", "manager", "realtor"].includes(String(value.custodian))
      || !isDateTime(value.occurred_at) || value.version !== 1
      || !isDateTime(value.created_at) || value.updated_at !== value.created_at
      || (value.contact_id !== undefined && value.contact_id !== null && !isUuid(value.contact_id))
      || (value.original_id !== undefined && value.original_id !== null && !isUuid(value.original_id))
      || (value.note !== undefined && (typeof value.note !== "string" || value.note.length > 1000))
      || (value.actor_display_name !== undefined && (typeof value.actor_display_name !== "string" || value.actor_display_name.length > 100))) return null;
  return {
    id: value.id,
    reservation_id: value.reservation_id,
    placement_id: value.placement_id,
    property_id: value.property_id,
    kind: value.kind as RentEntryKind,
    amount_minor: value.amount_minor as number,
    currency: "AZN",
    custodian: value.custodian as RentCustodian,
    ...(value.contact_id !== undefined ? { contact_id: value.contact_id as string | null } : {}),
    ...(value.original_id !== undefined ? { original_id: value.original_id as string | null } : {}),
    occurred_at: value.occurred_at,
    ...(value.note !== undefined ? { note: value.note as string } : {}),
    ...(value.actor_display_name !== undefined ? { actor_display_name: value.actor_display_name as string } : {}),
    version: 1,
    created_at: value.created_at,
    updated_at: value.updated_at,
  };
}

export function isUuid(value: unknown): value is string { return typeof value === "string" && UUID.test(value); }
export function isDateTime(value: unknown): value is string { return typeof value === "string" && Number.isFinite(Date.parse(value)); }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
