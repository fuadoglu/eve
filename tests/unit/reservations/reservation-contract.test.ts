import assert from "node:assert/strict";
import test from "node:test";
import {
  formatAznMinor,
  getReservationIdempotencyState,
  mapReservationApiError,
  normalizePhoneE164,
  parseAznMinor,
  parsePercentageBasisPoints,
  parseReservationEnvelope,
  toReservationCreateInput,
  validateReservationDraft,
  type ReservationDraft,
  type ReservationPropertyContext,
} from "../../../src/modules/reservations/reservation-contract.ts";

const property: ReservationPropertyContext = {
  id: "f2000000-0000-0000-0000-000000000011",
  name: "A1",
  max_guests: 4,
  default_check_in: "15:00",
  default_check_out: "11:00",
};

const draft = (): ReservationDraft => ({
  guest_name: " A Guest ",
  guest_phone: "+994501234567",
  guest_count: "2",
  check_in: "2027-05-01",
  check_out: "2027-05-04",
  check_in_time: "15:00",
  check_out_time: "11:00",
  total_azn: "300,01",
  free_stay: false,
  capacity_override_confirmed: false,
  hold_duration: "three_hours",
  receipt_azn: "100,25",
  receipt_kind: "rent_receipt",
  custodian: "owner",
  receipt_contact_id: "",
  commission_contact_id: "",
  commission_kind: "percentage",
  commission_value: "",
  note: "",
});

test("AZN parsing accepts local comma or dot and rejects hidden rounding", () => {
  assert.equal(parseAznMinor("300,01"), 30001);
  assert.equal(parseAznMinor("300.01"), 30001);
  assert.equal(parseAznMinor("0", false), null);
  assert.equal(parseAznMinor("1,001"), null);
  assert.equal(parseAznMinor("9,007,199,254,740,991"), null);
  assert.equal(parseAznMinor("90071992547409,92"), null);
  assert.throws(() => formatAznMinor(-1), /invalid_minor_amount/);
  assert.equal(formatAznMinor(30001).includes("300"), true);
  assert.equal(formatAznMinor(Number.MAX_SAFE_INTEGER).includes("409,91"), true);
});

test("percentage is entered as percent and serialized as basis points", () => {
  assert.equal(parsePercentageBasisPoints("10"), 1000);
  assert.equal(parsePercentageBasisPoints("0,01"), 1);
  assert.equal(parsePercentageBasisPoints("100"), 10000);
  assert.equal(parsePercentageBasisPoints("100,01"), null);
  assert.equal(parsePercentageBasisPoints("0"), null);
});

test("international phone formatting is normalized without guessing a country code", () => {
  assert.equal(normalizePhoneE164(" +994 (50) 123-45-67 "), "+994501234567");
  assert.equal(normalizePhoneE164(""), "");
  assert.equal(normalizePhoneE164("0501234567"), null);
  assert.equal(normalizePhoneE164("+994501234567 ext 2"), null);
});

test("reservation input keeps defaults, integer minor values and no empty receipt", () => {
  const value = draft();
  assert.deepEqual(validateReservationDraft(value, property), {});
  assert.deepEqual(toReservationCreateInput(value, property, "confirmed"), {
    property_id: property.id,
    guest_name: "A Guest",
    guest_phone: "+994501234567",
    guest_count: 2,
    check_in: "2027-05-01",
    check_out: "2027-05-04",
    check_in_time: "15:00",
    check_out_time: "11:00",
    status: "confirmed",
    total_minor: 30001,
    initial_receipt: { amount_minor: 10025, kind: "rent_receipt", custodian: "owner" },
  });
  value.receipt_azn = "";
  assert.equal("initial_receipt" in toReservationCreateInput(value, property, "confirmed"), false);
});

test("idempotency key is reused for identical retry payload and rotated after edits", () => {
  const input = toReservationCreateInput(draft(), property, "confirmed");
  let created = 0;
  const createKey = () => `reservation-test-key-${++created}`;
  const first = getReservationIdempotencyState(input, null, createKey);
  const retry = getReservationIdempotencyState(input, first, createKey);
  const edited = getReservationIdempotencyState({ ...input, total_minor: input.total_minor + 1 }, retry, createKey);
  assert.equal(retry.key, first.key);
  assert.notEqual(edited.key, first.key);
  assert.equal(created, 2);
});

test("API errors map to safe messages and allowlisted form fields", () => {
  const conflict = mapReservationApiError({ error: { code: "DATE_CONFLICT", message: "private backend detail", request_id: "req-1" } });
  assert.match(conflict.message, /tarixlər/);
  assert.equal(conflict.message.includes("private backend detail"), false);
  const validation = mapReservationApiError({
    error: {
      code: "VALIDATION_ERROR",
      message: "raw message",
      request_id: "req-2",
      field_errors: [
        { field: "guest_name", code: "INVALID", message: "raw message" },
        { field: "initial_receipt.amount_minor", code: "INVALID", message: "raw message" },
        { field: "internal.secret", code: "INVALID", message: "raw message" },
      ],
    },
  });
  assert.ok(validation.fieldErrors.guest_name);
  assert.ok(validation.fieldErrors.receipt_azn);
  assert.equal(Object.keys(validation.fieldErrors).length, 2);
  assert.equal(validation.message.includes("raw message"), false);
  assert.match(mapReservationApiError(new Error("offline")).message, /cavabı alınmadı/);
});

test("hold, capacity override, zero price and realtor receipt are explicit", () => {
  const value = draft();
  value.guest_count = "6";
  value.capacity_override_confirmed = true;
  value.total_azn = "0";
  value.free_stay = true;
  value.custodian = "realtor";
  value.receipt_contact_id = "f3000000-0000-0000-0000-000000000011";
  value.commission_contact_id = value.receipt_contact_id;
  value.commission_value = "10,5";
  assert.deepEqual(validateReservationDraft(value, property), {});
  assert.deepEqual(toReservationCreateInput(value, property, "hold"), {
    property_id: property.id,
    guest_name: "A Guest",
    guest_phone: "+994501234567",
    guest_count: 6,
    check_in: "2027-05-01",
    check_out: "2027-05-04",
    check_in_time: "15:00",
    check_out_time: "11:00",
    status: "hold",
    hold_duration: "three_hours",
    total_minor: 0,
    capacity_override_confirmed: true,
    initial_receipt: { amount_minor: 10025, kind: "rent_receipt", custodian: "realtor", contact_id: value.receipt_contact_id },
    commission: { contact_id: value.commission_contact_id, kind: "percentage", percentage_basis_points: 1050 },
    free_stay: true,
  });
});

test("invalid dates, unsupported fractional precision and omitted capacity consent fail validation", () => {
  const value = draft();
  value.check_in = "2027-02-30";
  value.check_out = "2027-05-01";
  value.total_azn = "10,005";
  value.guest_count = "5";
  const errors = validateReservationDraft(value, property);
  assert.ok(errors.check_in);
  assert.ok(errors.total_azn);
  assert.ok(errors.capacity_override_confirmed);
});

test("detail accepts only a server envelope with server balance DTO", () => {
  const envelope = {
    data: {
      id: "f4000000-0000-0000-0000-000000000011",
      property_id: property.id,
      current_placement_id: "f5000000-0000-0000-0000-000000000011",
      guest_name: "A Guest",
      guest_count: 2,
      check_in: "2027-05-01",
      check_out: "2027-05-04",
      check_in_time: "15:00",
      check_out_time: "11:00",
      status: "confirmed",
      total_minor: 30001,
      currency: "AZN",
      balance: {
        rent_received_minor: 10025,
        rent_refunded_minor: 0,
        remaining_minor: 19976,
        overpaid_minor: 0,
        deposit_held_minor: 0,
      },
      version: 1,
      created_at: "2027-04-01T10:00:00Z",
      updated_at: "2027-04-01T10:00:00Z",
    },
    meta: { request_id: "f6000000-0000-0000-0000-000000000011" },
  };
  assert.equal(parseReservationEnvelope(envelope).data.balance.remaining_minor, 19976);
  assert.throws(() => parseReservationEnvelope({ ...envelope, data: { ...envelope.data, server_balance: 0 } }), /invalid_reservation_envelope/);
  assert.throws(() => parseReservationEnvelope({ ...envelope, data: { ...envelope.data, balance: { ...envelope.data.balance, remaining_minor: -1 } } }), /invalid_reservation_envelope/);
});
