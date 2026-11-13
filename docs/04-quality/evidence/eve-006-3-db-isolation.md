# EVE-006.3 — DB isolation and concurrency evidence

Status: **local package scope complete**. Task contract was recorded in parent issue #14 on 2026-11-13. This evidence is limited to isolated synthetic local PostgreSQL/Supabase CI; it is not hosted or production evidence.

## Acceptance mapping

| Acceptance | Fixture and assertion | Evidence status |
|---|---|---|
| AT04–06 DB negative tests | `0062_access_policy_smoke.sql`, `0062_property_list_smoke.sql`, `0062_reservation_read_smoke.sql`, `0062_reservation_list_smoke.sql`, `0062_manual_block_read_smoke.sql`, `0062_contact_read_smoke.sql`, `0062_rent_read_smoke.sql`, `0062_storage_boundary_smoke.sql`, plus `scripts/test-local-supabase-http.py`. Synthetic A/B owners, M daily/full memberships, owner+manager identity, cross-owner FK failures, revoke-next-request, denied base access and daily finance/storage boundaries are exercised. | CI #43379564053 at head `b937bcf`: `docs`, `sql_schema`, `supabase_local` all `success`; 67 local HTTP/DB assertions passed. PostgreSQL 17 and Supabase local stack are isolated synthetic CI services. |
| Happy-path and negative concurrency invariant | `scripts/test-db-concurrency.py` creates an isolated synthetic owner/property with two overlapping manual blocks. Two independent psql transactions overlap; the first holds an uncommitted occupancy row while the second attempts its conflicting range. | CI #43379564053 output: `2 concurrent transactions, 1 commit, 1 exclusion_violation, 1 active row`. The loser failed specifically on `occupancy_no_overlap`; the synthetic fixture was cleaned. An unmarked invocation was refused with exit 2. Current desktop has no PostgreSQL service, so no local DB run is claimed. |
| Documentation and dependency contract | Package depends on EVE-006.2; no schema or migration changed. `docs-check`, `verify-contracts`, storage-config and JSON Schema validators run on the PR. | Local validators and CI #43379564053 `docs` job passed. Independent `integration_reviewer` read-only review found no blocker; this is not a GitHub human approval. |

## Limits

The race test exercises the existing database exclusion constraint directly; it does not implement or verify a booking/hold/block API transaction or prove all AT07 behavior. The AT04–06 local tests are DB/access foundation evidence and do not close complete product flows, provider behavior, hosted HTTP, media proxy, backup/restore, or production acceptance. Those remain parent/release gates.
