# EVE-012.3 — Placement history and permission regression

## Scope and status

Status: `in_progress`. This work implements a database guard for the documented immutable placement history and prepares PostgreSQL role-switched regression coverage. EVE-012.3 is not closed: no reservation move RPC currently exists, and the smoke below uses a clearly synthetic pointer update. It does not prove the documented atomic move transaction or the complete AT10 transition matrix.

Normative references: `docs/03-engineering/DATA-MODEL.md` §§4–5, `docs/04-quality/ACCEPTANCE.md` AT10, and `docs/05-delivery/work-packages.json` EVE-012.3.

## Implementation under review

- Migration `20261116002600_eve_reservation_placement_history_guard.sql` rejects placement deletion, mutation of snapshot/identity columns, invalid closure, and a second closure. The only permitted placement update is the one-way `effective_to: NULL → timestamp` transition strictly after `effective_from`.
- `0066_reservation_placement_history_smoke.sql` covers positive and negative cases for the guard and verifies source-only versus target manager visibility around a synthetic current-placement pointer update. It verifies the authenticated client cannot access the private placement table directly.
- CI runs the migration and smoke in the PostgreSQL 17 schema job; the fresh local Supabase job runs the smoke after migration application.

## Evidence

- `node scripts/docs-check.mjs` — passed (79 Markdown files).
- `node scripts/verify-contracts.mjs` — passed (118 operations, 56 tables, 256 field bindings, 90 acyclic packages, 36 scenarios).
- `/tmp/eve0222-schema-venv/bin/python scripts/validate-schemas.py` — passed (207 schemas, 12 positive and 20 negative examples).
- `node scripts/test-prototype.mjs` — passed (71 assertions; VM/fake-DOM scope only).
- `git diff --check` — passed.
- Initial PostgreSQL 17 and fresh synthetic Supabase CI — failed: the first smoke incorrectly assumed the trusted internal `app_executor` role could not select historical rows. Existing media-proxy policy intentionally grants that internal executor row access; this role is not granted to `authenticated`. The smoke has been corrected to assert that the authenticated client has no direct private-table access. Corrected SQL has not yet rerun.
- Local SQL execution — not run: Docker daemon is unavailable and no local PostgreSQL server answers on `localhost:5432`. Corrected database result is pending PostgreSQL 17 and fresh synthetic Supabase CI.
- Independent read-only review — no defect found in the trigger logic or CI ordering for this slice. Review confirmed that this synthetic pointer update does not meet AT10 move/side-effect acceptance; EVE-012.3 remains `in_progress` and is not counted done.

## Explicitly open

- Implement the documented move command with same-owner and both-property authorization, locks, overlap checks, occupancy transfer, immutable placement history, attribution, task preservation/cancellation, guest-private link revocation, audit/outbox, and idempotency.
- Prove the complete AT10 matrix, including stale version handling, early departure, completed task preservation, old-placement link revocation, and source-only privacy through the actual command path.
- Independent review, PR merge, merged-main CI, and package ledger closure.

This package is not production-ready evidence and does not claim any hosted database or production change.
