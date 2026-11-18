export type ExpenseAllocation = { property_id: string; amount_minor: number };
export type ExpenseProposalInput = {
  category: "utilities" | "building_service" | "cleaning" | "repair" | "purchase" | "consumables" | "other";
  amount_minor: number;
  allocations: ExpenseAllocation[];
  occurred_on: string;
  due_on?: string;
  contact_id?: string;
  task_id?: string;
  note?: string;
  receipt_media_ids?: [];
  mark_paid?: false;
};

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const categories = new Set(["utilities", "building_service", "cleaning", "repair", "purchase", "consumables", "other"]);
const date = /^\d{4}-\d{2}-\d{2}$/;
const own = (value: Record<string, unknown>, key: string): boolean => Object.prototype.hasOwnProperty.call(value, key);
const record = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);
const cents = (value: unknown): value is number => Number.isSafeInteger(value) && (value as number) > 0;
const isoDate = (value: unknown): value is string => typeof value === "string" && date.test(value)
  && !Number.isNaN(Date.parse(`${value}T00:00:00Z`))
  && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;

export function parseExpenseProposalInput(value: unknown): ExpenseProposalInput | null {
  if (!record(value) || Object.keys(value).some((key) => ![
    "category", "amount_minor", "allocations", "occurred_on", "due_on", "contact_id", "task_id",
    "note", "receipt_media_ids", "mark_paid",
  ].includes(key))) return null;
  if (typeof value.category !== "string" || !categories.has(value.category) || !cents(value.amount_minor)
    || !isoDate(value.occurred_on) || !Array.isArray(value.allocations)
    || value.allocations.length < 1 || value.allocations.length > 100) return null;
  if (own(value, "due_on") && !isoDate(value.due_on)) return null;
  if (own(value, "contact_id") && (typeof value.contact_id !== "string" || !uuid.test(value.contact_id))) return null;
  if (own(value, "task_id") && (typeof value.task_id !== "string" || !uuid.test(value.task_id))) return null;
  if (own(value, "note") && (typeof value.note !== "string" || value.note.length > 2000)) return null;
  // Proposal creation cannot record payment or bind unvalidated media.
  if (value.mark_paid === true || (own(value, "mark_paid") && value.mark_paid !== false)
    || (own(value, "receipt_media_ids") && (!Array.isArray(value.receipt_media_ids) || value.receipt_media_ids.length !== 0))) return null;
  let sum = 0;
  const properties = new Set<string>();
  for (const allocation of value.allocations) {
    if (!record(allocation) || Object.keys(allocation).some((key) => !["property_id", "amount_minor"].includes(key))
      || typeof allocation.property_id !== "string" || !uuid.test(allocation.property_id)
      || !cents(allocation.amount_minor) || properties.has(allocation.property_id.toLowerCase())) return null;
    sum += allocation.amount_minor;
    if (!Number.isSafeInteger(sum)) return null;
    properties.add(allocation.property_id.toLowerCase());
  }
  if (sum !== value.amount_minor) return null;
  return value as ExpenseProposalInput;
}

export function parseExpenseProposal(value: unknown): Record<string, unknown> | null {
  if (!record(value) || typeof value.id !== "string" || !uuid.test(value.id)
    || Object.keys(value).some((key) => !["id", "category", "amount_minor", "currency", "allocations",
      "approval", "payment_status", "paid_minor", "occurred_on", "due_on", "contact_id", "task_id",
      "note", "receipt_media_ids", "version", "created_at", "updated_at"].includes(key))
    || !["proposed", "approved"].includes(String(value.approval))
    || value.payment_status !== "unpaid" || value.paid_minor !== 0
    || value.currency !== "AZN" || !Number.isSafeInteger(value.version) || (value.version as number) < 1
    || typeof value.created_at !== "string" || Number.isNaN(Date.parse(value.created_at))
    || typeof value.updated_at !== "string" || Number.isNaN(Date.parse(value.updated_at))
    || !Array.isArray(value.receipt_media_ids) || value.receipt_media_ids.length !== 0
    || parseExpenseProposalInput({
      category: value.category, amount_minor: value.amount_minor, allocations: value.allocations,
      occurred_on: value.occurred_on, ...((value.due_on === null || value.due_on === undefined) ? {} : { due_on: value.due_on }),
      ...((value.contact_id === null || value.contact_id === undefined) ? {} : { contact_id: value.contact_id }),
      ...((value.task_id === null || value.task_id === undefined) ? {} : { task_id: value.task_id }),
      ...((value.note === null || value.note === undefined) ? {} : { note: value.note }),
    }) === null) return null;
  return value;
}
