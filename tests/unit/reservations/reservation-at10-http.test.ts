import test from "node:test";
import assert from "node:assert/strict";
import { handleReservationPatch, handleReservationTransition } from "../../../src/modules/reservations/reservation-at10-http.ts";

const id = "f4000000-0000-4000-8000-000000000001";
const key = "reservation-at10-key-0001";
const old = process.env.APP_BASE_URL;
process.env.APP_BASE_URL = "https://eve.test";
test.after(() => { if (old === undefined) delete process.env.APP_BASE_URL; else process.env.APP_BASE_URL = old; });

function request(path: string, body: unknown, headers: Record<string, string> = {}) {
  return new Request(`https://eve.test/api/v1/reservations/${id}${path}`, { method: path ? "POST" : "PATCH",
    headers: { Host: "eve.test", Origin: "https://eve.test", "Content-Type": "application/json", "Idempotency-Key": key, ...headers }, body: JSON.stringify(body) });
}
function dto() { return { id, property_id: "f2000000-0000-4000-8000-000000000001", current_placement_id: "f5000000-0000-4000-8000-000000000001",
  guest_name: "A Guest", guest_count: 1, check_in: "2027-05-01", check_out: "2027-05-03", check_in_time: "15:00", check_out_time: "11:00",
  status: "confirmed", total_minor: 28000, currency: "AZN", balance: { rent_received_minor: 0, rent_refunded_minor: 0, remaining_minor: 28000, overpaid_minor: 0, deposit_held_minor: 0 },
  version: 4, created_at: "2027-01-01T00:00:00.000Z", updated_at: "2027-01-02T00:00:00.000Z" }; }

test("PATCH enforces origin, media type, idempotency key and documented input bounds before operation", async () => {
  let calls = 0;
  const patch = async () => { calls++; return dto(); };
  assert.equal((await handleReservationPatch(request("", { expected_version: 3, note: "ok" }, { Origin: "https://attacker.test" }), id, patch)).status, 403);
  assert.equal((await handleReservationPatch(request("", { expected_version: 3, note: "ok" }, { "Content-Type": "text/plain" }), id, patch)).status, 400);
  assert.equal((await handleReservationPatch(request("", { expected_version: 3, note: "ok" }, { "Idempotency-Key": "bad" }), id, patch)).status, 400);
  assert.equal((await handleReservationPatch(request("", { expected_version: 3, total_minor: 0 }), id, patch)).status, 422);
  assert.equal((await handleReservationPatch(request("", { expected_version: 3, unknown: true }), id, patch)).status, 422);
  assert.equal(calls, 0);
});

test("PATCH passes parsed input and key, returns validated envelope, and maps safe conflicts", async () => {
  let seen: unknown;
  const patchInput = { expected_version: 3, guest_name: "A Guest", guest_phone: null };
  const response = await handleReservationPatch(request("", patchInput), id, async (gotId, input, gotKey) => { seen = { gotId, input, gotKey }; return dto(); });
  assert.equal(response.status, 200);
  assert.deepEqual(seen, { gotId: id, input: patchInput, gotKey: key });
  assert.equal((await response.json()).data.version, 4);
  const conflict = await handleReservationPatch(request("", patchInput), id, async () => { throw Object.assign(new Error("private DB detail"), { code: "CONFLICT" }); });
  assert.equal(conflict.status, 409);
  assert.equal((await conflict.text()).includes("private DB detail"), false);
});

test("transition validates action-specific fields and refuses success for mismatched resource", async () => {
  let calls = 0;
  const transition = async () => { calls++; return dto(); };
  assert.equal((await handleReservationTransition(request("/transition", { expected_version: 3, action: "release_remaining_days" }), id, transition)).status, 422);
  assert.equal(calls, 0);
  const ok = await handleReservationTransition(request("/transition", { expected_version: 3, action: "confirm" }), id, transition);
  assert.equal(ok.status, 200);
  const mismatch = await handleReservationTransition(request("/transition", { expected_version: 3, action: "check_in" }), id, async () => ({ ...dto(), id: "f4000000-0000-4000-8000-000000000099" }));
  assert.equal(mismatch.status, 503);
});

test("transition rejects malformed JSON, invalid id and returns unauthenticated status safely", async () => {
  const malformed = new Request(`https://eve.test/api/v1/reservations/${id}/transition`, { method: "POST", headers: { Host: "eve.test", Origin: "https://eve.test", "Content-Type": "application/json", "Idempotency-Key": key }, body: "{" });
  assert.equal((await handleReservationTransition(malformed, id, async () => dto())).status, 400);
  assert.equal((await handleReservationTransition(request("/transition", { expected_version: 1, action: "cancel" }), "bad", async () => dto())).status, 404);
  const denied = await handleReservationTransition(request("/transition", { expected_version: 1, action: "cancel" }), id, async () => { throw Object.assign(new Error("secret"), { code: "UNAUTHENTICATED" }); });
  assert.equal(denied.status, 401);
  assert.equal((await denied.text()).includes("secret"), false);
});
