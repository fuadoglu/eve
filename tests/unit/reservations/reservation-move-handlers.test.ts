import test from "node:test";
import assert from "node:assert/strict";
import { handleReservationMove } from "../../../src/modules/reservations/reservation-move-handlers.ts";

const reservationId = "f4000000-0000-4000-8000-000000000001";
const sourcePropertyId = "f2000000-0000-4000-8000-000000000001";
const targetPropertyId = "f2000000-0000-4000-8000-000000000002";
const input = { expected_version: 3, to_property_id: targetPropertyId, new_total_minor: 28000 };
const originalAppBaseUrl = process.env.APP_BASE_URL;
process.env.APP_BASE_URL = "https://eve.test";
test.after(() => {
  if (originalAppBaseUrl === undefined) delete process.env.APP_BASE_URL;
  else process.env.APP_BASE_URL = originalAppBaseUrl;
});

function request(body: unknown = input, headers: Record<string, string> = {}): Request {
  return new Request(`https://eve.test/api/v1/reservations/${reservationId}/move`, {
    method: "POST",
    headers: { Host: "eve.test", Origin: "https://eve.test", "Content-Type": "application/json",
      "Idempotency-Key": "reservation-move-key-0001", ...headers },
    body: JSON.stringify(body),
  });
}

function reservationDto() {
  return {
    id: reservationId,
    property_id: targetPropertyId,
    current_placement_id: "f5000000-0000-4000-8000-000000000002",
    guest_name: "A Guest",
    guest_count: 1,
    check_in: "2027-05-01",
    check_out: "2027-05-03",
    check_in_time: "15:00",
    check_out_time: "11:00",
    status: "confirmed",
    total_minor: 28000,
    currency: "AZN",
    balance: { rent_received_minor: 10000, rent_refunded_minor: 0, remaining_minor: 18000, overpaid_minor: 0, deposit_held_minor: 0 },
    version: 4,
    created_at: "2027-01-01T00:00:00.000Z",
    updated_at: "2027-01-02T00:00:00.000Z",
  };
}

test("move route rejects origin and invalid input before calling the command", async () => {
  let calls = 0;
  const move = async () => { calls++; return reservationDto(); };
  assert.equal((await handleReservationMove(request(input, { Origin: "https://attacker.test" }), reservationId, move)).status, 403);
  assert.equal((await handleReservationMove(request({ ...input, unknown: true }), reservationId, move)).status, 422);
  assert.equal((await handleReservationMove(request(input, { "Idempotency-Key": "bad" }), reservationId, move)).status, 400);
  assert.equal(calls, 0);
});

test("move route returns a validated server acknowledgement and never hides a provider failure as success", async () => {
  let received: { id: string; input: unknown; key: string } | null = null;
  const response = await handleReservationMove(request(), reservationId, async (id, body, key) => {
    received = { id, input: body, key };
    return reservationDto();
  });
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.deepEqual(received, { id: reservationId, input, key: "reservation-move-key-0001" });
  assert.equal(body.data.property_id, targetPropertyId);
  assert.equal(body.meta.request_id.length > 0, true);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");

  const failure = await handleReservationMove(request(), reservationId, async () => {
    throw Object.assign(new Error("internal database detail"), { code: "CONFLICT" });
  });
  assert.equal(failure.status, 409);
  assert.equal((await failure.text()).includes("internal database detail"), false);
});

test("move route rejects a response for a different reservation id", async () => {
  const response = await handleReservationMove(request(), reservationId, async () => ({
    ...reservationDto(), id: "f4000000-0000-4000-8000-000000000099",
  }));
  assert.equal(response.status, 503);
});

test("move route does not accept malformed reservation ids", async () => {
  let calls = 0;
  const response = await handleReservationMove(request(), "not-a-uuid", async () => { calls++; return reservationDto(); });
  assert.equal(response.status, 404);
  assert.equal(calls, 0);
  assert.notEqual(sourcePropertyId, targetPropertyId);
});
