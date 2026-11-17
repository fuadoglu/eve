import assert from "node:assert/strict";
import test from "node:test";
import { handleRealtorBalanceGet, handleRealtorSettlementPost } from "../../../src/modules/finance/realtor-settlement-handlers.ts";
import { parseRealtorBalance, parseRealtorSettlement, parseSettlementInput } from "../../../src/modules/finance/realtor-settlement-contract.ts";

const appBaseUrl = process.env.APP_BASE_URL;
process.env.APP_BASE_URL = "https://eve.test";
test.after(() => { if (appBaseUrl === undefined) delete process.env.APP_BASE_URL; else process.env.APP_BASE_URL = appBaseUrl; });

const reservationId = "fa500000-0000-4000-8000-000000000001";
const contactId = "fa400000-0000-4000-8000-000000000001";
const balance = { version: 4, contact_id: contactId, collected_minor: 10000, transferred_minor: 7000,
  commission_minor: 3000, commission_paid_minor: 3000, owner_due_minor: 0, realtor_due_minor: 0 };
const settlement = { id: "fa700000-0000-4000-8000-000000000001", reservation_id: reservationId, contact_id: contactId,
  kind: "commission_offset", amount_minor: 3000, occurred_at: "2026-11-18T10:00:00.000Z", balance_version: 5,
  created_at: "2026-11-18T10:00:01.000Z" };
const input = { expected_version: 4, contact_id: contactId, kind: "commission_offset", amount_minor: 3000 };

function request(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request(`https://eve.test/api/v1/reservations/${reservationId}/realtor-settlements`, {
    method: "POST", headers: { Host: "eve.test", Origin: "https://eve.test", "Content-Type": "application/json",
      "Idempotency-Key": "realtor-settlement-test-001", ...headers }, body: JSON.stringify(body),
  });
}

test("settlement input accepts safe integer qəpik and rejects contract drift", () => {
  assert.deepEqual(parseSettlementInput(input), input);
  assert.equal(parseSettlementInput({ ...input, amount_minor: 1.1 }), null);
  assert.equal(parseSettlementInput({ ...input, amount_minor: Number.MAX_SAFE_INTEGER + 1 }), null);
  assert.equal(parseSettlementInput({ ...input, expected_version: 0 }), null);
  assert.equal(parseSettlementInput({ ...input, kind: "commission_prepayment" }), null);
  assert.equal(parseSettlementInput({ ...input, owner_account_id: contactId }), null);
  assert.notEqual(parseRealtorBalance(balance), null);
  assert.equal(parseRealtorBalance({ ...balance, owner_due_minor: 1, realtor_due_minor: 1 }), null);
  assert.notEqual(parseRealtorSettlement(settlement), null);
  assert.equal(parseRealtorSettlement({ ...settlement, request_hash: "leak" }), null);
});

test("POST validates origin, idempotency key and body before writing; server ack is private", async () => {
  let calls = 0;
  const write = async () => { calls++; return settlement; };
  assert.equal((await handleRealtorSettlementPost(request(input, { Origin: "https://attacker.test" }), reservationId, write)).status, 403);
  assert.equal((await handleRealtorSettlementPost(request(input, { "Idempotency-Key": "short" }), reservationId, write)).status, 400);
  assert.equal((await handleRealtorSettlementPost(request({ ...input, amount_minor: 1.5 }), reservationId, write)).status, 422);
  assert.equal(calls, 0);
  const response = await handleRealtorSettlementPost(request(input), reservationId, write);
  assert.equal(response.status, 201);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
  assert.deepEqual((await response.json()).data, settlement);
  assert.equal(calls, 1);
});

test("balance GET returns only a valid server-acknowledged DTO", async () => {
  let calls = 0;
  const get = async () => { calls++; return balance; };
  const req = new Request(`https://eve.test/api/v1/reservations/${reservationId}/realtor-balance`, {
    headers: { Host: "eve.test", Origin: "https://eve.test" },
  });
  const response = await handleRealtorBalanceGet(req, reservationId, get);
  assert.equal(response.status, 200);
  assert.deepEqual((await response.json()).data, balance);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.equal(calls, 1);
});
