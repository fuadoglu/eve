# EVE-022.2 — media byte validation and finalize

Status: **in progress**. This evidence records the current implementation increment; it does not close EVE-022.2, EVE-022, or any production gate.

## Implemented in this increment

- `src/modules/media/media-validation.ts` validates exact downloaded bytes against supported passive image, audio/video container, and PDF signatures; enforces the existing kind/size/duration limits; and computes SHA-256 from bytes. Client MIME and size declarations are compared with the actual object.
- `src/modules/media/supabase-media-finalizer.ts` reads the pending object's server-only bucket/key metadata, downloads bytes from private Storage, validates measured MIME/size/duration/hash, then calls DB finalize. The `POST /api/v1/media/{id}/finalize` route requires an active session, same-origin empty JSON, and an idempotency key; it returns success only after the DB acknowledges the transition.
- Forward migration `20261114002200_eve_media_finalize.sql` adds an idempotent `app_private.finalize_media_upload` primitive and narrow service-role-only source/finalize `api` bridges. The private primitive and source location are unavailable to anon/authenticated roles. Finalized actual bytes may be below the reservation but may not exceed it, so finalize cannot increase quota usage beyond the amount admitted under EVE-022.1's property lock. Current membership and the existing `inventory.manage` capability boundary are checked before both first finalize and any authorized replay. D39 records this bridge boundary.
- `supabase/tests/0222_media_finalize_smoke.sql` covers grants, authenticated denial of both bridges, source bucket/reservation mapping, over-reservation rejection, validated metadata, idempotent replay/mismatch, cross-owner denial, and denial after inventory membership revocation.
- CI runs the byte-validation unit suite and, after the 022 migration, the PostgreSQL finalize smoke and catalog guards.

## Verification observed

- Node 24.22.2 / pnpm 12.18.0 `pnpm test:media`: **7/7 passed**.
- Node 24.22.2 / pnpm 12.18.0 `pnpm typecheck`: **passed**.
- `node scripts/docs-check.mjs`: **passed**, 73 Markdown files.
- `node scripts/verify-contracts.mjs`: **passed**, 117 operations, 55 tables, 256 field bindings, 90 acyclic packages, 16 trace rows, 36 scenarios.
- `python3 scripts/verify-storage-config.py`: **passed**, API-only schema and seven private D33/D34 buckets align.
- `git diff --check`: **passed**.
- Independent read-only review confirmed the measured-size ceiling and current authorization checks, including private inventory replay. The reviewer did not execute SQL; GitHub PostgreSQL CI remains necessary.
- Initial draft PR CI `43584187911` exposed SQL smoke integration issues. The catalog SELECT list and cross-owner fixture were corrected; follow-up CI confirmed all checks pass.
- Local PostgreSQL migration/smoke: **not run** because the Docker daemon is unavailable. GitHub Actions CI run `43584535175` at head `874318b` passed `docs`, PostgreSQL 17 `sql_schema` (migration, finalize/ACL smoke, RLS coverage and API allowlist), and fresh synthetic `supabase_local` (finalize smoke and Data API/Storage negative HTTP suite). This is synthetic CI evidence, not a hosted Eve or production result.

## Remaining before package closure

- Implement private media serving with a fresh authorization/revoke/expiry/current-placement check per request; do not issue signed read URLs.
- Extend integration smoke to exercise private Storage byte download/finalize behavior. Scoped task/guest media must respect EVE-017.3/link-session dependencies; do not treat owner/property-only checks as their substitute.
- Obtain independent final review and merge after the remaining adapter/proxy work. These tasks are intentionally open; package status remains `in_progress`.
