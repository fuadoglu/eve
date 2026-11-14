# EVE-026.1 — Billing catalog and initial order-line component

- **Task:** EVE-026.1, parent EVE-026 / GitHub issue #34
- **Feature branch:** `feat/EVE-026-1-billing-catalog`
- **Feature commits:** `74d9be3` (catalog/order contract), `48acb61` (initial single-property scope), `dea9e26` (test naming)
- **Feature PR:** [#99](https://github.com/fuadoglu/eve/pull/99), squash-merged
- **Main commit:** `39d0381193af3adf3ae42eeb61178a0f050a18cb`
- **CI:** [run #43579005886](https://github.com/fuadoglu/eve/actions/runs/43579005886) — `docs`, clean typecheck/build, PostgreSQL 17 `sql_schema`, and fresh synthetic `supabase_local` all passed.
- **Independent review:** found a multi-property order draft exceeded the initial one-property product scope. The implementation and issue/package ownership were narrowed to one property; bulk checkout remains a separate task. Final follow-up found no remaining issue. No GitHub human approval is claimed; branch protection requires zero approvals.

## Implemented component

- Server-owned catalog returns monthly 999 and yearly 9999 integer qəpik, currency AZN, seven-day first-property trial descriptor, and `recurring_available: false`.
- Builds an initial single-property order-line draft only from a property already loaded for the current owner.
- Uses server catalog price regardless of extra client fields; rejects malformed IDs, foreign/missing property scope and unsupported recurring opt-in.
- Enforces safe integer order totals and current single-property checkout scope.

## Verification evidence

- `node --conditions=react-server --experimental-strip-types --test tests/unit/billing/*.test.ts` — 4/4 passed.
- `node_modules/.bin/tsc --noEmit` — passed with temporary dependency symlink, removed afterward.
- `node scripts/docs-check.mjs` — passed.
- `node scripts/verify-contracts.mjs` — passed.
- CI clean typecheck/build and branch `docs` check — passed.
- CI PostgreSQL 17 and fresh synthetic Supabase jobs — passed; this package adds no migration.
- `git diff --check` — passed.

## Scope limits

This is a local catalog/order-line component, not a persisted API. It does not initiate or verify payment, integrate Payriff, apply a trial or paid entitlement, calculate calendar periods/anchor clamps, or implement bulk checkout. Hosted provider sandbox, full AT25/AT28, backup/restore and production evidence remain open.
