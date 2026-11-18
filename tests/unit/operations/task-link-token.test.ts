import assert from "node:assert/strict";
import test from "node:test";
import { deriveTaskLinkToken, sha256 } from "../../../src/modules/operations/task-link-token.ts";

test("task link token is deterministic, 256-bit and scoped by actor/task/key", () => {
  const secret = "a".repeat(64);
  const first = deriveTaskLinkToken(secret, "actor-a", "task-a", "idempotency-key-0001");
  assert.equal(first, deriveTaskLinkToken(secret, "actor-a", "task-a", "idempotency-key-0001"));
  assert.match(first, /^[A-Za-z0-9_-]{43}$/);
  assert.notEqual(first, deriveTaskLinkToken(secret, "actor-b", "task-a", "idempotency-key-0001"));
  assert.notEqual(first, deriveTaskLinkToken(secret, "actor-a", "task-b", "idempotency-key-0001"));
  assert.notEqual(first, deriveTaskLinkToken(secret, "actor-a", "task-a", "idempotency-key-0002"));
  assert.match(sha256(first), /^[0-9a-f]{64}$/);
  assert.throws(() => deriveTaskLinkToken("short", "actor-a", "task-a", "idempotency-key-0001"));
});
