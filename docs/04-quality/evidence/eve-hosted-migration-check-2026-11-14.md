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
- The canonical project's Data API setting was not changed in this check. The initial dashboard attempt was blocked while the Mac was locked; the later GitHub-authenticated Dashboard session was a different Supabase organization and could not access the canonical project. The broad `supabase config push` was not run because local and remote Auth/Storage settings differ. The separate dashboard-visible project's change and the remaining canonical-project access gate are recorded below.

This follow-up proves a real Supabase Auth record and Auth session for a synthetic test identity, but not an end-to-end reservation flow, Data API/RLS acceptance, SMTP delivery, or production readiness.

## Follow-up — dashboard account mismatch, 2026-11-16

- The GitHub-authenticated Supabase Dashboard session belongs to an organization with two projects: `eve-0062-test-20261112` (`grpkyulubxjhubfgbdrz`) and `livo-demo`. The canonical hosted migration-check project above (`rbjvxikwnvpdriebofnl`) is not accessible in this Dashboard session; opening its project URL returns “You do not have access to this project.”
- The dashboard-visible `eve-0062-test-20261112` is a different project, not a rename of `eve-hosted-migration-check`: its dashboard reports `Unhealthy`, its migration history stops at `20261111001100` (`eve_rent_read`), and it shows no backups. Its role as staging or production has not been documented or validated.
- With the user's explicit confirmation, Data API exposed schemas for that separate test project were changed to `api` only. The saved dashboard state showed 1 of 4 schemas exposed, 0 of 52 tables, and 0 of 199 functions exposed. No function or table exposure was enabled, no migration was applied, and no Auth user was created in this project. The project's prior public/GraphQL schema exposure was removed by this change.
- This configuration change does not resolve the canonical project's `PGRST106` issue and does not make the app functional against `eve-0062-test-20261112`. The canonical project remains the CLI-visible `eve-hosted-migration-check`; changing its Data API setting requires Dashboard access to the correct Supabase organization/account or an authorized narrow Management API path. No broad `supabase config push` was run.

## Follow-up — canonical Data API and reservation smoke, 2026-11-16

This section supersedes the earlier statement that the canonical project's API schema was not exposed and that its Data API setting still needed to change.

- With the user's explicit confirmation, the canonical project's PostgREST configuration was updated through the narrow [Supabase Management API endpoint](https://supabase.com/docs/reference/api/v1-update-postgrest-service-config) to expose only `api`. A separate GET verified `db_schema=api`; `db_extra_search_path` remains `public, extensions`, and `max_rows` remains `1000`. The read-only API OpenAPI endpoint returned HTTP 200 with 28 paths, including `list_reservable_property_contexts`, `create_reservation`, and `move_reservation`.
- The test project's database password was rotated through the Management API and stored only in macOS Keychain for CLI access. No credential value was written to the repository or included in output. The CLI warned that local configuration differed from the linked project; `supabase config push` was not run.
- Before applying changes, remote migration history was verified as an exact prefix of this repository. An isolated temporary CLI workspace, linked to `rbjvxikwnvpdriebofnl`, dry-run selected exactly migrations `20261114002200` through `20261116002700`. `supabase db push --linked --yes` applied those six migrations. A subsequent Management API history read confirmed all 27 remote versions exactly match the repository; the migration list was not force-repaired or manually edited.
- A local Next.js process on port 3002 used the canonical project's URL and publishable key without saving them in a repository env file. A synthetic Auth identity (`codex-eve-smoke-2026-11-16@example.com`) was used; no email was sent. The documented `api.create_property` RPC created a synthetic property and trial. The authenticated local calendar returned HTTP 200 and rendered that property.
- The local same-origin `POST /api/v1/reservations` route created a synthetic confirmed reservation and returned HTTP 201 with the server DTO and balance. Repeating the same request with the same idempotency key returned the same reservation ID. A second request with overlapping dates and a new key returned HTTP 409 `CONFLICT`. An initial test input exceeding the property's one-guest capacity returned HTTP 422; the capacity-conforming request then succeeded.
- This verifies a hosted synthetic reservation create path against the test database. It does **not** establish staging or production readiness, broad RLS negative acceptance, backup/restore, email delivery, Storage HTTP/media acceptance, Payriff, Vercel, real-device accessibility, full AT10, or release gates. The separate dashboard-visible project remains distinct and unchanged by the canonical migration push.
