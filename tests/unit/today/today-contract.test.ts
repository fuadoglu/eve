import assert from "node:assert/strict";
import test from "node:test";
import { parseTodayEnvelope, parseTodayProjection } from "../../../src/modules/today/today-contract.ts";

const card = {
  id: "f8000000-0000-4000-8000-000000000001",
  kind: "arrival",
  property_id: "f8000000-0000-4000-8000-000000000002",
  property_label: "Sahil",
  title: "Giriş · Sintetik qonaq",
  due_at: "2026-11-16T11:00:00.000Z",
  amount_minor: null,
  action: "check_in",
  target_id: "f8000000-0000-4000-8000-000000000003",
};

test("Today projection accepts a documented card and Asia/Baku date", () => {
  assert.deepEqual(parseTodayProjection({ local_date: "2026-11-16", timezone: "Asia/Baku", cards: [card] }), {
    local_date: "2026-11-16", timezone: "Asia/Baku", cards: [card],
  });
});

test("Today envelope requires a UUID request id", () => {
  assert.throws(() => parseTodayEnvelope({ data: { local_date: "2026-11-16", timezone: "Asia/Baku", cards: [] }, meta: { request_id: "invalid" } }), /invalid_today_envelope/);
});

test("Today projection rejects unsupported fields, kinds and duplicate card ids", () => {
  assert.throws(() => parseTodayProjection({ local_date: "2026-02-30", timezone: "Asia/Baku", cards: [] }), /invalid_today_projection/);
  assert.throws(() => parseTodayProjection({ local_date: "2026-11-16", timezone: "Asia/Baku", cards: [{ ...card, kind: "secret" }] }), /invalid_today_card/);
  assert.throws(() => parseTodayProjection({ local_date: "2026-11-16", timezone: "Asia/Baku", cards: [card, card] }), /duplicate_today_card_id/);
});

test("Today projection enforces safe integer money and UUID target ids", () => {
  assert.throws(() => parseTodayProjection({ local_date: "2026-11-16", timezone: "Asia/Baku", cards: [{ ...card, amount_minor: Number.MAX_SAFE_INTEGER + 1 }] }), /invalid_today_card/);
  assert.throws(() => parseTodayProjection({ local_date: "2026-11-16", timezone: "Asia/Baku", cards: [{ ...card, target_id: "not-a-uuid" }] }), /invalid_today_card/);
});
