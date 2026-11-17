import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import { handleCreateTaskLink, handleReadScopedTask, handleRevokeTaskLink,
  handleTransitionScopedTask, TaskLinkApiError } from "../../../src/modules/operations/task-link-http.ts";

const token = "a".repeat(43);
const tokenHash = createHash("sha256").update(token).digest("hex");
const taskId = "f3000000-0000-4000-8000-000000000021";
const linkId = "f4000000-0000-4000-8000-000000000021";
const scoped = { task_id: taskId, property_label: "Ev", title: "Tapşırıq", due_at: "2026-11-19T12:00:00Z",
  state: "open", version: 1 };
const url = `https://eve.example/api/v1/s/${token}/task`;
const cookie = `eve_scope=${tokenHash}`;

test("GET/prefetch is read only and requires the exact scoped cookie", async () => {
  let reads = 0;
  const read = async () => { reads++; return scoped; };
  const noCookie = await handleReadScopedTask(new Request(url), token, read);
  assert.equal(noCookie.status, 404);
  assert.equal(reads, 0);
  const wrongCookie = await handleReadScopedTask(new Request(url, { headers: { cookie: `eve_scope=${"b".repeat(64)}` } }), token, read);
  assert.equal(wrongCookie.status, 404);
  assert.equal(reads, 0);
  const good = await handleReadScopedTask(new Request(url, { headers: { cookie } }), token, read);
  assert.equal(good.status, 200);
  assert.equal(reads, 1);
  assert.equal((await good.json()).data.state, "open");
  assert.equal(good.headers.get("cache-control"), "private, no-store");
  assert.equal(good.headers.get("referrer-policy"), "no-referrer");
});

test("POST needs explicit same-origin action; revoke and expiry fail closed", async () => {
  let writes = 0;
  const transition = async () => { writes++; return { ...scoped, state: "accepted", version: 2 }; };
  const body = JSON.stringify({ expected_version: 1, claimed_name: "Usta" });
  const baseHeaders = { cookie, "Content-Type": "application/json", "Idempotency-Key": "task-accept-key-00001" };
  const prefetch = await handleTransitionScopedTask(new Request(url, { method: "POST", headers: baseHeaders, body }), token, "accept", transition);
  assert.equal(prefetch.status, 403);
  assert.equal(writes, 0);
  const accepted = await handleTransitionScopedTask(new Request(url, { method: "POST",
    headers: { ...baseHeaders, Origin: "https://eve.example" }, body }), token, "accept", transition);
  assert.equal(accepted.status, 200);
  assert.equal(writes, 1);
  assert.equal((await accepted.json()).data.state, "accepted");
  const revoked = await handleReadScopedTask(new Request(url, { headers: { cookie } }), token,
    async () => { throw new TaskLinkApiError("LINK_EXPIRED"); });
  assert.equal(revoked.status, 410);
  assert.equal(revoked.headers.get("cache-control"), "private, no-store");
});

test("task share returns only acknowledged link and no sent claim", async () => {
  const request = new Request(`https://eve.example/api/v1/tasks/${taskId}/share-link`, { method: "POST",
    headers: { Origin: "https://eve.example", "Content-Type": "application/json", "Idempotency-Key": "task-share-key-00001" },
    body: "{}" });
  const created = await handleCreateTaskLink(request, taskId,
    async () => ({ link_id: linkId, token, expires_at: "2026-11-20T12:00:00Z", replayed: false }));
  assert.equal(created.status, 201);
  const data = (await created.json()).data;
  assert.equal(data.delivery_state, "not_tracked");
  assert.equal(data.url, `https://eve.example/s/${token}`);
  assert.ok(!JSON.stringify(data).includes("göndərildi"));
});

test("owner revoke is idempotent at HTTP boundary and rejects foreign origin", async () => {
  let calls = 0;
  const revoke = async () => { calls++; return { accepted: true }; };
  const path = `https://eve.example/api/v1/access-links/${linkId}`;
  const headers = { "Content-Type": "application/json", "Idempotency-Key": "task-revoke-key-0001" };
  const foreign = await handleRevokeTaskLink(new Request(path, { method: "DELETE", headers: { ...headers, Origin: "https://other.example" }, body: "{}" }), linkId, revoke);
  assert.equal(foreign.status, 403);
  assert.equal(calls, 0);
  const own = await handleRevokeTaskLink(new Request(path, { method: "DELETE", headers: { ...headers, Origin: "https://eve.example" }, body: "{}" }), linkId, revoke);
  assert.equal(own.status, 200);
  assert.equal(calls, 1);
});
