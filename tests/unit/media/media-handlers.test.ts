import assert from "node:assert/strict";
import test from "node:test";
import type { SessionProvider } from "../../../src/modules/identity/session-contract.ts";
import { SessionUnauthorizedError } from "../../../src/modules/identity/session-contract.ts";
import { handleMediaFinalize } from "../../../src/modules/media/media-handlers.ts";
import { MediaValidationError } from "../../../src/modules/media/media-validation.ts";
import type { MediaFinalizeResult } from "../../../src/modules/media/supabase-media-finalizer.ts";

const mediaId = "a0222300-0000-4000-8000-000000000011";
const result: MediaFinalizeResult = {
  id: mediaId,
  property_id: "a0222200-0000-4000-8000-000000000011",
  kind: "image",
  classification: "public_property",
  status: "validated",
  size_bytes: 4,
  version: 2,
  created_at: "2026-11-14T00:00:00Z",
  updated_at: "2026-11-14T00:00:00Z",
};

function session(userId: string | null): SessionProvider {
  return {
    async getCurrentUserId() { return userId; },
    async isCurrentSessionActive() { return userId !== null; },
    async signOutCurrentSession() {},
    async revokeAllSessions() {},
    async signOutAllSessions() {},
  };
}

function request(options: { origin?: string; key?: string; body?: string } = {}): Request {
  return new Request("https://eve.example/api/v1/media/a0222300-0000-4000-8000-000000000011/finalize", {
    method: "POST",
    headers: {
      origin: options.origin ?? "https://eve.example",
      "content-type": "application/json",
      "idempotency-key": options.key ?? "media-finalize-key-0001",
    },
    body: options.body ?? "{}",
  });
}

test("finalize handler returns success only after server operation acknowledges", async () => {
  let called = false;
  const response = await handleMediaFinalize(request(), mediaId, session("actor-1"), async (input) => {
    called = true;
    assert.equal(input.actorUserId, "actor-1");
    assert.equal(input.mediaId, mediaId);
    assert.equal(input.idempotencyKey, "media-finalize-key-0001");
    return result;
  });
  assert.equal(called, true);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.deepEqual((await response.json() as { data: MediaFinalizeResult }).data, result);
});

test("rejects foreign origins, non-empty bodies and invalid idempotency keys before provider calls", async () => {
  let calls = 0;
  const finalize = async () => { calls++; return result; };
  assert.equal((await handleMediaFinalize(request({ origin: "https://attacker.example" }), mediaId, session("actor-1"), finalize)).status, 403);
  assert.equal((await handleMediaFinalize(request({ body: JSON.stringify({ actor_id: "forged" }) }), mediaId, session("actor-1"), finalize)).status, 422);
  assert.equal((await handleMediaFinalize(request({ key: "short" }), mediaId, session("actor-1"), finalize)).status, 400);
  assert.equal(calls, 0);
});

test("maps unauthenticated sessions and byte validation failures to safe API errors", async () => {
  const unauthorized: SessionProvider = {
    ...session(null),
    async getCurrentUserId() { throw new SessionUnauthorizedError(); },
  };
  let response = await handleMediaFinalize(request(), mediaId, unauthorized, async () => result);
  assert.equal(response.status, 401);

  response = await handleMediaFinalize(request(), mediaId, session("actor-1"), async () => {
    throw new MediaValidationError("mime_mismatch");
  });
  assert.equal(response.status, 422);
  const payload = await response.json() as { error: { message: string } };
  assert.doesNotMatch(payload.error.message, /bucket|object_key|sha/i);
});
