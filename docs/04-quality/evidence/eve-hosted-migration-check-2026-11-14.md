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
