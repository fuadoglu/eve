import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import {
  createManagerInviteToken,
  hashManagerInviteToken,
} from "../../../src/modules/access/invite-token.ts";

test("manager invite token is high entropy, URL safe, and stored only as SHA-256 hex", () => {
  const first = createManagerInviteToken();
  const second = createManagerInviteToken();

  assert.match(first.rawToken, /^[A-Za-z0-9_-]{43}$/);
  assert.match(first.tokenHash, /^[0-9a-f]{64}$/);
  assert.notEqual(first.rawToken, second.rawToken);
  assert.equal(
    first.tokenHash,
    createHash("sha256").update(first.rawToken, "utf8").digest("hex"),
  );
  assert.equal(hashManagerInviteToken(first.rawToken), first.tokenHash);
});

test("manager invite token hashing rejects malformed or undersized bearer values", () => {
  for (const value of ["", "x".repeat(42), "x".repeat(43) + "=", "x".repeat(257), "a/b".repeat(15)]) {
    assert.throws(() => hashManagerInviteToken(value), {
      name: "TypeError",
      message: "invalid_manager_invite_token",
    });
  }
});
