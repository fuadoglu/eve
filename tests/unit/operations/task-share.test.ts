import assert from "node:assert/strict";
import test from "node:test";
import { copyTaskShareMessage, createWhatsAppShareUrl, formatTaskShareExpiry } from "../../../src/modules/operations/task-share.ts";

test("WhatsApp handoff uses a fixed host and encodes the complete message", () => {
  const message = "Tapşırığı açın: https://eve.example/s/secret?x=1&y=2";
  const result = new URL(createWhatsAppShareUrl(message));
  assert.equal(result.origin, "https://wa.me");
  assert.equal(result.searchParams.get("text"), message);
  assert.throws(() => createWhatsAppShareUrl(" "), /invalid_task_share_message/);
  assert.throws(() => createWhatsAppShareUrl("x".repeat(3001)), /invalid_task_share_message/);
});

test("clipboard reports success only after the browser acknowledges the write", async () => {
  const message = "Task link";
  let written = "";
  assert.equal(await copyTaskShareMessage({ writeText: async (value) => { written = value; } }, message), "copied");
  assert.equal(written, message);
  assert.equal(await copyTaskShareMessage({ writeText: async () => { throw new Error("denied"); } }, message), "unavailable");
  assert.equal(await copyTaskShareMessage(undefined, message), "unavailable");
  assert.equal(await copyTaskShareMessage({ writeText: async () => {} }, "  "), "unavailable");
});

test("expiry formatting rejects invalid timestamps without exposing malformed text", () => {
  assert.match(formatTaskShareExpiry("2026-11-20T10:00:00.000Z"), /2026/);
  assert.equal(formatTaskShareExpiry("invalid"), "");
});
