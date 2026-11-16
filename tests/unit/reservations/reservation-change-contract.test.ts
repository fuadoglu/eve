import assert from "node:assert/strict";
import test from "node:test";
import {
  parseReservationDatePricePatch,
  parseReservationMoveInput,
} from "../../../src/modules/reservations/reservation-change-contract.ts";

test("date/price patch accepts valid dates, integer qəpik and an explicit zero-price confirmation", () => {
  assert.deepEqual(parseReservationDatePricePatch({
    expected_version: 3,
    check_in: "2027-05-02",
    check_out: "2027-05-06",
    total_minor: 27550,
  }), {
    expected_version: 3,
    check_in: "2027-05-02",
    check_out: "2027-05-06",
    total_minor: 27550,
  });
  assert.deepEqual(parseReservationDatePricePatch({ expected_version: 1, total_minor: 0, free_stay: true }), {
    expected_version: 1, total_minor: 0, free_stay: true,
  });
});

test("date/price patch rejects nonpositive version, malformed interval, rounding, unconfirmed zero and extra fields", () => {
  for (const value of [
    { expected_version: 0, check_in: "2027-05-02" },
    { expected_version: 1, check_in: "2027-02-29" },
    { expected_version: 1, check_in: "2027-05-03", check_out: "2027-05-03" },
    { expected_version: 1, total_minor: 1.5 },
    { expected_version: 1, total_minor: 0 },
    { expected_version: 1, total_minor: 100, status: "confirmed" },
    { expected_version: 1 },
  ]) assert.throws(() => parseReservationDatePricePatch(value));
});

test("same-owner move input shape is validated without claiming server-side authorization", () => {
  assert.deepEqual(parseReservationMoveInput({
    expected_version: 2,
    to_property_id: "f2000000-0000-0000-0000-000000000012",
    new_total_minor: 31500,
    reason: "Qonaq tarix dəyişikliyi istədi",
  }), {
    expected_version: 2,
    to_property_id: "f2000000-0000-0000-0000-000000000012",
    new_total_minor: 31500,
    reason: "Qonaq tarix dəyişikliyi istədi",
  });
  assert.deepEqual(parseReservationMoveInput({
    expected_version: 2,
    to_property_id: "f2000000-0000-0000-0000-000000000012",
    new_total_minor: 0,
    free_stay: true,
  }).new_total_minor, 0);
});

test("move parser rejects invalid target, unsafe price, zero without confirmation and uncontracted fields", () => {
  const valid = {
    expected_version: 2,
    to_property_id: "f2000000-0000-0000-0000-000000000012",
    new_total_minor: 31500,
  };
  for (const value of [
    { ...valid, expected_version: 0 },
    { ...valid, to_property_id: "not-a-uuid" },
    { ...valid, new_total_minor: 9007199254740992 },
    { ...valid, new_total_minor: 0 },
    { ...valid, force: true },
    { ...valid, reason: "x".repeat(1001) },
  ]) assert.throws(() => parseReservationMoveInput(value));
});
