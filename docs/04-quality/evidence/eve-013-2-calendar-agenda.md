# EVE-013.2 — Agenda/ay və ev/sahib filtrləri

Status: **`done` for the EVE-013.2 component scope**. Implementation PR #125 was squash-merged to `main`; PR CI, merged-main CI and independent review are complete. Ledger is 45/90 (50.0%). This does not close parent AT29 device acceptance, EVE-013.3 readiness/performance, or production release gates.

Date: 2026-11-17 (Asia/Baku). Parent issue: [#21](https://github.com/fuadoglu/eve/issues/21). Normative package: EVE-013.2 in `docs/05-delivery/work-packages.json`; UI: UI05 `/calendar`; contract: `GET /calendar` in `docs/03-engineering/openapi.json`; acceptance: AT29 and calendar query performance.

## Scope and contract audit

- EVE-013.1 dependency is merged and recorded as component-scope `done`.
- The existing `/calendar` OpenAPI contract requires `from`, `to`, and 1–100 `property_ids`; range is at most 93 days and reservations overlap as `[check_in,check_out)`. The complete `CalendarEnvelope` DTO is preserved; no OpenAPI, field-binding, enum, default, or data-dictionary change is intended.
- The repository had no `/api/v1/calendar` route or calendar projection RPC. These are necessary to connect UI05 to authorized data rather than a fake calendar; the read-only route and RPC are included under integrator-owned package paths.
- `GET /properties` itself is not implemented. Calendar filter choices use the additive internal `api.list_calendar_property_options` RPC. It returns only visible property id/account id/property name/area and the owner's display name; the latter is scoped by `property.read`, and profile email/phone are never returned.

## Implemented and merged

- Added `GET /api/v1/calendar` with strict date/property query validation, same-session active check, private/no-store/noindex headers, contract envelope, and safe errors.
- Added `api.get_calendar(date,date,uuid[])`: authorizes every requested property and fails the complete selection on any unauthorized ID; reads current-placement reservations under `reservation.read` and unreleased blocks under `property.read`; does not mutate domain state; bounds range and response size.
- Added `api.list_calendar_property_options(uuid,integer)` with profile-row RLS scoped to `property.read`; the UI owner filter uses names and only adds account ID disambiguation when display names collide.
- Added UI05 agenda and one-house month modes, owner/property filters, month navigation, loading/empty/error/unauthenticated/retry states, and accessible touch controls. Multi-property selection opens agenda by default; month mode is enabled only for one selected property. Empty data is explicitly not presented as reservation confirmation.
- Agenda now shows a visible “Davam edir” row when a reservation or block overlaps the range but began earlier. Calendar cards show hold expiry and label elapsed holds as awaiting state cleanup; the read-only query does not change occupancy.
- Removed incomplete ARIA grid roles; each date remains a native button with its selected state, so assistive technology receives a real button control.
- The client adapter only retains fields needed for rendering; the HTTP response itself keeps the full documented OpenAPI DTO.

## Verification to date

- `pnpm test:reservations`: **45/45 passed**, including the calendar contract/query/range/filter/carry-in/owner/hold-expiry cases.
- `pnpm typecheck`: passed after the review fixes.
- `pnpm build`: production build passed; `/api/v1/calendar` and `/calendar` are present as dynamic routes.
- `node scripts/docs-check.mjs`, `node scripts/verify-contracts.mjs`, JSON Schema validation (207 schemas; 14 positive and 23 negative examples), and prototype smoke (71 assertions) passed. A first schema-check invocation used a non-existent path; the documented `scripts/validate-schemas.py` command passed in an isolated temporary venv.
- Production Chromium mobile shell smoke: **124 assertions** passed at 320/360/390/430 px, including no-overflow, keyboard, axe and navigation checks. This smoke did not receive authenticated calendar data and does not prove the populated calendar grid layout. The <=340 px CSS now gives day cells a 44 px minimum width and height; populated-grid browser measurement remains open.
- Expired hold labels now schedule a local re-evaluation at the server-provided expiry timestamp; this is presentation only and GET remains non-mutating. The UI still relies on the device clock.
- The property-options RPC now checks `api.is_my_session_active()` itself; SQL smoke `0069` revokes the synthetic active session and expects the direct RPC call to fail with SQLSTATE `28000`.
- Docker daemon is unavailable (`docker info` failed); no local PostgreSQL migration/DB smoke result is claimed. Final PR-head CI [#44090271956](https://github.com/fuadoglu/eve/actions/runs/44090271956) passed `docs`, PostgreSQL 17 `sql_schema` (migration 029 and smoke 0069, including revoked-session denial and an actor with no property membership), and synthetic Supabase `supabase_local` (active-session RPC calls, mixed authorized/foreign rejection, API allowlist/RLS coverage, and HTTP boundaries). The squash merge is `36bf81c430d65d80d52a523976e77304cc878e57`; merged-main CI [#44090770483](https://github.com/fuadoglu/eve/actions/runs/44090770483) passed all three jobs on that commit. Independent final review found no remaining blocker; the reviewer did not run tests independently. Earlier failed runs and fixture corrections remain in CI history.

## Open risks and limitations

- The API route depends on migration 029 in each target environment; until it is applied there, calendar loading fails closed. The migration is not applied to a hosted Eve staging/production database.
- Independent review found and the implementation addresses carry-in reservations/blocks, UUID-only owner labels, mismatched ARIA grid semantics, direct RPC access after session revocation, the 320 px touch target and stale expiry labels. A possible RLS recursion concern was closed by the PostgreSQL 17 no-membership actor smoke plus final static review.
- The authenticated populated month/agenda grid and its screen-reader interaction have not been browser-verified. The generic mobile shell smoke exercised the calendar route's unauthenticated fail-closed state; 320 px target width is covered by CSS dimensions and independent review, not a populated-grid screenshot.
- No staging/production migration, authenticated hosted response, real-device AT29, p95 query performance, backup/restore, or production readiness is claimed. EVE-013.3 retains readiness and interval-performance acceptance.
