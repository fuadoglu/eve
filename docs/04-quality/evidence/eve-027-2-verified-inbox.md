# EVE-027.2 — Normalized verified billing event inbox

## Scope

Adds a server-only service-role bridge that accepts Eve-normalized input only after a trusted provider-verification adapter has verified it. It records an allowlisted redacted event, checks order amount/currency and provider transaction uniqueness, deduplicates `(provider,event_key)`, and invokes the existing entitlement transaction atomically. It does not parse Payriff payloads, verify signatures/status, expose a public webhook/HTTP route, or make a provider request.

## Acceptance evidence

- A valid event moves a pending monthly order through `verified_paid` to `entitlement_applied` and records exactly one subscription period.
- Replaying the same event key/payload returns the same inbox row and does not add an entitlement. A distinct event key for the same normalized provider transaction is treated as an entitlement replay and does not extend the period twice.
- Reusing an event key with a changed normalized payload conflicts. Amount/currency mismatch is recorded as rejected and creates no entitlement.
- A verified event for an expired/closed order (or after `expires_at`) is retained as verified and returns `manual_review_required`; the order/entitlement is not changed automatically (D43).
- Authenticated/anon cannot execute the service bridge or read the inbox table. The server bridge is the only client-visible `api` function addition and is service-role-only.
- PostgreSQL artifact: migration `20261117003100_eve_verified_billing_event.sql` and smoke `supabase/tests/0272_verified_billing_event_smoke.sql`; CI runs both plus RLS and API allowlist checks.
- TypeScript boundary: `src/modules/billing/verified-billing-event.ts` and server-only `supabase-verified-billing-events.ts`; unit contract tests are in `tests/unit/billing/verified-billing-event.test.ts`.

## Verification state

Local normalized DTO contract tests passed 2/2 using Node 24.5.0 with native type stripping. `node scripts/docs-check.mjs`, `node scripts/verify-contracts.mjs`, and `node scripts/test-prototype.mjs` passed; the prototype smoke reports 71 assertions with its documented fake-DOM limit. `git diff --check` passed. The independent read-only review found no blocker in migration, event transaction, deduplication, RLS/API grants, TypeScript boundary, tests, or D43 docs; it did not run tests. PR CI and merged-main CI are pending. Local Python schema validation could not run because `jsonschema` is not installed; local Docker is unavailable. All SQL smoke records are synthetic.

## Limitations

This boundary trusts its server-only caller to have completed provider verification. It is not wired to an inbound route and does not establish Payriff event key/transaction ID formats, merchant identity mapping, endpoint, auth, signature verification, status lookup, provider idempotency, sandbox behavior, hosted DB application, or production readiness. Closed-order recovery is manual-review output only; an operator workflow is not included.
