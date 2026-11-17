import type { RentEntry } from "./rent-entry-contract.ts";

const refundableSources = new Set(["rent_receipt", "deposit_to_rent", "deposit_receipt"]);

/** The documented money-entry POST acknowledges creation only with HTTP 201. */
export function isRentEntryCreationAcknowledged(status: number): boolean {
  return status === 201;
}

/** Computes per-source refundable room from the append-only history; the server remains authoritative. */
export function refundableMinor(source: RentEntry, entries: RentEntry[]): number {
  if (!refundableSources.has(source.kind)) return 0;
  const adjustments = entries.filter((entry) => entry.original_id === source.id);
  const reversals = entries.filter((entry) => entry.kind === "reversal");
  const relevantKinds = source.kind === "deposit_receipt"
    ? new Set(["deposit_return", "deposit_to_rent", "deposit_to_damage"])
    : new Set(["rent_refund"]);
  const adjustmentsById = new Map(adjustments.filter((entry) => relevantKinds.has(entry.kind)).map((entry) => [entry.id, entry]));
  let used = 0;
  for (const entry of adjustments) if (relevantKinds.has(entry.kind)) used += entry.amount_minor;
  for (const reversal of reversals) {
    if (reversal.original_id === source.id) used += reversal.amount_minor;
    if (adjustmentsById.has(reversal.original_id ?? "")) used -= reversal.amount_minor;
  }
  return Math.max(0, source.amount_minor - Math.max(0, used));
}

export function depositTotals(entries: RentEntry[]): { received_minor: number; returned_minor: number } {
  const receipts = new Set(entries.filter((entry) => entry.kind === "deposit_receipt").map((entry) => entry.id));
  const returns = new Set(entries.filter((entry) => entry.kind === "deposit_return").map((entry) => entry.id));
  const receiptReversals = entries.filter((entry) => entry.kind === "reversal" && receipts.has(entry.original_id ?? ""))
    .reduce((total, entry) => total + entry.amount_minor, 0);
  const returnReversals = entries.filter((entry) => entry.kind === "reversal" && returns.has(entry.original_id ?? ""))
    .reduce((total, entry) => total + entry.amount_minor, 0);
  return {
    received_minor: Math.max(0, entries.filter((entry) => entry.kind === "deposit_receipt").reduce((total, entry) => total + entry.amount_minor, 0) - receiptReversals),
    returned_minor: Math.max(0, entries.filter((entry) => entry.kind === "deposit_return").reduce((total, entry) => total + entry.amount_minor, 0) - returnReversals),
  };
}

export function bakuToday(now = new Date()): string {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Baku", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(now);
  const part = (type: string) => parts.find((item) => item.type === type)?.value ?? "";
  return `${part("year")}-${part("month")}-${part("day")}`;
}

/** Converts a Baku calendar date to noon in that zone without assuming its UTC offset. */
export function bakuDateToIso(date: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || new Date(`${date}T00:00:00Z`).toISOString().slice(0, 10) !== date) {
    throw new TypeError("invalid_baku_date");
  }
  const target = Date.parse(`${date}T12:00:00Z`);
  let guess = target;
  const formatter = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Baku", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23" });
  for (let i = 0; i < 3; i++) {
    const fields = Object.fromEntries(formatter.formatToParts(new Date(guess)).map((part) => [part.type, part.value]));
    const represented = Date.UTC(Number(fields.year), Number(fields.month) - 1, Number(fields.day), Number(fields.hour), Number(fields.minute), Number(fields.second));
    guess += target - represented;
  }
  return new Date(guess).toISOString();
}
