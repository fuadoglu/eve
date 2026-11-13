import assert from "node:assert/strict";
import test from "node:test";
import { POST as currentLogoutRoute } from "../../../src/app/api/v1/auth/logout/route.ts";
import { POST as logoutAllRoute } from "../../../src/app/api/v1/auth/logout-all/route.ts";
import {
  handleCurrentSessionLogout,
  handleLogoutAllSessions,
} from "../../../src/modules/identity/session-handlers.ts";
import type { SessionProvider } from "../../../src/modules/identity/session-contract.ts";

function makeProvider(overrides: Partial<SessionProvider> = {}) {
  const calls: string[] = [];
  const provider: SessionProvider = {
    async getCurrentUserId() { calls.push("get-user"); return "user-a"; },
    async isCurrentSessionActive() { calls.push("check-active"); return true; },
    async signOutCurrentSession() { calls.push("sign-out-local"); },
    async revokeAllSessions() { calls.push("revoke-app-sessions"); },
    async signOutAllSessions() { calls.push("sign-out-global"); },
    ...overrides,
  };
  return { provider, calls };
}

function logoutRequest(path: string, body = "{}", origin = "https://eve.example") {
  return new Request(`https://eve.example${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Origin: origin },
    body,
  });
}

test("current logout verifies the active session and revokes only the local session", async () => {
  const { provider, calls } = makeProvider();
  const response = await handleCurrentSessionLogout(logoutRequest("/api/v1/auth/logout"), provider);
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.deepEqual(payload.data, { accepted: true });
  assert.match(payload.meta.request_id, /^[0-9a-f-]{36}$/u);
  assert.deepEqual(calls, ["get-user", "check-active", "sign-out-local"]);
  assert.equal(response.headers.get("cache-control"), "private, no-store");
});

test("logout-all records the app cutoff before provider global revocation", async () => {
  const { provider, calls } = makeProvider();
  const response = await handleLogoutAllSessions(logoutRequest("/api/v1/auth/logout-all"), provider);
  assert.equal(response.status, 200);
  assert.deepEqual(calls, ["get-user", "check-active", "revoke-app-sessions", "sign-out-global"]);
});

test("logout-all never acknowledges provider failure after applying the cutoff", async () => {
  const { provider, calls } = makeProvider({
    async signOutAllSessions() { calls.push("sign-out-global"); throw new Error("private provider detail"); },
  });
  const response = await handleLogoutAllSessions(logoutRequest("/api/v1/auth/logout-all"), provider);
  const payload = await response.json();
  assert.equal(response.status, 503);
  assert.equal(payload.error.code, "PROVIDER_UNAVAILABLE");
  assert.doesNotMatch(JSON.stringify(payload), /private provider detail/);
  assert.deepEqual(calls, [
    "get-user", "check-active", "revoke-app-sessions", "sign-out-global", "sign-out-local",
  ]);
});

test("invalid input, cross-origin POST and revoked sessions never initialize provider", async () => {
  let initialized = false;
  const lazyProvider = async () => {
    initialized = true;
    return makeProvider().provider;
  };
  const badBody = await handleCurrentSessionLogout(logoutRequest("/api/v1/auth/logout", "{\"extra\":true}"), lazyProvider);
  assert.equal(badBody.status, 422);
  assert.equal(initialized, false);
  const badOrigin = await handleLogoutAllSessions(
    logoutRequest("/api/v1/auth/logout-all", "{}", "https://attacker.example"), lazyProvider,
  );
  assert.equal(badOrigin.status, 403);
  assert.equal(initialized, false);
  const missingOrigin = await handleCurrentSessionLogout(new Request("https://eve.example/api/v1/auth/logout", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: "{}",
  }), lazyProvider);
  assert.equal(missingOrigin.status, 403);
  assert.equal(initialized, false);
  const { provider } = makeProvider({ async isCurrentSessionActive() { return false; } });
  const revoked = await handleLogoutAllSessions(logoutRequest("/api/v1/auth/logout-all"), provider);
  assert.equal(revoked.status, 401);
});

test("OpenAPI logout route wrappers validate request bodies before provider initialization", async () => {
  for (const route of [currentLogoutRoute, logoutAllRoute]) {
    const response = await route(new Request("https://eve.example/api/v1/auth/logout", {
      method: "POST",
      headers: { "Content-Type": "application/json", Origin: "https://eve.example" },
      body: "{\"unexpected\":true}",
    }));
    assert.equal(response.status, 422);
    assert.equal(response.headers.get("x-robots-tag"), "noindex, nofollow");
  }
});
