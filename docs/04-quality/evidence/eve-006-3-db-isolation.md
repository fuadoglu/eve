# EVE-006.3 — DB isolation and concurrency evidence

Status: **in progress; no package completion claim**. Task contract is recorded in parent issue #14 on 2026-11-13. This evidence is limited to isolated synthetic local PostgreSQL/Supabase CI; it is not hosted or production evidence.

## Acceptance mapping

| Acceptance | Fixture and assertion | Evidence status |
|---|---|---|
| AT04–06 DB negative tests | `0062_access_policy_smoke.sql`, `0062_property_list_smoke.sql`, `0062_reservation_read_smoke.sql`, `0062_reservation_list_smoke.sql`, `0062_manual_block_read_smoke.sql`, `0062_contact_read_smoke.sql`, `0062_rent_read_smoke.sql`, `0062_storage_boundary_smoke.sql`, plus `scripts/test-local-supabase-http.py`. These use synthetic A/B owners, M daily/full memberships, cross-owner failures, revoke-next-request, denied base access and daily finance/storage boundaries. | Existing suite passed in main CI #43378759033 (`sql_schema`, `supabase_local`); the EVE-006.3 PR run must repeat this evidence on its own head before closure. |
| Happy-path and negative concurrency invariant | `scripts/test-db-concurrency.py` creates an isolated synthetic owner/property with two overlapping manual blocks. Two independent psql transactions overlap; first holds an uncommitted occupancy row while the second attempts its conflicting range. Expected: first commits, second fails specifically on `occupancy_no_overlap`, and exactly one active row remains. Fixture is cleaned after success. | Newly added; awaiting PR CI execution. Local PostgreSQL service is not available in the current desktop environment. |
| Documentation and dependency contract | Package dependency is EVE-006.2; no schema or migration changes. `docs-check` and `verify-contracts` validate the package ledger and DAG. | Local validators passed on the current branch; final PR CI is pending. |

## Limits

The race test exercises the existing database exclusion constraint directly; it does not implement or verify a booking/hold/block API transaction or prove all AT07 behavior. The AT04–06 local tests are partial foundation projections and do not close complete product flows, provider behavior, hosted HTTP, media proxy, backup/restore, or production acceptance.
