# EVE-022.2 — media byte validation and finalize

Status: **in progress**. This evidence records the current implementation increment; it does not close EVE-022.2, EVE-022, or any production gate.

## Implemented in this increment

- `src/modules/media/media-validation.ts` validates exact downloaded bytes against supported passive image, audio/video container, and PDF signatures; enforces the existing kind/size/duration limits; and computes SHA-256 from bytes. Client MIME and size declarations are compared with the actual object.
- Forward migration `20261114002200_eve_media_finalize.sql` adds an idempotent `app_private.finalize_media_upload` primitive and a narrow service-role-only `api.finalize_media_upload_for_server` bridge. The private primitive is not executable through anon/authenticated roles. Finalized actual bytes may be below the reservation but may not exceed it, so finalize cannot increase quota usage beyond the amount admitted under EVE-022.1's property lock. Current membership and the existing `inventory.manage` capability boundary are checked before both first finalize and any authorized replay. D39 records this bridge boundary.
- `supabase/tests/0222_media_finalize_smoke.sql` covers grants, authenticated denial, over-reservation rejection, validated metadata, idempotent replay/mismatch, cross-owner denial, and denial after inventory membership revocation.
- CI runs the byte-validation unit suite and, after the 022 migration, the PostgreSQL finalize smoke and catalog guards.

## Verification observed

- Node 24.22.2 / pnpm 12.18.0 `pnpm test:media`: **4/4 passed**.
- Node 24.22.2 / pnpm 12.18.0 `pnpm typecheck`: **passed**.
- `node scripts/docs-check.mjs`: **passed**, 72 Markdown files.
- `node scripts/verify-contracts.mjs`: **passed**, 117 operations, 55 tables, 256 field bindings, 90 acyclic packages, 16 trace rows, 36 scenarios.
- `python3 scripts/verify-storage-config.py`: **passed**, API-only schema and seven private D33/D34 buckets align.
- `git diff --check`: **passed**.
- Independent read-only review confirmed the measured-size ceiling and current authorization checks, including private inventory replay. The reviewer did not execute SQL; GitHub PostgreSQL CI remains necessary.
- PostgreSQL migration/smoke, CI, and hosted provider checks: **not run**. Local Docker daemon is unavailable; no hosted claim is made.

## Remaining before package closure

- Wire the validator and finalize primitive to an authenticated server adapter that retrieves the reserved object from its private bucket and trusts only server-validated session/scope.
- Implement private media serving with a fresh authorization/revoke/expiry/current-placement check per request; do not issue signed read URLs.
- Extend the smoke suite to exercise the integrated server/storage behavior and verify it in CI. Scoped task/guest media must respect EVE-017.3/link-session dependencies; do not treat owner/property-only checks as their substitute.
- Obtain independent read-only review and merged-branch CI evidence. These tasks are intentionally open; package status remains `in_progress`.
