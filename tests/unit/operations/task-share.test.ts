import assert from "node:assert/strict";
import test from "node:test";
import { buildTaskShareMessage, copyTaskShareMessage, createWhatsAppShareUrl, formatTaskShareExpiry } from "../../../src/modules/operations/task-share.ts";

test("WhatsApp handoff uses a fixed host and encodes the complete message", () => {
  const message = "Tapşırığı açın: https://eve.example/s/secret?x=1&y=2";
  const href = createWhatsAppShareUrl(message);
  assert.ok(href);
  assert.ok(href.length <= 2048);
  const result = new URL(href);
  assert.equal(result.origin, "https://wa.me");
  assert.equal(result.searchParams.get("text"), message);
  assert.equal(createWhatsAppShareUrl(" "), null);
  assert.equal(createWhatsAppShareUrl("x".repeat(3001)), null);
  assert.equal(createWhatsAppShareUrl("😀".repeat(200)), null);
});

test("copy fallback always carries the scoped URL within the contract limit", () => {
  const message = buildTaskShareMessage("Tapşırığı açın", "https://eve.example/s/opaque");
  assert.equal(message, "Tapşırığı açın\nhttps://eve.example/s/opaque");
  assert.equal(buildTaskShareMessage(message, "https://eve.example/s/opaque"), message);
  assert.equal(buildTaskShareMessage("x".repeat(3000), "https://eve.example/s/opaque"), "https://eve.example/s/opaque");
  assert.ok(buildTaskShareMessage("x".repeat(3000), "https://eve.example/s/opaque").length <= 3000);
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
