import assert from "node:assert/strict";
import test from "node:test";
import { parseExpenseProposal, parseExpenseProposalInput } from "../../../src/modules/finance/expense-proposal-contract.ts";
import { handleExpenseProposalPost } from "../../../src/modules/finance/expense-proposal-handler.ts";

const previous = process.env.APP_BASE_URL;
process.env.APP_BASE_URL = "https://eve.test";
test.after(() => { if (previous === undefined) delete process.env.APP_BASE_URL; else process.env.APP_BASE_URL = previous; });
const property = "f9300000-0000-4000-8000-000000000021";
const second = "f9300000-0000-4000-8000-000000000022";
const input = { category: "cleaning", amount_minor: 1001, allocations: [
  { property_id: property, amount_minor: 501 }, { property_id: second, amount_minor: 500 },
], occurred_on: "2026-11-18" };
const result = { id: "f9800000-0000-4000-8000-000000000021", ...input, currency: "AZN",
  approval: "approved", payment_status: "unpaid", paid_minor: 0, receipt_media_ids: [],
  version: 1, created_at: "2026-11-18T10:00:00Z", updated_at: "2026-11-18T10:00:00Z" };

test("proposal enforces safe integer allocation sum, unique property and unpaid state", () => {
  assert.deepEqual(parseExpenseProposalInput(input), input);
  assert.equal(parseExpenseProposalInput({ ...input, amount_minor: 1000 }), null);
  assert.equal(parseExpenseProposalInput({ ...input, amount_minor: 1.2 }), null);
  assert.equal(parseExpenseProposalInput({ ...input, allocations: [input.allocations[0], input.allocations[0]] }), null);
  assert.equal(parseExpenseProposalInput({ ...input, mark_paid: true }), null);
  assert.equal(parseExpenseProposalInput({ ...input, receipt_media_ids: [result.id] }), null);
  assert.equal(parseExpenseProposalInput({ ...input, occurred_on: "2026-02-30" }), null);
  assert.notEqual(parseExpenseProposal(result), null);
  assert.notEqual(parseExpenseProposal({ ...result, approval: "proposed" }), null);
  assert.equal(parseExpenseProposal({ ...result, payment_status: "paid" }), null);
  assert.equal(parseExpenseProposal({ ...result, owner_account_id: property }), null);
});

function request(body: unknown, origin = "https://eve.test"): Request {
  return new Request("https://eve.test/api/v1/expenses", { method: "POST", headers: {
    Host: "eve.test", Origin: origin, "Content-Type": "application/json", "Idempotency-Key": "expense-key-00000001",
  }, body: JSON.stringify(body) });
}
test("POST sends validated input once and exposes only acknowledged private DTO", async () => {
  let calls = 0;
  const create = async (received: unknown, key: string) => { calls++; assert.deepEqual(received, input); assert.equal(key, "expense-key-00000001"); return result; };
  assert.equal((await handleExpenseProposalPost(request(input, "https://other.test"), create)).status, 403);
  assert.equal((await handleExpenseProposalPost(request({ ...input, mark_paid: true }), create)).status, 422);
  assert.equal(calls, 0);
  const reply = await handleExpenseProposalPost(request(input), create);
  assert.equal(reply.status, 201);
  assert.equal(reply.headers.get("Cache-Control"), "private, no-store");
  assert.equal((await reply.json()).data.payment_status, "unpaid");
  assert.equal(calls, 1);
  assert.equal((await handleExpenseProposalPost(request(input), async () => ({ ...result, paid_minor: 1001 }))).status, 503);
});
