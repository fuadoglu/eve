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
- Supabase Auth settings endpoint for canonical test project `rbjvxikwnvpdriebofnl` returned HTTP 200 with the configured publishable key. Before migration 028, `api.get_today` returned HTTP 404.

## Open proof and blockers

- PostgreSQL smoke `0068_today_projection_smoke.sql` has **not** run locally: Docker is unavailable and installed PostgreSQL is 14.18 while repository CI requires PostgreSQL 17.
- CI wiring for PostgreSQL 17 and fresh local Supabase now includes migration 028, smoke 0068, and API/RLS allowlist updates; CI has not yet run on a PR head.
- No migration was applied to the hosted project. No authenticated Eve user session was used, so no hosted Today DTO/data result is claimed.
- Independent review found UUID-format, title-length, ownership metadata, money aggregation, and SQL coverage issues; fixes are in this branch. The follow-up review of the latest changes is pending.
- EVE-012.3 remains `in_progress` and is a declared dependency. EVE-013.1 and parent #21 remain open; this package is not Done and does not close UI04 operations, AT10, AT29, production DB, backup/restore, or release gates.
