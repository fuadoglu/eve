import test from "node:test";
import assert from "node:assert/strict";
import { handleReservationCreate } from "../../../src/modules/reservations/reservation-handlers.ts";

const input = { property_id: "f2000000-0000-4000-8000-000000000001", guest_name: "A Guest" };

function request(headers: Record<string, string> = {}, body: unknown = input): Request {
  return new Request("https://eve.test/api/v1/reservations", {
    method: "POST",
    headers: { Origin: "https://eve.test", "Content-Type": "application/json", "Idempotency-Key": "reservation-key-0001", ...headers },
    body: JSON.stringify(body),
  });
}

function reservationDto() {
  return {
    id: "f4000000-0000-4000-8000-000000000001",
    property_id: input.property_id,
    current_placement_id: "f5000000-0000-4000-8000-000000000001",
    guest_name: "A Guest",
    guest_count: 1,
    check_in: "2027-05-01",
    check_out: "2027-05-03",
    check_in_time: "15:00",
    check_out_time: "11:00",
    status: "confirmed",
    total_minor: 30000,
    currency: "AZN",
    balance: { rent_received_minor: 10000, rent_refunded_minor: 0, remaining_minor: 20000, overpaid_minor: 0, deposit_held_minor: 0 },
    version: 1,
    created_at: "2027-01-01T00:00:00.000Z",
    updated_at: "2027-01-01T00:00:00.000Z",
  };
}

test("origin, JSON media type and idempotency key are checked before calling the reservation operation", async () => {
  let calls = 0;
  const create = async () => { calls++; return reservationDto(); };
  assert.equal((await handleReservationCreate(request({ Origin: "https://attacker.test" }), create)).status, 403);
  assert.equal((await handleReservationCreate(request({ "Idempotency-Key": "short" }), create)).status, 400);
  assert.equal((await handleReservationCreate(request({ "Content-Type": "text/plain" }), create)).status, 400);
  assert.equal(calls, 0);
});

test("successful create returns only a validated server DTO after the operation acknowledges", async () => {
  let receivedInput: unknown;
  let receivedKey = "";
  const response = await handleReservationCreate(request(), async (value, key) => {
    receivedInput = value;
    receivedKey = key;
    return reservationDto();
  });
  const body = await response.json();
  assert.equal(response.status, 201);
  assert.deepEqual(receivedInput, input);
  assert.equal(receivedKey, "reservation-key-0001");
  assert.equal(body.data.balance.remaining_minor, 20000);
  assert.equal(typeof body.meta.request_id, "string");
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
});

test("database conflict is returned without exposing provider details", async () => {
  const response = await handleReservationCreate(request(), async () => { throw Object.assign(new Error("secret detail"), { code: "CONFLICT" }); });
  const body = await response.json();
  assert.equal(response.status, 409);
  assert.equal(body.error.code, "CONFLICT");
  assert.doesNotMatch(JSON.stringify(body), /secret detail/);
});

test("malformed server DTO never becomes a success response", async () => {
  const response = await handleReservationCreate(request(), async () => ({ id: "only-an-id" }));
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error.code, "PROVIDER_UNAVAILABLE");
});
