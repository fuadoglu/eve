# EVE-012.3 — Placement history and permission regression

## Scope and status

Status: `in_progress`. The merged placement-history guard is extended by an in-progress same-owner move RPC and authenticated HTTP route. EVE-012.3 is not closed: the move command covers the property-move slice only; date changes, early departure, remaining-day release and the complete AT10 transition matrix are still open.

Normative references: `docs/03-engineering/DATA-MODEL.md` §§4–5, `docs/04-quality/ACCEPTANCE.md` AT10, and `docs/05-delivery/work-packages.json` EVE-012.3.

## Implementation under review

- Migration `20261116002600_eve_reservation_placement_history_guard.sql` rejects placement deletion, mutation of snapshot/identity columns, invalid closure, and a second closure. The only permitted placement update is the one-way `effective_to: NULL → timestamp` transition strictly after `effective_from`.
- `0066_reservation_placement_history_smoke.sql` covers positive and negative cases for the guard and verifies source-only versus target manager visibility around a synthetic current-placement pointer update. It verifies the authenticated client cannot access the private placement table directly.
- `20261116002700_eve_reservation_move.sql` adds an idempotent, versioned same-owner move command. It rechecks both property capabilities and active entitlements, obtains source/target property locks in deterministic UUID order through hold catch-up, transfers occupancy and placement history atomically, snapshots rather than moves ledger attribution, cancels future unfinished cleaning tasks through transition events, creates generic target cleaning tasks, revokes old-placement task/guest links, and appends audit/outbox records.
- `POST /api/v1/reservations/{id}/move` uses the cookie-scoped session and returns success only after a validated server acknowledgement and DTO. The API reason limit is aligned to the existing audit column limit.
- Decision D41 records the privacy-minimal cleaning-task copy behavior: only due time and readiness requirement transfer; title is generic, and description, assignee, media and private links do not.
- `0067_reservation_move_smoke.sql` is synthetic PostgreSQL role-switched coverage for unauthorized source-only/cross-owner moves, stale version, target occupancy conflict and rollback, successful owner move, same-key replay/payload conflict, balances, task event/history, link revocation, audit/outbox and post-move source/target visibility.
- CI runs the migration and smoke in the PostgreSQL 17 schema job; the fresh local Supabase job runs the smoke after migration application.

## Evidence

- `node scripts/docs-check.mjs` — passed (79 Markdown files).
- `node scripts/verify-contracts.mjs` — passed (118 operations, 56 tables, 256 field bindings, 90 acyclic packages, 36 scenarios).
- `/tmp/eve0222-schema-venv/bin/python scripts/validate-schemas.py` — passed (207 schemas, 12 positive and 20 negative examples).
- `node scripts/test-prototype.mjs` — passed (71 assertions; VM/fake-DOM scope only).
- `git diff --check` — passed.
- `node --conditions=react-server --experimental-strip-types --test tests/unit/reservations/*.test.ts` — passed (33/33), including move route validation, server acknowledgement and safe error behavior.
- `node node_modules/typescript/bin/tsc --noEmit` — passed.
- PostgreSQL 17 PR CI runs [#43820047081](https://github.com/fuadoglu/eve/actions/runs/43820047081), [#43820385039](https://github.com/fuadoglu/eve/actions/runs/43820385039), and [#43821152667](https://github.com/fuadoglu/eve/actions/runs/43821152667) iteratively exposed and helped correct the task fixture unique index, temporary function-owner schema grant, runtime UUID format, strict API allowlist, task transition idempotency scope, and private-table grant/policy allowlists. The final PR head `e60466524e5e86b1a63f9a23c24a8515d0728af1` passed all three CI jobs in run [#43821706633](https://github.com/fuadoglu/eve/actions/runs/43821706633): docs, PostgreSQL 17 `sql_schema` (including the move transaction and RLS/grant coverage smoke), and fresh synthetic Supabase `supabase_local`. Independent static review found no remaining definite SQL/smoke blocker; date changes and early-departure behavior remain outside this increment. Docker is unavailable locally, so the DB execution evidence is CI synthetic, not a hosted Eve database.
- Local Next.js production build and preview — `next build` passed; `next start` served `/calendar` with HTTP 200. Initial no-config preview showed the expected connection state. A follow-up used the `eve-hosted-migration-check` publishable key and a synthetic Auth user/session; Auth verification worked, but calendar RPCs returned `PGRST106 Invalid schema: api` because the hosted project does not expose the repo's API schema. The broader hosted configuration status and evidence are in `eve-hosted-migration-check-2026-11-14.md`.
- Initial PR CI run [#43816716512](https://github.com/fuadoglu/eve/actions/runs/43816716512) failed in the placement smoke: the first version incorrectly assumed the trusted internal `app_executor` role could not select historical rows. Existing media-proxy policy intentionally grants that role row access; it is not granted to `authenticated`. The smoke was corrected to assert that authenticated clients have no direct private-table access.
- Corrected PR CI run [#43817148464](https://github.com/fuadoglu/eve/actions/runs/43817148464) — passed all three jobs: `docs`, PostgreSQL 17 `sql_schema` including migration and smoke, and fresh synthetic `supabase_local` including the smoke and full local HTTP/browser checks.
- Local SQL execution — not run: Docker daemon is unavailable and no local PostgreSQL server answers on `localhost:5432`; database evidence above is CI synthetic. Only a synthetic Auth identity was added to the hosted migration-test project; no reservation/property data, staging, or production database was changed.
- Independent read-only review — no defect found in the trigger logic or corrected permission boundary assertion. Review confirmed that this synthetic pointer update does not meet AT10 move/side-effect acceptance; EVE-012.3 remains `in_progress` and is not counted done.

## Explicitly open

- Verify the move migration and smoke in PostgreSQL 17 CI, complete independent review, merge the scoped increment, then record merged-main CI evidence.
- Add and prove the remaining documented AT10 date-change and early-departure / remaining-day-release behavior in the proper package scope.
- EVE-012.3 acceptance, parent #20 and package ledger closure remain open until all owned criteria and review evidence are complete.

This package is not production-ready evidence and does not claim any hosted database or production change.
