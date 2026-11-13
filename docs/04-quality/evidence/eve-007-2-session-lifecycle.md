# EVE-007.2 — Session refresh and logout-all evidence

Status: **implementation in progress**. This evidence covers the local adapter, route, and synthetic DB contract. It is not hosted Supabase or production session acceptance.

## Acceptance mapping

| Acceptance | Local artifact and assertion | Evidence boundary |
|---|---|---|
| Session refresh/logout artifacts use the existing contract | `POST /api/v1/auth/logout` uses explicit local scope; `POST /api/v1/auth/logout-all` records the existing `profiles.session_revoked_before` cutoff and uses global provider sign-out. Shared `requireActiveSession` calls verified `auth.getUser()` (which can refresh the request cookie), then checks stable JWT `session_id` against `auth.sessions` and compares that session row's `created_at` against the cutoff. | Refreshing a pre-cutoff session preserves its session ID and cannot pass by changing JWT `iat`. Future protected API handlers must use this shared guard. Current shell pages contain no private data and are not treated as protected API operations. |
| Positive and negative behavior in local scope | `tests/unit/identity/session*.test.ts` covers current-only scope, global scope/order, active/revoked sessions, invalid body, cross-origin POST, provider outage, 401/503 behavior and avoiding provider initialization for invalid input. | Provider calls are mocked in unit tests. They do not prove remote refresh-token revocation, expiry timing, cookies in a hosted project, or actual other-device logout. |
| DB/RLS contract uses the documented field and remains deny-first | Forward migration `20261113001200_eve_session_revocation.sql` grants only scoped profile-column writes to `app_executor`, creates actor-scoped policies and exposes two authenticated-only RPCs. `app_session_reader` has narrow column-level read access to `auth.sessions` and the existing cutoff field. SQL smoke checks no-profile eligibility, pre-cutoff rejection after JWT refresh, a genuinely new post-cutoff session, cross-user isolation, direct base-write denial and anon denial. | Local Docker/PostgreSQL is unavailable in this desktop session. SQL smoke is pending CI and must not be called passed until then. No existing migration is edited. |
| HTTP/API and Data API allowlist remain aligned | OpenAPI logout operations remain `EmptyInput → AckEnvelope`; Next.js handlers map the existing `/api/v1/auth/logout` and `/api/v1/auth/logout-all` routes. CI applies migration 012, runs its role-switched smoke and updates the exact RPC allowlist. | No production deploy. HTTP behavior beyond route unit checks awaits CI and provider staging. |

## Local checks

| Check | Result |
|---|---|
| Identity unit tests (`node --conditions=react-server --experimental-strip-types --test tests/unit/identity/*.test.ts`) | 19/19 passed locally. |
| TypeScript (`./node_modules/.bin/tsc --noEmit`) | Passed locally. `pnpm` launcher could not find its configured Corepack cache, so the installed project binaries were invoked directly. |
| Python syntax (`PYTHONPYCACHEPREFIX=/tmp/eve-pycache python3 -m py_compile scripts/test-local-supabase-http.py`) | Passed locally. |
| `node scripts/docs-check.mjs`, `node scripts/verify-contracts.mjs`, `git diff --check` | Passed locally after the session refresh correction. |
| JSON Schema, storage, prototype, build, mobile shell | Passed earlier in this branch; not rerun after the SQL-only revocation correction. |
| Migration 012 and SQL smoke | Not run locally; Docker daemon is unavailable. CI `sql_schema` is the required execution evidence. |

## External and release limitations

- CI, independent QA review and merge are pending for this package.
- Real Supabase refresh rotation/global revoke, current access JWT lifetime, cross-device logout and AT02 have not been tested against a hosted project.
- Provider global sign-out failure returns an error and triggers a local cookie clear attempt; the application cutoff remains active. No success acknowledgement is returned for the partial provider failure.
- This package does not establish production readiness or the M1 exit gate.
