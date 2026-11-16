# EVE-012.2 — Reservation lifecycle transition input contract

## Scope

This package slice adds runtime parsing for the `cancel`, `no_show`, `check_in`, and `check_out` subset of `ReservationTransition`, and aligns the OpenAPI financial-decision invariant with API-CONTRACT: it is accepted only for cancel/no-show. Parent issue #20 and full AT10/AT12/AT16 remain open.

## Implemented

- Parser enforces positive expected version, the four scoped actions, strict top-level fields, optional reason limit, and the documented nested adjustment shapes.
- `keep_as_is` has no other fields; `adjust` must have a receipt-linked rent refund, deposit return, or commission amount. Amounts are safe integer qəpik; source IDs are UUIDs; adjustment arrays have 1–100 items.
- OpenAPI now rejects `financial_decision` with `confirm`, `check_in`, `check_out`, and `release_remaining_days`, matching the text contract that limits financial decisions to cancellation/no-show. Existing policy and state-machine declarations are otherwise unchanged.
- Code comments reserve current-state/arrival checks, entitlement, capability, money-ledger bounds, idempotency, task/occupancy/link effects and atomicity for server/DB implementation.

## Verification

| Check | Result |
|---|---|
| Targeted transition contract tests | Passed, 4/4 via `node --conditions=react-server --experimental-strip-types --test tests/unit/reservations/reservation-transition-contract.test.ts` |
| TypeScript | Passed via `node node_modules/typescript/bin/tsc --noEmit` |
| Documentation links/IDs | Passed via `node scripts/docs-check.mjs` |
| Contract/dependency checks | Passed via `node scripts/verify-contracts.mjs` |
| JSON Schema examples | Passed: 207 schemas, 12 positive and 20 negative via `/tmp/eve0222-schema-venv/bin/python scripts/validate-schemas.py` |
| Prototype smoke | Passed: 71 assertions; VM/fake-DOM evidence only |
| Independent review | Passed: read-only contract/security review found no blocker; reviewer confirmed the explicit server/DB boundary and targeted tests 4/4. |

This is local contract code and schema evidence only. No route, PostgreSQL transition, RLS/policy, real authorization, cancellation/refund write, task event, checkout effect, hosted database, mobile UX or production acceptance is claimed.

## Package closure

EVE-012.2 is `done` for this documented local component/contract scope. PR #114 squash-merged as `92700bf6507314100e6fc0fcf11a1d9ec5d5f8f1`; independent contract/security review found no blocker, including the Unicode maxLength follow-up. PR CI [#43814247879](https://github.com/fuadoglu/eve/actions/runs/43814247879) and merged-main CI [#43814801917](https://github.com/fuadoglu/eve/actions/runs/43814801917) passed `docs`, PostgreSQL 17 `sql_schema`, and fresh synthetic `supabase_local`. Parent #20 and full AT10 remain open; this package closure does not assert backend transition integration or production readiness.

## Package closure

EVE-012.2 is `done` for this documented local component/contract scope. PR #114 squash-merged as `92700bf6507314100e6fc0fcf11a1d9ec5d5f8f1`; independent contract/security review found no blocker, including the Unicode maxLength follow-up. PR CI [#43814247879](https://github.com/fuadoglu/eve/actions/runs/43814247879) and merged-main CI [#43814801917](https://github.com/fuadoglu/eve/actions/runs/43814801917) passed `docs`, PostgreSQL 17 `sql_schema`, and fresh synthetic `supabase_local`. Parent #20 and full AT10 remain open; this package closure does not assert backend transition integration or production readiness.
