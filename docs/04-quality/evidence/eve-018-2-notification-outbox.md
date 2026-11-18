# EVE-018.2 — Outbox worker primitives

Tarix: 2026-11-18 (Asia/Baku). Status: **done for the EVE-018.2 worker-dispatch component scope**. Parent EVE-018 and full AT16/AT36 remain open.

## Scope

Adds server-only claim/complete/retry primitives over the existing `app_private.outbox`, protects each lease with a generation UUID, applies user quiet hours in `Asia/Baku`, and records event-key dedupe semantics. Scheduler defaults are one-minute tick, batch 25, 300-second lease, and eight attempts. Retry delays are 1, 2, 4, 8, 16, 32, and 64 minutes; the eighth failed attempt becomes `failed`. Error codes are constrained to a short lowercase code format to keep provider payload and personal data out of `last_error_code`.

The producer event queue is not a notification inbox. It does not implement recipient/channel fan-out, per-recipient scheduled-time dedupe, email/Web Push dispatch, hosted Supabase Cron activation, or the morning summary. These limits are explicit in D48 and `INTEGRATIONS.md`; they do not prove full AT36 or production delivery.

## Evidence

| Check | Result |
|---|---|
| Migration `20261118004000` + smoke `0077` on isolated synthetic PostgreSQL 16, after core schema/access policy migrations | Passed; covers service-role-only RPCs, no direct table grants, event dedupe, Asia/Baku timezone enforcement and overnight quiet end, quiet deferral, lease claim/reclaim, stale-token rejection, safe error codes, and retry delay |
| `node scripts/docs-check.mjs` | Passed: 95 Markdown files |
| `node scripts/verify-contracts.mjs` | Passed: 118 operations, 56 tables, 258 field bindings, 90 acyclic packages, 16 trace rows, 36 scenarios |
| `scripts/validate-schemas.py` | Passed: 207 schemas, 14 positive and 23 negative examples |
| `node scripts/test-prototype.mjs` | Passed: 71 VM/fake-DOM assertions; no browser/device claim |
| `git diff --check` | Passed |
| PR #154 final-head CI `#44282539247` | Passed: `docs`, PostgreSQL 17 `sql_schema`, fresh synthetic `supabase_local` |
| Merged-main CI `#44283917555` | Passed: `docs`, PostgreSQL 17 `sql_schema`, fresh synthetic `supabase_local` |
| Independent read-only QA review, final head `6595a437f9ddc232e63f8cb614861006e0621bf5` | No remaining blocker reported; reviewer did not run tests |

## Boundaries

This local SQL result used a minimal synthetic PostgreSQL 16 harness with the core schema and access-policy migrations, not the full application migration chain. Full-chain migration order after migration 039 and a fresh Supabase stack passed in the two CI runs above. No hosted Eve database, staging scheduler, SMTP, push provider, or production resource was changed or tested. This component result does not prove hosted scheduling, notification fan-out, email/Web Push delivery, or full AT16/AT36.
