import assert from "node:assert/strict";
import test from "node:test";
import { parseReservationLifecycleTransition } from "../../../src/modules/reservations/reservation-transition-contract.ts";

test("lifecycle transitions accept the documented versioned actions", () => {
  for (const action of ["cancel", "no_show", "check_in", "check_out"] as const) {
    assert.equal(parseReservationLifecycleTransition({ expected_version: 4, action }).action, action);
  }
  assert.deepEqual(parseReservationLifecycleTransition({
    expected_version: 5,
    action: "cancel",
    financial_decision: { mode: "keep_as_is" },
  }), {
    expected_version: 5,
    action: "cancel",
    financial_decision: { mode: "keep_as_is" },
  });
});

test("cancel/no-show adjustment accepts receipt-linked integer minor amounts", () => {
  assert.deepEqual(parseReservationLifecycleTransition({
    expected_version: 1,
    action: "no_show",
    financial_decision: {
      mode: "adjust",
      rent_refunds: [{ original_id: "f3000000-0000-0000-0000-000000000011", amount_minor: 2500 }],
      deposit_returns: [{ original_id: "f3000000-0000-0000-0000-000000000012", amount_minor: 10000 }],
      commission_keep_minor: 500,
    },
  }).action, "no_show");
});

test("lifecycle transition rejects unsupported actions, malformed version, extra keys and oversized reason", () => {
  for (const value of [
    { expected_version: 0, action: "cancel" },
    { expected_version: 1, action: "move_property" },
    { expected_version: 1, action: "check_in", status: "checked_in" },
    { expected_version: 1, action: "cancel", reason: "x".repeat(2001) },
  ]) assert.throws(() => parseReservationLifecycleTransition(value));
  assert.equal(parseReservationLifecycleTransition({
    expected_version: 1, action: "cancel", reason: "😀".repeat(2000),
  }).action, "cancel");
  assert.throws(() => parseReservationLifecycleTransition({
    expected_version: 1, action: "cancel", reason: "😀".repeat(2001),
  }));
});

test("financial decisions are limited to cancel/no-show and have exact mode shapes", () => {
  for (const value of [
    { expected_version: 1, action: "check_in", financial_decision: { mode: "keep_as_is" } },
    { expected_version: 1, action: "cancel", financial_decision: { mode: "keep_as_is", commission_keep_minor: 0 } },
    { expected_version: 1, action: "cancel", financial_decision: { mode: "adjust" } },
    { expected_version: 1, action: "cancel", financial_decision: { mode: "adjust", rent_refunds: [] } },
    { expected_version: 1, action: "no_show", financial_decision: { mode: "adjust", deposit_returns: [{ original_id: "bad", amount_minor: 1 }] } },
    { expected_version: 1, action: "cancel", financial_decision: { mode: "adjust", commission_keep_minor: -1 } },
  ]) assert.throws(() => parseReservationLifecycleTransition(value));
});
