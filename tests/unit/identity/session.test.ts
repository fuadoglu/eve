import assert from "node:assert/strict";
import test from "node:test";
import {
  SessionProviderUnavailableError,
  SessionUnauthorizedError,
} from "../../../src/modules/identity/session-contract.ts";
import { createSessionProvider } from "../../../src/modules/identity/session-provider.ts";

test("session adapter refreshes/validates identity and uses explicit local/global scopes", async () => {
  const calls: string[] = [];
  const client = {
    auth: {
      async getUser() { calls.push("getUser"); return { data: { user: { id: "user-a" } }, error: null }; },
      async signOut({ scope }: { scope: "local" | "global" }) {
        calls.push(`signOut:${scope}`);
        return { error: null };
      },
    },
    schema(name: "api") {
      calls.push(`schema:${name}`);
      return { async rpc(rpcName: "is_my_session_active" | "revoke_my_sessions") {
        calls.push(`rpc:${rpcName}`);
        return { data: true, error: null };
      } };
    },
  };
  const provider = createSessionProvider(client);
  assert.equal(await provider.getCurrentUserId(), "user-a");
  assert.equal(await provider.isCurrentSessionActive(), true);
  await provider.signOutCurrentSession();
  await provider.revokeAllSessions();
  await provider.signOutAllSessions();
  assert.deepEqual(calls, [
    "getUser", "schema:api", "rpc:is_my_session_active", "signOut:local",
    "schema:api", "rpc:revoke_my_sessions", "signOut:global",
  ]);
});

test("session adapter treats a missing user as unauthenticated and provider outage as unavailable", async () => {
  const client = {
    auth: {
      async getUser() { return { data: { user: null }, error: { status: 401 } }; },
      async signOut() { return { error: null }; },
    },
    schema() { return { async rpc() { return { data: null, error: null }; } }; },
  };
  const provider = createSessionProvider(client);
  await assert.rejects(provider.getCurrentUserId(), SessionUnauthorizedError);
  await assert.rejects(createSessionProvider({
    ...client,
    auth: { ...client.auth, async getUser() { throw new Error("private transport detail"); } },
  }).getCurrentUserId(), SessionProviderUnavailableError);
});

test("global 404 is idempotent per the provider contract", async () => {
  const client = {
    auth: {
      async getUser() { return { data: { user: { id: "user-a" } }, error: null }; },
      async signOut() { return { error: { status: 404 } }; },
    },
    schema() { return { async rpc() { return { data: true, error: null }; } }; },
  };
  await createSessionProvider(client).signOutAllSessions();
});
