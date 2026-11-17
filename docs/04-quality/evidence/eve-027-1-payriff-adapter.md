# EVE-027.1 — Payriff hosted checkout adapter boundary

## Scope

Adds Eve's internal `createOrder(order, returnUrl)` boundary for hosted checkout. It validates the server-owned single-property billing order and catalog amount, rejects recurring opt-in, constrains the return URL to the configured Eve origin, and accepts only an HTTPS checkout URL from explicitly injected merchant-approved origins. The transport is an injected normalized Eve-side port and receives a stable Eve order ID as its request key; it must not be mapped to an unverified provider field.

## Verification

- `pnpm test:billing` passed 20/20, including positive transport mapping and negative order state/amount/line-count/recurring/return URL/checkout origin/credentials/hash/unknown-field/transport failure cases. Retries pass the same internal order ID as the transport request key; this proves stable Eve input only.
- `pnpm typecheck` passed.
- `pnpm build`, `node scripts/docs-check.mjs`, `node scripts/verify-contracts.mjs`, schema validation (207 schemas; 14 positive/23 negative), storage config, prototype smoke (71 synthetic assertions), and `git diff --check` passed.
- Independent QA review found no local adapter-scope blocker; reviewer did not run tests. PR CI remains pending.

All transport fixtures use synthetic `.example` origins. Tests do not call Payriff or represent provider sandbox evidence.

## Limits

The Payriff merchant API version, endpoint, auth header, wire payload, response schema, status mapping, provider-side idempotency behavior and webhook verification remain unconfirmed under EXT04/EXT05. This module deliberately does not invent them and is not wired into a live checkout route. The internal request key keeps retries stable at the Eve boundary; it does not prove the provider will deduplicate them. No payment, browser return or entitlement is verified here; checkout stays unavailable unless an operator injects a concrete approved transport and origin policy. EVE-027.2 owns status lookup/reconcile and EVE-027.3 owns provider sandbox/forgery/replay acceptance.
