import assert from "node:assert/strict";
import test from "node:test";
import { handleRentEntryGet, handleRentEntryPost } from "../../../src/modules/finance/rent-entry-handlers.ts";
import { parseRentEntry, parseRentEntryCreate } from "../../../src/modules/finance/rent-entry-contract.ts";

const appBaseUrl = process.env.APP_BASE_URL;
process.env.APP_BASE_URL = "https://eve.test";
test.after(() => { if (appBaseUrl === undefined) delete process.env.APP_BASE_URL; else process.env.APP_BASE_URL = appBaseUrl; });

const reservationId = "f4000000-0000-4000-8000-000000000001";
const entry = {
  id: "f4100000-0000-4000-8000-000000000001", reservation_id: reservationId,
  placement_id: "f4200000-0000-4000-8000-000000000001", property_id: "f4300000-0000-4000-8000-000000000001",
  kind: "rent_receipt", amount_minor: 10000, currency: "AZN", custodian: "owner", occurred_at: "2027-01-01T10:00:00.000Z",
  version: 1, created_at: "2027-01-01T10:00:00.000Z", updated_at: "2027-01-01T10:00:00.000Z",
};
const input = { kind: "rent_receipt", amount_minor: 10000, custodian: "owner" };

function postRequest(headers: Record<string, string> = {}, body: unknown = input): Request {
  return new Request(`https://eve.test/api/v1/reservations/${reservationId}/money`, {
    method: "POST", headers: { Host: "eve.test", Origin: "https://eve.test", "Content-Type": "application/json", "Idempotency-Key": "rent-entry-test-key-1", ...headers }, body: JSON.stringify(body),
  });
}

test("create contract keeps minor amounts safe and requires adjustment sources/reasons", () => {
  assert.deepEqual(parseRentEntryCreate(input), input);
  assert.equal(parseRentEntryCreate({ ...input, amount_minor: 1.2 }), null);
  assert.equal(parseRentEntryCreate({ ...input, amount_minor: Number.MAX_SAFE_INTEGER + 1 }), null);
  assert.equal(parseRentEntryCreate({ ...input, unexpected: true }), null);
  assert.equal(parseRentEntryCreate({ kind: "rent_refund", amount_minor: 1, custodian: "owner" }), null);
  assert.equal(parseRentEntryCreate({ kind: "deposit_to_damage", amount_minor: 1, custodian: "owner", original_id: entry.id }), null);
  assert.notEqual(parseRentEntryCreate({ kind: "deposit_to_damage", amount_minor: 1, custodian: "owner", original_id: entry.id, note: "Zədə üzrə razılaşma" }), null);
  assert.equal(parseRentEntryCreate({ kind: "rent_receipt", amount_minor: 100, custodian: "realtor" }), null);
});

test("DTO rejects mutable timestamps, invalid identity and non-AZN currency", () => {
  assert.notEqual(parseRentEntry(entry), null);
  assert.equal(parseRentEntry({ ...entry, updated_at: "2027-01-02T10:00:00.000Z" }), null);
  assert.equal(parseRentEntry({ ...entry, currency: "USD" }), null);
  assert.equal(parseRentEntry({ ...entry, version: 2 }), null);
  assert.equal(parseRentEntry({ ...entry, operation_key: "secret-hash" }), null);
  assert.equal(parseRentEntry({ ...entry, note: "x".repeat(1001) }), null);
});

test("POST validates origin/key/body before write and returns private no-store DTO on ack", async () => {
  let calls = 0;
  const create = async () => { calls++; return entry; };
  assert.equal((await handleRentEntryPost(postRequest({ Origin: "https://attacker.test" }), reservationId, create)).status, 403);
  assert.equal((await handleRentEntryPost(postRequest({ "Idempotency-Key": "short" }), reservationId, create)).status, 400);
  assert.equal((await handleRentEntryPost(postRequest({}, { ...input, amount_minor: 0 }), reservationId, create)).status, 422);
  assert.equal(calls, 0);
  const response = await handleRentEntryPost(postRequest(), reservationId, create);
  assert.equal(response.status, 201);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
  assert.deepEqual((await response.json()).data, entry);
  assert.equal(calls, 1);
});

test("GET bounds pagination and validates the acknowledged safe DTO page", async () => {
  let calls = 0;
  const list = async (_id: string, cursor: string | null, limit: number) => { calls++; assert.equal(cursor, null); assert.equal(limit, 30); return { items: [entry], next_cursor: null }; };
  const request = new Request(`https://eve.test/api/v1/reservations/${reservationId}/money`, { headers: { Host: "eve.test", Origin: "https://eve.test" } });
  const response = await handleRentEntryGet(request, reservationId, list);
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).data.items, [entry]);
  const bad = new Request(`https://eve.test/api/v1/reservations/${reservationId}/money?limit=101` , { headers: { Host: "eve.test", Origin: "https://eve.test" } });
  assert.equal((await handleRentEntryGet(bad, reservationId, list)).status, 400);
  assert.equal(calls, 1);
});
