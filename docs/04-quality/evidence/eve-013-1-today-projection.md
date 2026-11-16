# EVE-013.1 — Today projection (in progress)

Date: 2026-11-16 (Asia/Baku). Branch: `feat/EVE-013-1-today-projection`. Parent issue: #21.

## Implemented locally

- `GET /api/v1/today` validates `local_date` and `owner_account_id`, requires a verified active Supabase session, uses the user-scoped `api` schema client, and returns private/no-store OpenAPI `TodayEnvelope` data.
- `api.get_today` is a read-only `app_executor` RPC. It checks the active session and current property scope, projects current-placement arrivals/departures, overdue/open task states, rent remaining on arrival day (excluding deposits), and subscription expiry on its Asia/Baku date.
- Card order is recorded in D42: overdue tasks, arrivals/departures, tasks due today, arrival-day rent balances, and subscriptions expiring today. Expense and inspection cards are not inferred because the product documents no due/problem rule for this projection.
- `/today` requests the API and distinguishes loading, unauthenticated/error, empty, and populated responses. Cards label the server-declared next operation. Target detail and transition routes are separate/incomplete upstream work, so this evidence does not claim those actions are executable.
- Money summary aggregation uses `BigInt`, preserving integer qəpik when multiple individually safe amounts are combined. SQL smoke fixtures include arrival/departure, overdue and reported-done tasks, a task attached to a superseded placement, rent/deposit separation, subscription expiry, and cross-tenant scope.

## Verification performed

- Today contract unit tests: **4/4 passed** (Node 24.5.0).
- TypeScript `tsc --noEmit`: **exit 0**.
- Next.js 16.4.6 production build: **exit 0**; `/api/v1/today` and `/today` compiled as dynamic routes.
- The required runtime is Node 24.22.2; local Node 24.5.0 is below that floor, so local validation is diagnostic and CI on the pinned runtime remains required.
- Docs checker, machine-contract verifier, Python schema validator, and prototype smoke all passed locally. The latter is VM/fake-DOM evidence, not browser/device acceptance.
- Chromium mobile shell smoke passed **124 assertions** locally at 320/360/390/430px. This validates the shared mobile shell interactions and accessibility checks; it is not a real-device or authenticated Today data test.
- Supabase Auth settings endpoint for canonical test project `rbjvxikwnvpdriebofnl` returned HTTP 200 with the configured publishable key. Before migration 028, `api.get_today` returned HTTP 404. A CLI `link` attempt identified the project but Supabase denied the current account access to remote project status because it lacks the necessary project privileges.

## Open proof and blockers

- PostgreSQL smoke `0068_today_projection_smoke.sql` has not run locally: Docker is unavailable and installed PostgreSQL is 14.18, below the repository CI PostgreSQL 17 requirement.
- CI run [#43856542579](https://github.com/fuadoglu/eve/actions/runs/43856542579) passed all three jobs on head `260b700`: `docs` (including Chromium mobile shell and validators), `sql_schema` (migration 028, smoke 0068, RLS/RPC/occupancy checks), and `supabase_local` (synthetic API/security and browser-to-PostgreSQL E2E).
- Migration 028 was **not** applied to the hosted project because the connected Supabase account lacks the required project privilege. No authenticated Eve user session was used, so no hosted Today DTO/data result is claimed.
- Independent review found and verified fixes for UUID format, title length, package ownership metadata, money precision, and projection smoke coverage. It found no SQL/tenant-scope defect; executable card destinations remain outside this projection because their detail/transition routes are incomplete upstream.
- EVE-012.3 remains `in_progress` and is a declared dependency. EVE-013.1 and parent #21 remain open; this package is not Done and does not close UI04 operations, AT10, AT29, production DB, backup/restore, or release gates.
