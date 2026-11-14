import assert from "node:assert/strict";
import test from "node:test";
import type { SessionProvider } from "../../../src/modules/identity/session-contract.ts";
import {
  handleAuthenticatedMediaContent, handleLinkSession, handleMediaAccess,
  handleScopedMediaAccess, handleScopedMediaContent,
} from "../../../src/modules/media/media-access-handlers.ts";
import { MediaAccessExpiredError } from "../../../src/modules/media/supabase-media-access.ts";
import { createMediaProxyUrl, hashScopedLinkToken, verifyMediaProxySignature, type MediaAccessSource } from "../../../src/modules/media/media-proxy-contract.ts";

const id = "a0222300-0000-4000-8000-000000000011";
const token = "x".repeat(43);
const secret = "server-only-signing-key-for-media-tests-2026";
const source: MediaAccessSource = {
  id, classification: "private_task", bucket: "eve-private-task", object_key: id,
  mime: "image/png", size_bytes: 4, link_expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
};

function session(userId: string | null): SessionProvider {
  return {
    async getCurrentUserId() { return userId; },
    async isCurrentSessionActive() { return userId !== null; },
    async signOutCurrentSession() {}, async revokeAllSessions() {}, async signOutAllSessions() {},
  };
}

function cookieRequest(url: string, cookie?: string): Request {
  return new Request(url, { headers: cookie ? { cookie } : {} });
}

test("proxy signatures bind media, expiry and authorization mode and expire after five minutes", async () => {
  const signed = await createMediaProxyUrl({ baseUrl: "https://eve.example/api/v1/media/x/access", mediaId: id,
    signingSecret: secret, nowSeconds: 1_800_000_000 });
  const url = new URL(signed.url);
  assert.equal(url.pathname, `/api/v1/media/${id}/content`);
  assert.equal(await verifyMediaProxySignature({ mediaId: id, expiresAtSeconds: Number(url.searchParams.get("exp")),
    signature: url.searchParams.get("sig")!, signingSecret: secret, nowSeconds: 1_800_000_001 }), true);
  assert.equal(await verifyMediaProxySignature({ mediaId: "a0222300-0000-4000-8000-000000000012",
    expiresAtSeconds: Number(url.searchParams.get("exp")), signature: url.searchParams.get("sig")!,
    signingSecret: secret, nowSeconds: 1_800_000_001 }), false);
  assert.equal(await verifyMediaProxySignature({ mediaId: id, expiresAtSeconds: Number(url.searchParams.get("exp")),
    signature: url.searchParams.get("sig")!, signingSecret: secret, nowSeconds: 1_800_000_301 }), false);
  const scoped = await createMediaProxyUrl({ baseUrl: "https://eve.example", mediaId: id, signingSecret: secret,
    token, linkExpiresAt: new Date(1_800_000_060 * 1000).toISOString(), nowSeconds: 1_800_000_000 });
  assert.equal(Number(new URL(scoped.url).searchParams.get("exp")), 1_800_000_060);
});

test("authenticated access returns a same-origin short-lived proxy only after active-session source authorization", async () => {
  let actor = "";
  const response = await handleMediaAccess(new Request(`https://eve.example/api/v1/media/${id}/access`), id,
    session("user-a"), async (actorId, mediaId) => { actor = actorId; assert.equal(mediaId, id); return source; }, secret);
  assert.equal(actor, "user-a");
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  const body = await response.json() as { data: { media_id: string; url: string; expires_at: string } };
  assert.equal(body.data.media_id, id);
  assert.equal(new URL(body.data.url).origin, "https://eve.example");
  assert.equal(Date.parse(body.data.expires_at) - Date.now() < 301_000, true);
});

test("link exchange is same-origin, accepts only the token field and sets a scoped HttpOnly cookie with no-store", async () => {
  let hash = "";
  const request = new Request("https://eve.example/api/v1/link-session", {
    method: "POST", headers: { origin: "https://eve.example", "content-type": "application/json" },
    body: JSON.stringify({ token }),
  });
  const response = await handleLinkSession(request, async (value) => {
    hash = value;
    return { resource_type: "task", expires_at: new Date(Date.now() + 60_000).toISOString() };
  });
  assert.equal(hash, await hashScopedLinkToken(token));
  assert.equal(response.status, 200);
  assert.match(response.headers.get("set-cookie") ?? "", /HttpOnly; SameSite=Strict; Secure/);
  assert.match(response.headers.get("set-cookie") ?? "", new RegExp(`Path=\\/api\\/v1\\/s\\/${token}\\/`));
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.doesNotMatch(await response.text(), new RegExp(token));

  const denied = await handleLinkSession(new Request("https://eve.example/api/v1/link-session", {
    method: "POST", headers: { origin: "https://attacker.example", "content-type": "application/json" }, body: JSON.stringify({ token }),
  }), async () => { throw new Error("must_not_call"); });
  assert.equal(denied.status, 403);
});

test("scoped media access requires eve_scope hash match before querying the database", async () => {
  let queries = 0;
  const denied = await handleScopedMediaAccess(cookieRequest(`https://eve.example/api/v1/s/${token}/media/${id}/access`),
    token, id, async () => { queries++; return source; }, secret);
  assert.equal(denied.status, 404);
  assert.equal(queries, 0);

  const allowed = await handleScopedMediaAccess(cookieRequest(`https://eve.example/api/v1/s/${token}/media/${id}/access`,
    `eve_scope=${await hashScopedLinkToken(token)}`), token, id, async (_hash, mediaId) => {
      queries++;
      assert.equal(mediaId, id);
      return source;
    }, secret);
  assert.equal(allowed.status, 200);
  assert.equal(queries, 1);
  const body = await allowed.json() as { data: { proxy_url: string; access_mode: string } };
  assert.equal(new URL(body.data.proxy_url).pathname, `/api/v1/s/${token}/media/${id}/content`);
  assert.equal(body.data.access_mode, "revalidated_proxy");
});

test("expired or revoked scoped links map to the documented 410 response", async () => {
  const response = await handleScopedMediaAccess(cookieRequest(`https://eve.example/api/v1/s/${token}/media/${id}/access`,
    `eve_scope=${await hashScopedLinkToken(token)}`), token, id, async () => {
    throw new MediaAccessExpiredError();
  }, secret);
  assert.equal(response.status, 410);
  const payload = await response.json() as { error: { code: string } };
  assert.equal(payload.error.code, "LINK_EXPIRED");
});

test("each scoped content GET checks its cookie, signed URL and live source before streaming no-store bytes", async () => {
  const tokenHash = await hashScopedLinkToken(token);
  const signed = await createMediaProxyUrl({ baseUrl: "https://eve.example/api/v1/s/x/access", mediaId: id,
    signingSecret: secret, token, linkExpiresAt: source.link_expires_at, nowSeconds: Math.floor(Date.now() / 1000) });
  let sourceCalls = 0;
  let storageCalls = 0;
  const resolve = async (scope: string, mediaId: string) => {
    sourceCalls++;
    assert.equal(scope, tokenHash);
    assert.equal(mediaId, id);
    return source;
  };
  const fetchObject = async () => {
    storageCalls++;
    return new Response(new Uint8Array([1, 2, 3, 4]), { headers: { "content-length": "4" } });
  };
  const url = signed.url;
  const denied = await handleScopedMediaContent(cookieRequest(url), token, id, resolve, secret, fetchObject);
  assert.equal(denied.status, 404);
  assert.equal(sourceCalls, 0);

  const response = await handleScopedMediaContent(cookieRequest(url, `eve_scope=${tokenHash}`), token, id, resolve, secret, fetchObject);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
  assert.equal(response.headers.get("referrer-policy"), "no-referrer");
  assert.equal(response.headers.get("x-content-type-options"), "nosniff");
  assert.equal(response.headers.get("content-type"), "image/png");
  assert.deepEqual([...new Uint8Array(await response.arrayBuffer())], [1, 2, 3, 4]);
  assert.equal(sourceCalls, 1);
  assert.equal(storageCalls, 1);
});

test("authenticated content requires a live session and current signed URL", async () => {
  const signed = await createMediaProxyUrl({ baseUrl: `https://eve.example/api/v1/media/${id}/access`, mediaId: id, signingSecret: secret });
  let calls = 0;
  const resolve = async () => { calls++; return source; };
  const fetchObject = async () => new Response(new Uint8Array([1, 2, 3, 4]), { headers: { "content-length": "4" } });
  const expired = new URL(signed.url);
  expired.searchParams.set("exp", String(Math.floor(Date.now() / 1000) - 1));
  assert.equal((await handleAuthenticatedMediaContent(new Request(expired), id, session("user-a"), resolve, secret, fetchObject)).status, 404);
  assert.equal(calls, 0);
  const response = await handleAuthenticatedMediaContent(new Request(signed.url), id, session("user-a"), resolve, secret, fetchObject);
  assert.equal(response.status, 200);
  assert.equal(calls, 1);
});
