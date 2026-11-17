import assert from "node:assert/strict";
import test from "node:test";
import { parseNormalizedVerifiedBillingEvent, parseVerifiedBillingEventResult } from "../../../src/modules/billing/verified-billing-event.ts";

const orderId = "a0272000-0000-4000-8000-000000000001";
const valid = {
  order_id: orderId,
  event_key: "opaque-normalized-event-key",
  provider_transaction_id: "opaque-normalized-transaction-reference",
  amount_minor: 999,
  currency: "AZN",
};

test("normalized verified billing event accepts only safe internal fields", () => {
  assert.deepEqual(parseNormalizedVerifiedBillingEvent(valid), valid);
  assert.equal(parseNormalizedVerifiedBillingEvent({ ...valid, amount_minor: 0 }), null);
  assert.equal(parseNormalizedVerifiedBillingEvent({ ...valid, amount_minor: 999.5 }), null);
  assert.equal(parseNormalizedVerifiedBillingEvent({ ...valid, currency: "USD" }), null);
  assert.equal(parseNormalizedVerifiedBillingEvent({ ...valid, event_key: "\nraw" }), null);
  assert.equal(parseNormalizedVerifiedBillingEvent({ ...valid, provider_payload: { signature: "secret" } }), null);
});

test("verified billing result rejects inconsistent entitlement/review state", () => {
  assert.equal(parseVerifiedBillingEventResult({ event_id: orderId, order_id: orderId, verification_state: "verified", replay: false, entitlement_applied: true, manual_review_required: false }), null);
  assert.equal(parseVerifiedBillingEventResult({ event_id: orderId, order_id: orderId, verification_state: "applied", replay: false, entitlement_applied: true, manual_review_required: false })?.entitlement_applied, true);
  assert.equal(parseVerifiedBillingEventResult({ event_id: orderId, order_id: orderId, verification_state: "verified", replay: false, entitlement_applied: false, manual_review_required: true, rejection_code: "closed_order_manual_reconcile_required" })?.manual_review_required, true);
});
