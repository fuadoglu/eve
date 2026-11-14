# EVE-026.3 — Trial/leap/month-end/plan transition integration

Status: **Done for the EVE-026.3 package scope**. Merged with squash PR #108 as 3d352dbaa51b1f1e7a7ef2859905a27f0988ec84.

## Implemented

- apply_verified_billing_order consumes only an existing verified_paid order. It accepts no client timestamp or anchor, enforces the documented single-property checkout boundary, validates the AZN total, and serializes application with order → property → subscription row locks.
- One transaction inserts the unique subscription period, updates entitlement and Asia/Baku anchor projection, marks the order line, and transitions the order to entitlement_applied. A retry returns the same period with replay=true.
- A service-role-only API bridge and server adapter apply the order. A dedicated billing_executor role has narrow table/column privileges and exact RLS policy checks. Provider verification remains owned by EVE-027.
- PostgreSQL smoke covers trial purchase at a February 29 Baku boundary, annual early renewal, annual-to-monthly switch, January 31 → February clamp → March restoration, microsecond precision, replay, unverified order, amount mismatch, single-property scope, and client-role denial.
- CI concurrency harness races two server callbacks for one order and checks one period, one projection update, and one replay result.

## Verification

- PR CI run [#43645609538](https://github.com/fuadoglu/eve/actions/runs/43645609538): docs, PostgreSQL 17 sql_schema, and fresh synthetic supabase_local all passed.
- Merge-commit CI run [#43645789988](https://github.com/fuadoglu/eve/actions/runs/43645789988): all three jobs passed again on the merged commit.
- The first CI iterations exposed migration-runner role membership assumptions. Those were corrected; the final runs passed migration 024, period smoke, exact RLS/API grants, concurrency and the fresh Supabase stack.
- Independent integration review and follow-up ACL review found no remaining blocker. No human review is claimed; GitHub branch protection required zero approvals.
- Local Node v24.5.0 / cached pnpm 12.18.0 test:billing: **14/14 passed**. The local Node version is below the repository floor 24.22.2.
- Local pnpm typecheck and pnpm build passed using the cached pnpm executable and Node v24.5.0.
- node scripts/docs-check.mjs passed, 75 Markdown files; node scripts/verify-contracts.mjs passed, 118 operations, 56 tables, 256 bindings, 90 acyclic packages, 16 trace rows and 36 scenarios.
- JSON Schema validator passed, 207 schemas; 12 positive and 20 negative examples. Storage configuration validator passed, seven private buckets. Prototype smoke passed, 71 synthetic VM/fake-DOM assertions; it is not billing or backend proof.
- git diff --check and concurrency-script syntax compile passed.
- Local full SQL execution was unavailable: Docker daemon was not available, and a PostgreSQL 14.18 diagnostic bootstrap stopped in pre-existing migration 20261111000200_eve_access_policies.sql because PG14 lacks pg_auth_members.inherit_option. The merged PG17 CI is the SQL runtime proof for this package.

## Remaining scope

This package does not prove Payriff sandbox verification/reconciliation, hosted Eve database application, full AT28 expiry authorization, safety QR continuity, guest task write windows, backup/restore or production readiness. Those gates remain open under their respective packages.
