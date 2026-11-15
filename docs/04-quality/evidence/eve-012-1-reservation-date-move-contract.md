# EVE-012.1 — Reservation date/price and move input contract

## Scope

This package slice implements and tests runtime input parsing for the documented date/price subset of `ReservationPatch` and `ReservationMoveInput`. It is local component/contract work for AT10 preparation. It does not implement or claim the API route or database mutation. Parent issue #20 and full AT10 remain open.

## Implemented

- Date/price patch parsing validates a positive expected version, real ISO calendar dates, a non-empty patch, integer AZN qəpik within the safe integer range, strict keys, end-after-start when both dates are present, and explicit `free_stay: true` for a zero total.
- Move input parsing validates positive expected version, target UUID, integer minor-unit total, optional reason length, strict keys and explicit zero-price confirmation.
- Code comments explicitly reserve owner/capability, entitlement, same-owner, overlap, stale-version comparison, idempotency and atomicity checks for the server/DB.
- No API, data dictionary, state machine, migration, route or UI contract was changed.

## Verification

| Check | Result |
|---|---|
| Targeted contract tests | Passed, 4/4 via `node --conditions=react-server --experimental-strip-types --test tests/unit/reservations/reservation-change-contract.test.ts` |
| Reservation unit suite | Passed, 25/25 via `node --conditions=react-server --experimental-strip-types --test tests/unit/reservations/*.test.ts` |
| TypeScript | Passed via `node node_modules/typescript/bin/tsc --noEmit` |
| Independent read-only contract/security review | No blocker; review verified input limits and the explicit server/DB boundary. Reviewer noted and the author corrected one test title that had called version-shape validation “stale” validation. |

This is local code/test evidence only. No PostgreSQL or hosted backend operation was implemented or exercised; no auth, tenant ownership, capability, same-owner move, occupancy, concurrency, financial history, route, mobile UI or production acceptance is claimed.
