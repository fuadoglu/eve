import assert from "node:assert/strict";
import test from "node:test";
import { BillingContractError, buildBillingOrderDraft, getBillingCatalog } from "../../../src/modules/billing/billing-contract.ts";

const owner = "f1000000-0000-4000-8000-000000000001";
const propertyA = "f2000000-0000-4000-8000-000000000001";
const propertyB = "f2000000-0000-4000-8000-000000000002";
const otherOwner = "f1000000-0000-4000-8000-000000000002";

function expectCode(run: () => unknown, code: string) {
  assert.throws(run, (error: unknown) => error instanceof BillingContractError && error.code === code);
}

test("server catalog matches fixed AZN minor-unit plans and keeps recurring disabled", () => {
  assert.deepEqual(getBillingCatalog(), {
    plans: [
      { key: "monthly", amount_minor: 999, currency: "AZN" },
      { key: "yearly", amount_minor: 9999, currency: "AZN" },
    ],
    first_property_trial_days: 7,
    recurring_available: false,
  });
});

test("order draft snapshots catalog prices for unique properties of one owner", () => {
  const draft = buildBillingOrderDraft({
    owner_account_id: owner,
    lines: [
      { property_id: propertyA, plan: "monthly", price_minor: 1 } as { property_id: string; plan: "monthly" },
      { property_id: propertyB, plan: "yearly" },
    ],
    owner_properties: [
      { id: propertyA, owner_account_id: owner },
      { id: propertyB, owner_account_id: owner },
    ],
  });
  assert.equal(draft.amount_minor, 10998);
  assert.equal(draft.currency, "AZN");
  assert.deepEqual(draft.lines.map(({ price_minor }) => price_minor), [999, 9999]);
  assert.equal(draft.auto_renew_opt_in, false);
});

test("foreign, missing, duplicate and malformed properties fail closed", () => {
  expectCode(() => buildBillingOrderDraft({
    owner_account_id: owner,
    lines: [{ property_id: propertyA, plan: "monthly" }],
    owner_properties: [{ id: propertyA, owner_account_id: otherOwner }],
  }), "billing_property_scope_invalid");
  expectCode(() => buildBillingOrderDraft({
    owner_account_id: owner,
    lines: [{ property_id: propertyA, plan: "monthly" }],
    owner_properties: [],
  }), "billing_property_scope_invalid");
  expectCode(() => buildBillingOrderDraft({
    owner_account_id: owner,
    lines: [{ property_id: propertyA, plan: "monthly" }, { property_id: propertyA, plan: "yearly" }],
    owner_properties: [{ id: propertyA, owner_account_id: owner }],
  }), "duplicate_property");
  expectCode(() => buildBillingOrderDraft({
    owner_account_id: owner,
    lines: [{ property_id: "not-a-uuid", plan: "monthly" }],
    owner_properties: [],
  }), "invalid_plan");
});

test("unknown plan, unsafe request sizes and unsupported recurring opt-in are rejected", () => {
  expectCode(() => buildBillingOrderDraft({
    owner_account_id: owner,
    lines: [{ property_id: propertyA, plan: "weekly" as "monthly" }],
    owner_properties: [{ id: propertyA, owner_account_id: owner }],
  }), "invalid_plan");
  expectCode(() => buildBillingOrderDraft({
    owner_account_id: owner,
    lines: Array.from({ length: 101 }, () => ({ property_id: propertyA, plan: "monthly" as const })),
    owner_properties: [{ id: propertyA, owner_account_id: owner }],
  }), "invalid_order_lines");
  expectCode(() => buildBillingOrderDraft({
    owner_account_id: owner,
    lines: [{ property_id: propertyA, plan: "monthly" }],
    owner_properties: [{ id: propertyA, owner_account_id: owner }],
    auto_renew_opt_in: true,
  }), "recurring_not_available");
});
