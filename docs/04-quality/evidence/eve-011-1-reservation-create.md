# EVE-011.1 — Reservation create RPC and initial receipt

Date: 2026-11-14 (Asia/Baku)  
Package: EVE-011.1, parent EVE-011 / issue #19  
Dependencies: EVE-009.3 and EVE-010.3 merged before implementation  
Feature PR: [#91](https://github.com/fuadoglu/eve/pull/91), squash merge `58ad767e54b3eb11fc67b917f7bedc1bbb711717`  
Feature head: `225bc3d1d55076c169bb22fa6cf2e8d1284bb9e2`

## Implemented DB component

`api.create_reservation(jsonb,text)` is an authenticated, property-scoped database RPC. It derives the tenant from the authorized property and actor; serializes on the property lock; rechecks property settings and active/trialing entitlement at the post-lock time; and atomically writes the reservation, initial immutable placement, occupancy, optional rent/deposit receipt, optional realtor commission, audit event, outbox event, and idempotency result.

It rejects unsupported input fields and invalid values, requires confirmation for over-capacity and zero-price cases, requires a hold duration for holds, scopes receipt/commission contacts to the owner, and records the selected owner/manager custodian identity. A retry with the same key and payload returns the same reservation/placement/receipt IDs; a changed payload with the same key is rejected. OpenAPI now makes the realtor-only `contact_id` rule explicit.

The response is an internal create acknowledgement, not a complete ReservationEnvelope or HTTP response. The migration is additive and must be superseded with a new migration after application; it is not edited in place after deployment. No provider or production database was changed.

## Acceptance and verification

- EVE-011.1 DB component acceptance is implemented and tested; this does not claim full AT07–11, HTTP, mobile, or usability acceptance.
- GitHub feature PR CI [run #43572138440](https://github.com/fuadoglu/eve/actions/runs/43572138440) passed `docs`, PostgreSQL 17 `sql_schema`, and fresh synthetic `supabase_local` on feature head `225bc3d`.
- Post-merge main CI [run #43572295768](https://github.com/fuadoglu/eve/actions/runs/43572295768) passed all three jobs on merge commit `58ad767`.
- `sql_schema` exercised migration 019, reservation/receipt/idempotency smoke, RLS/grant and API allowlist coverage, plus the existing occupancy concurrency runner. `supabase_local` exercised fresh synthetic Supabase migration application and reservation smoke.
- Local PostgreSQL 14.18 compatibility-adapted synthetic run also passed `0064_reservation_create_smoke.sql`, `0062_rls_coverage_smoke.sql`, and `0062_api_surface_smoke.sql`. PostgreSQL 14 required adapting only newer role-membership syntax; this is not equivalent to the PostgreSQL 17 CI result.
- `node scripts/docs-check.mjs`, `node scripts/verify-contracts.mjs`, `.venv-docs/bin/python scripts/validate-schemas.py`, `node scripts/test-prototype.mjs` (71 VM/fake-DOM assertions), and `git diff --check` passed locally.
- Independent read-only QA review found four issues during development; all were fixed. Follow-up review found no actionable findings. This is independent review evidence, not GitHub human approval.
- Main branch rules require the `docs` check and zero approving reviews; PR #91 had no human review request. No self-approval was claimed.

## Remaining scope and gates

EVE-011.2 form/detail and server-balance UI, EVE-011.3 retry/validation mobile E2E, full AT07–11 acceptance, hosted Eve Supabase migration history, real HTTP/Data API evidence, backup/restore, real-device/accessibility proof, and production deployment remain open. EVE-011/#19 stays open. This package is not production-ready evidence.

After this package closure, the delivery ledger is 31/90 packages (`34.4%`).
