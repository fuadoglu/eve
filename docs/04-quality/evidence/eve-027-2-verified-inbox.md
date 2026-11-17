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

PR #138 was squash-merged as `6aa07d3c15b6508b3db20e7e092de28d8efd6828`. Final-head CI [#44163636041](https://github.com/fuadoglu/eve/actions/runs/44163636041) and merged-main CI [#44164230330](https://github.com/fuadoglu/eve/actions/runs/44164230330) passed `docs`, PostgreSQL 17 `sql_schema`, and synthetic `supabase_local`. The initial run found that the exact private RLS policy count had not been increased for the three new event policies; the expected inventory was corrected to 147 and the synchronized final run passed. Local normalized DTO tests passed 2/2 on Node 24.5.0 using native type stripping. `node scripts/docs-check.mjs`, `node scripts/verify-contracts.mjs`, `node scripts/test-prototype.mjs` (71 assertions with its documented fake-DOM limit), and `git diff --check` passed. Independent review found no blocker in migration, event transaction, deduplication, RLS/API grants, TypeScript boundary, tests, or D43 docs; it did not run tests. Local Python schema validation could not run because `jsonschema` is not installed; local Docker is unavailable. SQL fixtures are synthetic.

## Limitations

This boundary trusts its server-only caller to have completed provider verification. It is not wired to an inbound route and does not establish Payriff event key/transaction ID formats, merchant identity mapping, endpoint, auth, signature verification, status lookup, provider idempotency, sandbox behavior, hosted DB application, or production readiness. Closed-order recovery is manual-review output only; an operator workflow is not included.

## Package closeout

EVE-027.2 is `done` for the internal normalized inbox and synthetic PostgreSQL/API acceptance scope. Provider signature/status verification, inbound route wiring, Payriff sandbox, hosted database migration, backup/restore, and production release gates remain open.
