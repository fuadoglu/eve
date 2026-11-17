import assert from "node:assert/strict";
import test from "node:test";
import { createPayriffHostedAdapter, PayriffHostedAdapterError, type PayriffHostedOrder } from "../../../src/modules/billing/payriff-hosted-adapter.ts";

const order: PayriffHostedOrder = {
  id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  state: "created",
  amount_minor: 999,
  currency: "AZN",
  auto_renew_opt_in: false,
  lines: [{ property_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", plan: "monthly", amount_minor: 999 }],
};
const returnUrl = "https://eve.example/billing/return?order=aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const allowed = ["https://checkout.merchant.example"];

test("hosted checkout sends only the validated Eve order to the injected normalized transport", async () => {
  const seen: unknown[] = [];
  const adapter = createPayriffHostedAdapter({ appOrigin: "https://eve.example", allowedCheckoutOrigins: allowed,
    transport: { async createHostedCheckout(input) { seen.push(input); return { provider_reference: "merchant-ref-1", checkout_url: "https://checkout.merchant.example/pay/1" }; } },
  });
  assert.deepEqual(await adapter.createOrder(order, returnUrl), {
    provider_reference: "merchant-ref-1", checkout_url: "https://checkout.merchant.example/pay/1",
  });
  await adapter.createOrder(order, returnUrl);
  assert.deepEqual(seen, [
    { order_id: order.id, request_key: order.id, amount_minor: 999, currency: "AZN", return_url: returnUrl },
    { order_id: order.id, request_key: order.id, amount_minor: 999, currency: "AZN", return_url: returnUrl },
  ]);
});

test("checkout fails closed if transport or verified checkout-origin policy is absent", async () => {
  const disabled = createPayriffHostedAdapter({ appOrigin: "https://eve.example", allowedCheckoutOrigins: [] });
  await assert.rejects(disabled.createOrder(order, returnUrl), (error) => error instanceof PayriffHostedAdapterError && error.code === "disabled");
  assert.throws(() => createPayriffHostedAdapter({ appOrigin: "https://eve.example", allowedCheckoutOrigins: ["http://checkout.example"] }), TypeError);
});

test("invalid billing state, amount, price, line count, recurring option and unknown fields are rejected before transport", async () => {
  let calls = 0;
  const adapter = createPayriffHostedAdapter({ appOrigin: "https://eve.example", allowedCheckoutOrigins: allowed,
    transport: { async createHostedCheckout() { calls++; return { provider_reference: "ref", checkout_url: "https://checkout.merchant.example/pay" }; } },
  });
  const invalid: unknown[] = [
    { ...order, state: "verified_paid" },
    { ...order, amount_minor: 1000 },
    { ...order, lines: [{ ...order.lines[0]!, amount_minor: 1000 }] },
    { ...order, lines: [...order.lines, order.lines[0]] },
    { ...order, auto_renew_opt_in: true },
    { ...order, invented: true },
    { ...order, lines: [{ ...order.lines[0]!, guest_name: "Guest" }] },
  ];
  for (const candidate of invalid) {
    await assert.rejects(adapter.createOrder(candidate as PayriffHostedOrder, returnUrl), (error) => error instanceof PayriffHostedAdapterError && error.code === "invalid_order");
  }
  assert.equal(calls, 0);
});

test("return URL must stay on the configured app origin and is checked before transport", async () => {
  let calls = 0;
  const adapter = createPayriffHostedAdapter({ appOrigin: "https://eve.example", allowedCheckoutOrigins: allowed,
    transport: { async createHostedCheckout() { calls++; return {}; } },
  });
  for (const value of ["http://eve.example/billing/return", "https://attacker.example/billing/return", "https://eve.example@attacker.example/return", "https://eve.example/return#token"]) {
    await assert.rejects(adapter.createOrder(order, value), (error) => error instanceof PayriffHostedAdapterError && error.code === "invalid_return_url");
  }
  assert.equal(calls, 0);
});

test("only an HTTPS checkout URL from the injected merchant allowlist is returned", async () => {
  const invalid = [
    { provider_reference: "ref", checkout_url: "http://checkout.merchant.example/pay" },
    { provider_reference: "ref", checkout_url: "https://other.example/pay" },
    { provider_reference: "ref", checkout_url: "https://user:password@checkout.merchant.example/pay" },
    { provider_reference: "ref", checkout_url: "https://checkout.merchant.example/pay#secret" },
    { provider_reference: "ref", checkout_url: "https://checkout.merchant.example/pay", extra: true },
    { provider_reference: "ref with space", checkout_url: "https://checkout.merchant.example/pay" },
  ];
  for (const value of invalid) {
    const adapter = createPayriffHostedAdapter({ appOrigin: "https://eve.example", allowedCheckoutOrigins: allowed,
      transport: { async createHostedCheckout() { return value; } },
    });
    await assert.rejects(adapter.createOrder(order, returnUrl), (error) => error instanceof PayriffHostedAdapterError && error.code === "invalid_checkout_url");
  }
});

test("transport errors are mapped to a safe provider error without raw detail", async () => {
  const adapter = createPayriffHostedAdapter({ appOrigin: "https://eve.example", allowedCheckoutOrigins: allowed,
    transport: { async createHostedCheckout() { throw new Error("secret provider response body"); } },
  });
  await assert.rejects(adapter.createOrder(order, returnUrl), (error) => {
    assert.equal(error instanceof PayriffHostedAdapterError, true);
    assert.equal((error as Error).message.includes("secret provider response body"), false);
    return (error as PayriffHostedAdapterError).code === "provider_unavailable";
  });
});
