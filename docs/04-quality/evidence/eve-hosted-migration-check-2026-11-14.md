# Hosted Supabase migration check — 2026-11-14

Status: **fresh hosted test project migration history verified; not Eve staging or production**.

## Environment

- Supabase project: `eve-hosted-migration-check`
- Project ref: `rbjvxikwnvpdriebofnl`
- Region: `eu-central-1` (Frankfurt)
- Provisioned: 2026-11-14 08:47 UTC
- New project; Eve application migration history was initially empty (all 21 repository versions showed remote blank before push). No guest or production data was used.
- Supabase CLI: `2.33.9`
- DB password was generated randomly and never committed or printed. It is no longer available in the local Keychain; reset it in the Supabase Dashboard before another direct database connection. The project remains accessible in the account.

## Migration result

The ordered repository migration chain `20261111000100` through `20261114002100` (21 migrations) was pushed successfully with `supabase db push`. A subsequent `supabase migration list --linked` showed every local migration version paired with the identical remote version; no local-only or remote-only migration was reported.

This confirms clean application and migration-history alignment for this new hosted test project. It does not recover or prove the history of the earlier temporary project, and it does not establish that any Eve production database exists.

## Limits and follow-up

- The linked Supabase project configuration differed from the repository in API schema exposure, Storage size, Auth defaults, and bucket configuration. `supabase config push` was deliberately not run because it would change unrelated remote Auth/API settings.
- Therefore D33/D34 bucket provisioning, Supabase Storage HTTP access, signed upload, object transfer, MIME/magic-byte validation, finalization, private serving, and hosted RLS/API negative acceptance are **not** claimed as passed here.
- No application credentials, SMTP, Payriff, Vercel, or real user data were configured.
- The project is a hosted migration test only. EXT02 staging/production, backup/restore, and release acceptance remain open.

## Reproduction evidence

Commands run from an isolated temporary Supabase CLI workspace containing the main-branch `supabase/` tree:

1. `supabase link --project-ref rbjvxikwnvpdriebofnl --password [stored secret]`
2. `supabase migration list --linked --password [stored secret]` — initially all 21 versions were local-only.
3. `supabase db push --linked --password [stored secret]` — all 21 migrations applied; exit 0.
4. `supabase migration list --linked --password [stored secret]` — all 21 local/remote versions matched; exit 0.

The password placeholder above is explanatory only; no credential is stored in this repository.

## Follow-up — local Auth account and Data API connection, 2026-11-16

- The account still exposes `eve-hosted-migration-check` as `ACTIVE_HEALTHY`; it remains a hosted migration test project, not staging or production.
- A synthetic Supabase Auth user (`codex-eve-smoke-…@example.com`) was created with email confirmed. Supabase's admin create-user endpoint returned HTTP 200. No email was sent, no SMTP setting was changed, and no real person's data was used. A one-time magic link was generated through the admin API and verified directly with the publishable key to test the local SSR cookie path.
- The local Next.js app was started against this project's URL and publishable key without writing credentials to the repository. `/calendar` returned HTTP 200, and Supabase Auth produced a session for the synthetic user.
- The reservation context RPC could not run: PostgREST returned HTTP 406 `PGRST106 Invalid schema: api` for `api.is_my_session_active` and `api.list_reservable_property_contexts`. This is a hosted Data API configuration mismatch; migration history alone does not expose the `api` schema.
- The project dashboard API setting was not changed in this check. The Mac was locked when the dashboard was needed, and the local config contains unrelated Auth/Storage differences; the broad `supabase config push` was not run. Next step is a narrow test-project Data API configuration update exposing only the documented `api` schema, then repeat the authenticated local request and negative RPC/grant checks.

This follow-up proves a real Supabase Auth record and Auth session for a synthetic test identity, but not an end-to-end reservation flow, Data API/RLS acceptance, SMTP delivery, or production readiness.
