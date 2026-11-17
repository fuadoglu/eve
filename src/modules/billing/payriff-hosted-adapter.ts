import { getBillingCatalog, type BillingPlanKey } from "./billing-contract.ts";

export type PayriffHostedOrder = {
  id: string;
  state: "created" | "pending";
  amount_minor: number;
  currency: "AZN";
  auto_renew_opt_in: false;
  lines: readonly { property_id: string; plan: BillingPlanKey; amount_minor: number }[];
};

/** Eve-side normalized port. It deliberately does not describe Payriff's wire format. */
export type PayriffHostedTransport = {
  /** Stable Eve-side dedupe key; never serialize as a provider field without confirmed documentation. */
  createHostedCheckout(input: {
    order_id: string;
    request_key: string;
    amount_minor: number;
    currency: "AZN";
    return_url: string;
  }): Promise<unknown>;
};

export type PayriffHostedCheckout = { provider_reference: string; checkout_url: string };

export class PayriffHostedAdapterError extends Error {
  readonly code: "disabled" | "invalid_order" | "invalid_return_url" | "invalid_checkout_url" | "provider_unavailable";

  constructor(code: PayriffHostedAdapterError["code"]) {
    super(code);
    this.name = "PayriffHostedAdapterError";
    this.code = code;
  }
}

/**
 * Creates Eve's hosted-checkout boundary. A transport and provider-approved
 * checkout origins must be injected; this module does not guess Payriff URLs,
 * headers, payloads, status labels, or webhook signatures.
 */
export function createPayriffHostedAdapter(options: {
  appOrigin: string;
  allowedCheckoutOrigins: readonly string[];
  transport?: PayriffHostedTransport;
}) {
  const appOrigin = parseHttpsOrigin(options.appOrigin);
  const checkoutOrigins = new Set(options.allowedCheckoutOrigins.map((origin) => parseHttpsOrigin(origin)));
  return {
    async createOrder(order: PayriffHostedOrder, returnUrl: string): Promise<PayriffHostedCheckout> {
      if (!options.transport || checkoutOrigins.size === 0) throw new PayriffHostedAdapterError("disabled");
      if (!isPayriffHostedOrder(order)) throw new PayriffHostedAdapterError("invalid_order");
      const safeReturnUrl = parseSameOriginReturnUrl(returnUrl, appOrigin);
      if (!safeReturnUrl) throw new PayriffHostedAdapterError("invalid_return_url");
      let result: unknown;
      try {
        result = await options.transport.createHostedCheckout({
          order_id: order.id,
          request_key: order.id,
          amount_minor: order.amount_minor,
          currency: "AZN",
          return_url: safeReturnUrl,
        });
      } catch {
        throw new PayriffHostedAdapterError("provider_unavailable");
      }
      const checkout = parseNormalizedCheckout(result, checkoutOrigins);
      if (!checkout) throw new PayriffHostedAdapterError("invalid_checkout_url");
      return checkout;
    },
  };
}

function isPayriffHostedOrder(value: unknown): value is PayriffHostedOrder {
  if (!isRecord(value) || !hasOnlyKeys(value, ["id", "state", "amount_minor", "currency", "auto_renew_opt_in", "lines"])
      || !isUuid(value.id) || !["created", "pending"].includes(String(value.state))
      || !isPositiveMinor(value.amount_minor) || value.currency !== "AZN" || value.auto_renew_opt_in !== false
      || !Array.isArray(value.lines) || value.lines.length !== 1) return false;
  const line = value.lines[0];
  if (!isRecord(line) || !hasOnlyKeys(line, ["property_id", "plan", "amount_minor"])
      || !isUuid(line.property_id) || (line.plan !== "monthly" && line.plan !== "yearly")
      || !isPositiveMinor(line.amount_minor)) return false;
  const expectedPrice = getBillingCatalog().plans.find((plan) => plan.key === line.plan)?.amount_minor;
  return expectedPrice === line.amount_minor && line.amount_minor === value.amount_minor;
}

function parseNormalizedCheckout(value: unknown, allowedOrigins: ReadonlySet<string>): PayriffHostedCheckout | null {
  if (!isRecord(value) || Object.keys(value).some((key) => !["provider_reference", "checkout_url"].includes(key))
      || typeof value.provider_reference !== "string" || !/^[A-Za-z0-9._:-]{1,160}$/.test(value.provider_reference)
      || typeof value.checkout_url !== "string" || value.checkout_url.length > 2048) return null;
  try {
    const url = new URL(value.checkout_url);
    if (url.protocol !== "https:" || !allowedOrigins.has(url.origin) || url.username || url.password || url.hash) return null;
    return { provider_reference: value.provider_reference, checkout_url: url.href };
  } catch { return null; }
}

function parseSameOriginReturnUrl(value: string, appOrigin: string): string | null {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.origin !== appOrigin || url.username || url.password || url.hash || url.href.length > 2048) return null;
    return url.href;
  } catch { return null; }
}

function parseHttpsOrigin(value: string): string {
  try {
    const url = new URL(value);
    if (url.protocol !== "https:" || url.origin !== value || url.username || url.password || url.pathname !== "/" || url.search || url.hash) throw new Error();
    return url.origin;
  } catch { throw new TypeError("Payriff host policy must contain HTTPS origins only"); }
}

function isUuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
function isPositiveMinor(value: unknown): value is number { return typeof value === "number" && Number.isSafeInteger(value) && value > 0; }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null && !Array.isArray(value); }
function hasOnlyKeys(value: Record<string, unknown>, allowed: readonly string[]): boolean { return Object.keys(value).every((key) => allowed.includes(key)); }
