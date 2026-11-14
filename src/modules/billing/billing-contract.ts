export type BillingPlanKey = "monthly" | "yearly";

export type BillingPlan = {
  key: BillingPlanKey;
  amount_minor: number;
  currency: "AZN";
};

export type BillingCatalog = {
  plans: readonly BillingPlan[];
  first_property_trial_days: 7;
  recurring_available: false;
};

export type OrderLineInput = {
  property_id: string;
  plan: BillingPlanKey;
};

export type SameOwnerProperty = {
  id: string;
  owner_account_id: string;
};

export type BillingOrderDraft = {
  owner_account_id: string;
  currency: "AZN";
  amount_minor: number;
  auto_renew_opt_in: false;
  lines: Array<OrderLineInput & { owner_account_id: string; price_minor: number }>;
};

export class BillingContractError extends Error {
  readonly code: "invalid_order_lines" | "invalid_plan" | "duplicate_property" | "billing_property_scope_invalid" | "recurring_not_available" | "unsafe_total";

  constructor(code: BillingContractError["code"]) {
    super(code);
    this.name = "BillingContractError";
    this.code = code;
  }
}

const PLAN_PRICES: Readonly<Record<BillingPlanKey, number>> = Object.freeze({
  monthly: 999,
  yearly: 9999,
});

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isBillingPlanKey(value: unknown): value is BillingPlanKey {
  return typeof value === "string" && Object.hasOwn(PLAN_PRICES, value);
}

/** Server-owned catalog matching configuration.json and BILLING-FINANCE.md. */
export function getBillingCatalog(): BillingCatalog {
  return {
    plans: [
      { key: "monthly", amount_minor: PLAN_PRICES.monthly, currency: "AZN" },
      { key: "yearly", amount_minor: PLAN_PRICES.yearly, currency: "AZN" },
    ],
    first_property_trial_days: 7,
    recurring_available: false,
  };
}

/** Build a server-side order draft from properties already loaded for the current owner. */
export function buildBillingOrderDraft(input: {
  owner_account_id: string;
  lines: readonly OrderLineInput[];
  owner_properties: readonly SameOwnerProperty[];
  auto_renew_opt_in?: boolean;
}): BillingOrderDraft {
  if (!UUID_PATTERN.test(input.owner_account_id) || !Array.isArray(input.lines)
      || !Array.isArray(input.owner_properties)
      || input.lines.length < 1 || input.lines.length > 100) {
    throw new BillingContractError("invalid_order_lines");
  }
  if (input.auto_renew_opt_in === true) {
    throw new BillingContractError("recurring_not_available");
  }

  const owned = new Map(input.owner_properties.map((property) => [property.id.toLowerCase(), property]));
  const seen = new Set<string>();
  const lines = input.lines.map((line) => {
    if (!line || !UUID_PATTERN.test(line.property_id) || !isBillingPlanKey(line.plan)) {
      throw new BillingContractError("invalid_plan");
    }
    const plan = line.plan as BillingPlanKey;
    const propertyId = line.property_id.toLowerCase();
    if (seen.has(propertyId)) throw new BillingContractError("duplicate_property");
    seen.add(propertyId);
    const property = owned.get(propertyId);
    if (!property || property.owner_account_id.toLowerCase() !== input.owner_account_id.toLowerCase()) {
      throw new BillingContractError("billing_property_scope_invalid");
    }
    return {
      property_id: line.property_id,
      plan,
      owner_account_id: input.owner_account_id,
      price_minor: PLAN_PRICES[plan],
    };
  });

  const amountMinor = lines.reduce((total, line) => total + line.price_minor, 0);
  if (!Number.isSafeInteger(amountMinor) || amountMinor <= 0) {
    throw new BillingContractError("unsafe_total");
  }
  return {
    owner_account_id: input.owner_account_id,
    currency: "AZN",
    amount_minor: amountMinor,
    auto_renew_opt_in: false,
    lines,
  };
}
