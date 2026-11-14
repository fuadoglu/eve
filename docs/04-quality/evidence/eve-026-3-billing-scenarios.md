# EVE-026.3 — Trial/leap/month-end/plan transition integration

Status: **implementation branch in progress; package remains open until independent review, PostgreSQL 17 CI, and merge**.

## Implemented on `feat/EVE-026-3-billing-scenarios`

- `app_private.apply_verified_billing_order` consumes only an existing `verified_paid` order. It accepts no client timestamp or anchor, enforces the current single-property checkout boundary, validates AZN total, and serializes application with order → property → subscription row locks.
- One transaction inserts the unique subscription period, updates current entitlement and Asia/Baku anchor projection, marks the order line, and transitions the order to `entitlement_applied`. A retry returns the same period with `replay=true`.
- The service-role-only API bridge and server adapter do not expose billing table access to browser roles. They do not perform Payriff verification; the provider adapter must set the order to `verified_paid` through its separately owned verification contract.
- PostgreSQL smoke covers trial purchase at a February 29 Baku boundary, annual early renewal, annual-to-monthly switch, January 31→February clamp→March restoration, exact microseconds, replay, unverified order, total mismatch, single-property scope, and client-role denial.
- The CI concurrency harness races two service callbacks for one order and checks one period/one projection update plus one replay response.

## Verification observed so far

- Node v24.5.0 with cached pnpm 12.18.0 `test:billing` — **14/14 passed**. This Node is below the repository engine floor (24.22.2); conforming-runtime CI remains required.
- `pnpm typecheck` and `pnpm build` — passed locally through the cached pnpm 12.18.0 executable (with Node v24.5.0; runtime floor limitation above).
- `node scripts/docs-check.mjs` — passed, 75 Markdown files.
- `node scripts/verify-contracts.mjs` — passed, 118 operations, 56 tables, 256 field bindings, 90 acyclic packages, 16 trace rows, 36 scenarios.
- JSON Schema validator — passed, 207 schemas; 12 positive and 20 negative examples.
- Storage configuration and prototype smoke — passed (71 synthetic VM/fake-DOM assertions; not billing/backend proof).
- Python concurrency script syntax compile and `git diff --check` — passed.
- Local full SQL execution — **not completed**. Docker daemon is unavailable. A diagnostic PostgreSQL 14.18 bootstrap stopped in existing migration `20261111000200_eve_access_policies.sql` because PostgreSQL 14 lacks `pg_auth_members.inherit_option`; the EVE-026.3 migration/smoke did not run in that attempt.
- PostgreSQL 17 `sql_schema`, fresh synthetic `supabase_local`, PR CI and merge-commit CI — pending. Independent transaction/security review found no blocker. A second review found two privilege-smoke precision gaps; these were tightened and independently confirmed, including exact billing role scope and the `app_executor` negative grant checks.

This evidence is not counted as Done. It does not prove Payriff sandbox verification, hosted Eve database application, full AT28 expiry authorization, safety QR continuity, guest task write windows, or production readiness.
