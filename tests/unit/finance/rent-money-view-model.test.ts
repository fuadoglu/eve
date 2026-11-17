import test from "node:test";
import assert from "node:assert/strict";
import type { RentEntry } from "../../../src/modules/finance/rent-entry-contract.ts";
import { bakuDateToIso, bakuToday, depositTotals, isRentEntryCreationAcknowledged, refundableMinor } from "../../../src/modules/finance/rent-money-view-model.ts";

const entry = (id: string, kind: RentEntry["kind"], amount_minor: number, original_id: string | null = null): RentEntry => ({
  id, reservation_id: "00000000-0000-4000-8000-000000000001", placement_id: "00000000-0000-4000-8000-000000000002",
  property_id: "00000000-0000-4000-8000-000000000003", kind, amount_minor, currency: "AZN", custodian: "owner",
  ...(original_id ? { original_id } : {}), occurred_at: "2026-11-17T08:00:00.000Z", version: 1,
  created_at: "2026-11-17T08:00:00.000Z", updated_at: "2026-11-17T08:00:00.000Z",
});

test("money-entry creation is acknowledged only by the documented HTTP 201 response", () => {
  assert.equal(isRentEntryCreationAcknowledged(201), true);
  for (const status of [200, 202, 204, 400, 500]) assert.equal(isRentEntryCreationAcknowledged(status), false);
});

test("available rent refund includes refunds and subtracts a reversal of a refund", () => {
  const source = entry("source", "rent_receipt", 30_000);
  const refund = entry("refund", "rent_refund", 12_000, "source");
  const reversal = entry("reversal", "reversal", 2_000, "refund");
  assert.equal(refundableMinor(source, [source, refund, reversal]), 20_000);
});

test("available deposit return counts all allocated/returned amounts and their reversals", () => {
  const source = entry("deposit", "deposit_receipt", 10_000);
  const returned = entry("return", "deposit_return", 3_000, "deposit");
  const damage = entry("damage", "deposit_to_damage", 4_000, "deposit");
  const reversal = entry("reversal", "reversal", 1_000, "damage");
  assert.equal(refundableMinor(source, [source, returned, damage, reversal]), 4_000);
});

test("refund room is zero for non-source entries and never negative", () => {
  const source = entry("source", "rent_receipt", 100);
  const refund = entry("refund", "rent_refund", 100, "source");
  assert.equal(refundableMinor(source, [source, refund]), 0);
  assert.equal(refundableMinor(refund, [source, refund]), 0);
});

test("deposit summary subtracts reversed receipts and returns while held balance stays server-owned", () => {
  const receipt = entry("deposit", "deposit_receipt", 10_000);
  const returned = entry("return", "deposit_return", 2_000, "deposit");
  const receiptReversal = entry("reverse-receipt", "reversal", 1_000, "deposit");
  const returnReversal = entry("reverse-return", "reversal", 500, "return");
  assert.deepEqual(depositTotals([receipt, returned, receiptReversal, returnReversal]), { received_minor: 9_000, returned_minor: 1_500 });
});

test("Baku date helpers use Asia/Baku civil date and noon instant", () => {
  assert.equal(bakuToday(new Date("2026-11-16T21:00:00.000Z")), "2026-11-17");
  assert.equal(new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Baku", hour: "2-digit", hourCycle: "h23" }).format(new Date(bakuDateToIso("2026-11-17"))), "12");
  assert.throws(() => bakuDateToIso("2026-02-31"), /invalid_baku_date/);
});
