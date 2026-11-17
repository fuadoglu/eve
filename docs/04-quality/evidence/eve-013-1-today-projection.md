# EVE-013.1 — Today projection

Status: **`done` for the EVE-013.1 component scope**. This does not establish full AT29 acceptance or production readiness.

Date: 2026-11-17 (Asia/Baku). Parent issue: [#21](https://github.com/fuadoglu/eve/issues/21). Normative package: EVE-013.1 in `docs/05-delivery/work-packages.json`; product ordering: D42; UI: UI04 `/today`.

## Implemented scope

- `GET /api/v1/today` validates the documented query, requires a verified active Supabase session, calls the user-scoped `api` schema, and returns the private/no-store `TodayEnvelope` contract.
- `api.get_today` is a read-only `app_executor` RPC. It validates active session/current property scope and projects current-placement arrivals/departures, eligible task states, arrival-day rent remaining (excluding deposits), and subscription expiry on the property's Asia/Baku date.
- D42 ordering is overdue tasks, arrivals/departures, today's tasks, arrival-day rent, then subscriptions expiring today; ties use due time (null last) and resource ID. Expense and inspection cards are not inferred because their due/problem rule is unspecified.
- `/today` distinguishes loading, unauthenticated/error, empty, and populated responses. Cards display the server-declared next operation. Downstream details/transitions remain separate work, so card actions are not claimed executable.
- Aggregated money uses `BigInt` to preserve integer qəpik. SQL fixtures cover placement, rent/deposit, subscription, task, and tenant-scope cases.

## Verification

- Local Today contract tests: **4/4 passed**; TypeScript typecheck, Next.js production build, docs/contracts/schema/prototype/storage validators passed. Local Node was 24.5.0, below the repo minimum 24.22.2; these local results are diagnostic.
- Final PR head `2084accb90abd3d820a480178664699f87627403` passed all three CI jobs in [run #44035837054](https://github.com/fuadoglu/eve/actions/runs/44035837054): `docs`, PostgreSQL 17 `sql_schema`, and synthetic Supabase `supabase_local`. The SQL job applied the Today and AT10 migrations and ran their smokes with the combined API/RLS allowlists. The docs job included the pinned Node runtime, typecheck/build, browser shell smoke, and contract validators.
- PR #121 was squash-merged as `8baad8f21da3069b88919a233db5082ec3324391`. Merged-main CI [#44036210386](https://github.com/fuadoglu/eve/actions/runs/44036210386) passed all three jobs on that commit.
- Independent read-only review found no concrete D42, implementation, SQL allowlist, RLS, or CI blocker. Reviewers did not run tests.

## Scope limits and external proof

- Local Docker was unavailable; no local PostgreSQL smoke is claimed. PostgreSQL 17 and synthetic Supabase evidence comes from CI.
- Migration 028 has **not** been applied to the hosted test project or production. The connected Supabase account lacks the required project privilege; no authenticated hosted Today DTO/data response is claimed.
- No live deployment, backup/restore, real-device AT29, screen-reader, or five-person usability acceptance is claimed. The mobile shell browser smoke is not real-device evidence.
- Downstream card destination and transition screens remain incomplete, so those actions are not claimed executable.
- EVE-012.3, a declared dependency, was completed for component scope on 2026-11-17 by PRs #122 and #123. The ledger was 43/90 (47.8%) immediately before EVE-013.1 closure.
