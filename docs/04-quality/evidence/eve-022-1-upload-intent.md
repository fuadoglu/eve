# EVE-022.1 — upload intent/quota reservation

Status: **EVE-022.1 DB component implemented; final PR CI passed; merge/closure and parent gates remain**. This is not the complete upload pipeline.

## Delivered component

- Migration `20261114002100_eve_upload_quota_reservation.sql` adds a server-generated, 15-minute pending reservation expiry and an internal `app_executor` primitive.
- The primitive derives owner from the property row, requires an active property membership/owner and active entitlement, enforces the 1 GiB property quota under a transaction advisory lock, reserves the declared size, applies OpenAPI kind/MIME/size/duration limits, and uses actor-scoped idempotency.
- D33/D34 classification-to-private-bucket mapping is enforced by the existing `media_bucket_classification` constraint. Receipt media is restricted to owner/full manager. The internal function is not exposed via `api` or executable by `authenticated`/`anon`.
- D37/D38 record the 15-minute versioned expiry and the trusted server adapter boundary. The adapter must derive classification from capability/resource scope before invoking this primitive.

## Verification

- `node scripts/docs-check.mjs` — PASS, 70 Markdown files.
- `node scripts/verify-contracts.mjs` — PASS, 117 operations, 55 tables, 256 field bindings, 90 acyclic packages, 16 trace rows, 36 scenarios.
- `.venv-docs/bin/python scripts/validate-schemas.py` — PASS, 207 schemas; 12 positive and 20 negative examples.
- `node scripts/test-prototype.mjs` — PASS, 71 assertions. This remains prototype-only evidence.
- PostgreSQL 14.18 synthetic local clone based on the available empty 001–019 schema; EVE-017.1 and EVE-022.1 migrations were applied from temporary compatibility-adapted copies that removed only PG16+ `GRANT ... WITH SET` options. EVE-017.1 transition smoke, `supabase/tests/0221_upload_quota_reservation_smoke.sql`, `0062_rls_coverage_smoke.sql`, and `0062_api_surface_smoke.sql` — PASS. Upload coverage includes positive reservation, idempotent replay/mismatch, image/audio/MIME negatives, aggregate quota overflow/expiry release, cross-owner, daily manager receipt denial, and anonymous rejection. This PG14 run is diagnostic only; source migrations are unchanged.
- Final PR head `6aef350` CI run `43581014490`: `docs`, PostgreSQL 17 `sql_schema` and fresh synthetic `supabase_local` all passed. The `sql_schema` job ran the unmodified migration and upload smoke; `supabase_local` applied the ordered migration chain and ran upload smoke, RLS/grant coverage and API surface check.
- Independent read-only QA review final follow-up: no blocking finding on privilege ordering, RLS allowlist or docs. This is not GitHub human approval.

## Explicit limits

No HTTP upload-intent route, server adapter, signed Storage URL, byte transfer, magic-byte validation, finalize, EXIF handling, private media serving, orphan cleanup, hosted Eve Supabase or production DB application is included or proven. The caller must derive classification and exact resource scope; this DB component does not independently infer those from the browser request. EVE-022.2/.3 and AT06/AT21/AT32 full file-flow acceptance remain open.
