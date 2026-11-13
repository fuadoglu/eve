# EVE-007.2 — Session refresh and logout-all evidence

Status: **implementation in progress**. This evidence covers the local adapter, route, and synthetic DB contract. It is not hosted Supabase or production session acceptance.

## Acceptance mapping

| Acceptance | Local artifact and assertion | Evidence boundary |
|---|---|---|
| Session refresh/logout artifacts use the existing contract | `POST /api/v1/auth/logout` uses explicit local scope; `POST /api/v1/auth/logout-all` records the existing `profiles.session_revoked_before` cutoff and uses global provider sign-out. Shared `requireActiveSession` calls verified `auth.getUser()` (which can refresh the request cookie), then checks stable JWT `session_id` against `auth.sessions` and compares that session row's `created_at` against the cutoff. | Refreshing a pre-cutoff session preserves its session ID and cannot pass by changing JWT `iat`. Future protected API handlers must use this shared guard. Current shell pages contain no private data and are not treated as protected API operations. |
| Positive and negative behavior in local scope | `tests/unit/identity/session*.test.ts` covers current-only scope, global scope/order, active/revoked sessions, invalid body, cross-origin POST, provider outage, 401/503 behavior and avoiding provider initialization for invalid input. | Provider calls are mocked in unit tests. They do not prove remote refresh-token revocation, expiry timing, cookies in a hosted project, or actual other-device logout. |
| DB/RLS contract uses the documented field and remains deny-first | Forward migration `20261113001200_eve_session_revocation.sql` grants only scoped profile-column writes to `app_executor`, creates actor-scoped policies and exposes two authenticated-only RPCs. The private `postgres`-owned `current_session_created_at()` helper reads only the JWT actor/session match from Supabase Auth; its execute privilege is limited to `app_session_reader`, which has no Auth schema/table access or RLS bypass. The guard reads the existing profile cutoff under actor-scoped RLS. SQL smoke checks helper owner/grants, no-profile eligibility, pre-cutoff rejection after JWT refresh, a genuinely new post-cutoff session, cross-user isolation, direct base-write denial and anon denial. | GitHub Actions CI run [#43389045851](https://github.com/fuadoglu/eve/actions/runs/43389045851) passed migration 012 and its SQL smoke in PostgreSQL 17. Supabase-managed Auth compatibility remains a hosted verification gate. No existing migration is edited. |
| HTTP/API and Data API allowlist remain aligned | OpenAPI logout operations remain `EmptyInput → AckEnvelope`; Next.js handlers map the existing `/api/v1/auth/logout` and `/api/v1/auth/logout-all` routes. CI applies migration 012, runs its role-switched smoke and updates the exact RPC allowlist. | CI run #43389045851 passed local Supabase migration, RPC/RLS/synthetic fixture smoke, and Data API/Storage negative HTTP smoke. No production deploy or hosted provider acceptance. |

## Local checks

| Check | Result |
|---|---|
| Identity unit tests (`node --conditions=react-server --experimental-strip-types --test tests/unit/identity/*.test.ts`) | 19/19 passed locally. |
| TypeScript (`./node_modules/.bin/tsc --noEmit`) | Passed locally. `pnpm` launcher could not find its configured Corepack cache, so the installed project binaries were invoked directly. |
| Python syntax (`PYTHONPYCACHEPREFIX=/tmp/eve-pycache python3 -m py_compile scripts/test-local-supabase-http.py`) | Passed locally. |
| `node scripts/docs-check.mjs`, `node scripts/verify-contracts.mjs`, `git diff --check` | Passed locally after the session refresh correction. |
| CI run #43389045851 (`docs`, `sql_schema`, `supabase_local`) | All three jobs passed, including production build, mobile shell browser smoke, PostgreSQL 17 migration/RLS/API allowlist tests, fresh local Supabase Auth schema startup and HTTP negative tests. |
| JSON Schema, storage, prototype, build, mobile shell | Passed earlier in this branch; not rerun after the SQL-only revocation correction. |
| Migration 012 and SQL smoke | Not run locally; Docker daemon is unavailable. CI `sql_schema` is the required execution evidence. |

## External and release limitations

- CI and independent QA review passed; merge is pending.
- Real Supabase refresh rotation/global revoke, current access JWT lifetime, cross-device logout and AT02 have not been tested against a hosted project.
- Provider global sign-out failure returns an error and triggers a local cookie clear attempt; the application cutoff remains active. No success acknowledgement is returned for the partial provider failure.
- This package does not establish production readiness or the M1 exit gate.
