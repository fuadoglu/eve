# EVE-010.2 — Expired hold lock/catch-up

Date: 2026-11-13  
Package: EVE-010.2, parent EVE-010 / issue #18  
Dependency: EVE-010.1 merged in PR #85/#86  
Feature PR: [#87](https://github.com/fuadoglu/eve/pull/87), squash merge `5695861f2995510045676f038919518f3551fc4a`  
Reviewed head: `d53b69f1be3508f344ea8e8dc3f5f88f97404e94`

## Delivered component behavior

The additive migration `20261113001800_eve_expired_hold_catchup.sql` adds the private `app_private.expire_property_holds(property_id)` helper. The helper accepts the current owner or a current, non-revoked property member, locks the property row, and reads `clock_timestamp()` after the lock is acquired. It finds due `hold` reservations for that property, changes each to `cancelled`, clears `hold_expires_at`, updates timestamp/version, deactivates exactly one matching active placement occupancy, and records an audit event with capability `system.hold_expiry` and reason `hold_expired`. A missing active occupancy raises an integrity error and rolls back the transaction. Repeated invocation is idempotent. The function is not exposed as a public RPC; `app_executor` alone receives execute permission.

No enum, OpenAPI operation, API DTO, or default changed. The existing reservation state enum and `[check_in, check_out)` occupancy model remain in use.

## Acceptance and verification evidence

- EVE-010.2 component acceptance is met by the helper, migration, and `0063_expired_hold_catchup_smoke.sql`.
- PostgreSQL 16.13 local synthetic run passed with the core schema and access-policy migrations, the EVE-010.2 migration, and the new smoke. The fixture verifies owner and daily-manager calls, cross-owner and unauthenticated denial, an actual `app_executor` role-switched call, due/future hold behavior, preservation of a confirmed reservation and manual block, state/version/occupancy/audit effects, idempotent retry, grants/search path, and rollback on missing occupancy.
- GitHub PR CI run [#43414122014](https://github.com/fuadoglu/eve/actions/runs/43414122014) passed `docs`, PostgreSQL 17 `sql_schema`, and fresh synthetic `supabase_local` on final feature head `d53b69f`; post-merge main CI run [#43414388727](https://github.com/fuadoglu/eve/actions/runs/43414388727) also passed all three jobs on merge commit `5695861`.
- Local repository checks passed: `node scripts/docs-check.mjs`; `node scripts/verify-contracts.mjs`; Python schema validation (207 schemas, 12 positive and 20 negative examples); prototype smoke (71 assertions); workflow YAML parse; and `git diff --check`.
- Independent read-only QA review found no P1/P2/P3 findings after the final role-switched smoke update. This is not a GitHub human approval. Main branch protection currently requires zero approving reviews; required `docs` and the package CI checks passed.

## Scope limits and remaining work

This closes only the EVE-010.2 database helper component. It does not implement a scheduler, booking-create RPC/HTTP flow, UI, or full cross-transaction booking/hold/block concurrency. Full AT07–09 and the parallel booking/block/hold package EVE-010.3 remain open. Hosted Eve Supabase migration history and production/backup/restore acceptance were not tested. Do not treat this result as production readiness.

After this closure, the delivery ledger is 29/90 packages (`32.2%`). EVE-010.3 and parent issue #18 remain open.
