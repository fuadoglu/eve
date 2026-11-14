import assert from "node:assert/strict";
import test from "node:test";
import { applyBillingPeriod } from "../../../src/modules/billing/billing-periods.ts";

test("trial purchase, leap anchor, annual renewal and queued monthly switch preserve one calendar timeline", () => {
  const trialEnd = "2024-02-28T20:00:00.123456Z"; // 2024-02-29 00:00:00.123456 Asia/Baku
  const initialAnnual = applyBillingPeriod({
    plan: "yearly",
    verified_at: "2024-02-01T12:00:00Z",
    trial_ends_at: trialEnd,
  });
  assert.equal(initialAnnual.starts_at, trialEnd);
  assert.equal(initialAnnual.ends_at, "2025-02-27T20:00:00.123456Z");
  assert.equal(initialAnnual.anchor_day, 29);
  assert.equal(initialAnnual.anchor_month, 2);
  assert.equal(initialAnnual.anchor_time, "00:00:00.123456");

  const earlyAnnualRenewal = applyBillingPeriod({
    plan: "yearly",
    verified_at: "2024-11-15T09:30:00Z",
    previous_period: initialAnnual,
  });
  assert.equal(earlyAnnualRenewal.starts_at, initialAnnual.ends_at);
  assert.equal(earlyAnnualRenewal.ends_at, "2026-02-27T20:00:00.123456Z");
  assert.equal(earlyAnnualRenewal.anchor_day, 29);
  assert.equal(earlyAnnualRenewal.anchor_month, 2);

  const queuedMonthly = applyBillingPeriod({
    plan: "monthly",
    verified_at: "2025-12-01T00:00:00Z",
    previous_period: earlyAnnualRenewal,
  });
  assert.equal(queuedMonthly.starts_at, earlyAnnualRenewal.ends_at);
  assert.equal(queuedMonthly.ends_at, "2026-03-28T20:00:00.123456Z");
  assert.equal(queuedMonthly.anchor_day, 29);
  assert.equal(queuedMonthly.anchor_month, 2);

  const nextMonthly = applyBillingPeriod({
    plan: "monthly",
    verified_at: queuedMonthly.ends_at,
    previous_period: queuedMonthly,
  });
  assert.equal(nextMonthly.ends_at, "2026-04-28T20:00:00.123456Z");
  assert.equal(nextMonthly.anchor_day, 29);
  assert.equal(nextMonthly.anchor_month, 2);
});

test("scenario rejects a non-positive stored period instead of extending from corrupt history", () => {
  assert.throws(() => applyBillingPeriod({
    plan: "monthly",
    verified_at: "2025-01-01T00:00:00Z",
    previous_period: {
      plan: "monthly",
      starts_at: "2025-02-01T00:00:00Z",
      ends_at: "2025-02-01T00:00:00Z",
      anchor_day: 31,
      anchor_month: 1,
      anchor_time: "00:00:00",
      anchor_timezone: "Asia/Baku",
    },
  }), (error: unknown) => typeof error === "object" && error !== null
    && "code" in error && error.code === "invalid_timestamp");
});
