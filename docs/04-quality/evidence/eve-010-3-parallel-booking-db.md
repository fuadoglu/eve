# EVE-010.3 — Parallel booking/block/hold DB tests

Date: 2026-11-13  
Package: EVE-010.3, parent EVE-010 / issue #18  
Dependency: EVE-010.2 merged in PR #87/#88  
Feature PR: [#89](https://github.com/fuadoglu/eve/pull/89), squash merge `78c7b0fa3f4b09d9123ad39812de53ec65629fd7`  
Reviewed head: `1e982c0f42faac74bb6bbdc3a4edd84095913725`

## DB component behavior tested

The existing local-only `scripts/test-db-concurrency.py` runner now uses explicit barriers rather than timing sleeps. It confirms competing transactions have reached the property-row lock wait before releasing the winning transaction.

- One property-locked manual block races two same-interval transactions (a hold and a confirmed reservation). The block commits; both reservation transactions fail on `occupancy_no_overlap`; no losing reservation or placement remains.
- A delayed background transaction holds the property lock without expiring an already-due hold. The next reservation write waits, invokes EVE-010.2 catch-up, and commits the same interval. The old hold becomes `cancelled`, its occupancy is inactive, and repeating catch-up returns zero.
- The existing first-trial race also waits for the losing create call to block on its advisory lock before the winner commits.
- Fixture cleanup runs only after the script validates the marked localhost `eve_schema_test` target. It removes all reservation, placement, occupancy, block, owner and auth-user fixtures; the local post-run counts were zero.

## Acceptance and verification evidence

- EVE-010.3 DB-level component criteria in `work-packages.json` are met. PostgreSQL 16.13 local synthetic run applied the repository migrations in order and passed all four reported scenarios.
- GitHub PR CI [#43416622216](https://github.com/fuadoglu/eve/actions/runs/43416622216) passed `docs`, PostgreSQL 17 `sql_schema`, and fresh synthetic `supabase_local` on final feature head `1e982c0`; post-merge main CI [#43416838949](https://github.com/fuadoglu/eve/actions/runs/43416838949) also passed all three jobs on merge commit `78c7b0f`.
- Independent read-only integration review found no P1/P2/P3 findings after synchronization and cleanup fixes. This is not a GitHub human approval.
- Local `docs-check`, `verify-contracts`, Python JSON Schema validator, script compilation, and `git diff --check` passed.

## Parent acceptance still open

This package does not mark full AT07–09 acceptance passed. Full booking-create RPC/idempotency is not implemented; public valid-departure behavior is not exercised here. AT07 API error/receipt behavior, AT08 public departure projection, AT09 reservation-create idempotency, hosted Eve Supabase history, and production/backup/restore gates remain open. The synthetic direct-SQL race is not booking HTTP/API, live traffic, or production evidence.

After this closure, the delivery ledger is 30/90 packages (`33.3%`). Parent issue #18 remains open for the downstream booking API and remaining acceptance.
