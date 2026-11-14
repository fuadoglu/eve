import assert from "node:assert/strict";
import test from "node:test";
import { applyBillingPeriod, BillingPeriodError, type ExistingBillingPeriod } from "../../../src/modules/billing/billing-periods.ts";

function period(input: Partial<ExistingBillingPeriod> & Pick<ExistingBillingPeriod, "plan" | "starts_at" | "ends_at">): ExistingBillingPeriod {
  return {
    plan: input.plan,
    starts_at: input.starts_at,
    ends_at: input.ends_at,
    anchor_day: input.anchor_day ?? 31,
    anchor_month: input.anchor_month ?? 1,
    anchor_time: input.anchor_time ?? "00:00:00",
    anchor_timezone: input.anchor_timezone ?? "Asia/Baku",
  };
}

function expectCode(run: () => unknown, code: BillingPeriodError["code"]): void {
  assert.throws(run, (error: unknown) => error instanceof BillingPeriodError && error.code === code);
}

test("monthly period keeps day 31 through February clamp and restores it in March", () => {
  const january = applyBillingPeriod({ plan: "monthly", verified_at: "2025-01-30T20:00:00.000000Z" });
  assert.equal(january.starts_at, "2025-01-30T20:00:00.000000Z");
  assert.equal(january.ends_at, "2025-02-27T20:00:00.000000Z");
  assert.equal(january.anchor_day, 31);
  assert.equal(january.anchor_month, 1);

  const february = applyBillingPeriod({
    plan: "monthly",
    verified_at: "2025-02-01T00:00:00.000000Z",
    previous_period: january,
  });
  assert.equal(february.starts_at, january.ends_at);
  assert.equal(february.ends_at, "2025-03-30T20:00:00.000000Z");
  assert.equal(february.anchor_day, 31);
});

test("month end follows the leap-year calendar and preserves the original anchor", () => {
  const january = applyBillingPeriod({ plan: "monthly", verified_at: "2024-01-30T20:00:00.000000Z" });
  assert.equal(january.ends_at, "2024-02-28T20:00:00.000000Z");
  const february = applyBillingPeriod({ plan: "monthly", verified_at: january.ends_at, previous_period: january });
  assert.equal(february.ends_at, "2024-03-30T20:00:00.000000Z");
  assert.equal(february.anchor_day, 31);
});

test("yearly February 29 anchor clamps in non-leap years and returns in leap year", () => {
  const first = applyBillingPeriod({ plan: "yearly", verified_at: "2024-02-28T20:00:00.000000Z" });
  assert.equal(first.anchor_day, 29);
  assert.equal(first.ends_at, "2025-02-27T20:00:00.000000Z");
  const second = applyBillingPeriod({ plan: "yearly", verified_at: first.ends_at, previous_period: first });
  const third = applyBillingPeriod({ plan: "yearly", verified_at: second.ends_at, previous_period: second });
  const fourth = applyBillingPeriod({ plan: "yearly", verified_at: third.ends_at, previous_period: third });
  assert.equal(second.ends_at, "2026-02-27T20:00:00.000000Z");
  assert.equal(third.ends_at, "2027-02-27T20:00:00.000000Z");
  assert.equal(fourth.ends_at, "2028-02-28T20:00:00.000000Z");
  assert.equal(fourth.anchor_day, 29);
});

test("period starts at the latest verified-payment, previous-period and trial boundary", () => {
  const existing = period({
    plan: "monthly",
    starts_at: "2025-01-30T20:00:00.000000Z",
    ends_at: "2025-02-27T20:00:00.000000Z",
    anchor_day: 31,
    anchor_month: 1,
  });
  const earlyRenewal = applyBillingPeriod({
    plan: "monthly", verified_at: "2025-02-01T00:00:00.000000Z", previous_period: existing,
  });
  assert.equal(earlyRenewal.starts_at, existing.ends_at);

  const afterTrial = applyBillingPeriod({
    plan: "monthly",
    verified_at: "2025-02-01T00:00:00.000000Z",
    trial_ends_at: "2025-02-10T20:00:00.000000Z",
  });
  assert.equal(afterTrial.starts_at, "2025-02-10T20:00:00.000000Z");
  assert.equal(afterTrial.ends_at, "2025-03-10T20:00:00.000000Z");
});

test("plan switch queues at the current boundary and resets annual month anchor there", () => {
  const monthly = period({
    plan: "monthly", starts_at: "2025-01-30T20:00:00.000000Z", ends_at: "2025-02-27T20:00:00.000000Z",
    anchor_day: 31, anchor_month: 1, anchor_time: "00:00:00",
  });
  const yearly = applyBillingPeriod({
    plan: "yearly", verified_at: "2025-02-01T00:00:00.000000Z", previous_period: monthly,
  });
  assert.equal(yearly.starts_at, monthly.ends_at);
  assert.equal(yearly.anchor_month, 2);
  assert.equal(yearly.anchor_day, 31);
  assert.equal(yearly.ends_at, "2026-02-27T20:00:00.000000Z");
});

test("Baku local anchor time and millisecond precision are preserved across UTC conversion", () => {
  const result = applyBillingPeriod({
    plan: "monthly", verified_at: "2025-01-30T20:15:30.125Z",
  });
  assert.equal(result.starts_at, "2025-01-30T20:15:30.125000Z");
  assert.equal(result.anchor_time, "00:15:30.125");
  assert.equal(result.ends_at, "2025-02-27T20:15:30.125000Z");
  assert.equal(result.anchor_timezone, "Asia/Baku");
});

test("PostgreSQL microsecond timestamp and anchor precision are preserved", () => {
  const result = applyBillingPeriod({ plan: "monthly", verified_at: "2025-01-30T20:15:30.123456Z" });
  assert.equal(result.starts_at, "2025-01-30T20:15:30.123456Z");
  assert.equal(result.anchor_time, "00:15:30.123456");
  assert.equal(result.ends_at, "2025-02-27T20:15:30.123456Z");
});

test("invalid plan, timestamps, anchor fields and unsupported timezone fail closed", () => {
  expectCode(() => applyBillingPeriod({ plan: "weekly" as "monthly", verified_at: "2025-01-01T00:00:00Z" }), "invalid_plan");
  expectCode(() => applyBillingPeriod({ plan: "monthly", verified_at: "2025-02-30T00:00:00Z" }), "invalid_timestamp");
  expectCode(() => applyBillingPeriod({ plan: "monthly", verified_at: "not-a-date" }), "invalid_timestamp");
  expectCode(() => applyBillingPeriod({
    plan: "monthly", verified_at: "2025-01-01T00:00:00Z",
    previous_period: period({
      plan: "monthly", starts_at: "2025-01-01T00:00:00Z", ends_at: "2025-02-01T00:00:00Z",
      anchor_day: 32,
    }),
  }), "invalid_anchor");
  expectCode(() => applyBillingPeriod({
    plan: "monthly", verified_at: "2025-01-01T00:00:00Z",
    previous_period: period({
      plan: "monthly", starts_at: "2025-01-01T00:00:00Z", ends_at: "2025-02-01T00:00:00Z",
      anchor_timezone: "UTC" as "Asia/Baku",
    }),
  }), "invalid_anchor");
  expectCode(() => applyBillingPeriod({
    plan: "monthly", verified_at: "2025-01-01T00:00:00Z",
    previous_period: period({
      plan: "monthly", starts_at: "2025-02-01T00:00:00Z", ends_at: "2025-02-01T00:00:00Z",
    }),
  }), "invalid_timestamp");
});
