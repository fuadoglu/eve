# EVE-013.2 — Agenda/ay və ev/sahib filtrləri

Status: **`in_progress`**. Acceptance is not closed until migration, API and UI checks, CI, and independent review all pass. Ledger remains 44/90 (48.9%).

Date: 2026-11-17 (Asia/Baku). Parent issue: [#21](https://github.com/fuadoglu/eve/issues/21). Normative package: EVE-013.2 in `docs/05-delivery/work-packages.json`; UI: UI05 `/calendar`; contract: `GET /calendar` in `docs/03-engineering/openapi.json`; acceptance: AT29 and calendar query performance.

## Scope and contract audit

- EVE-013.1 dependency is merged and recorded as component-scope `done`.
- The existing `/calendar` OpenAPI contract requires `from`, `to`, and 1–100 `property_ids`; range is at most 93 days and reservations overlap as `[check_in,check_out)`. The complete `CalendarEnvelope` DTO is preserved; no OpenAPI, field-binding, enum, default, or data-dictionary change is intended.
- The repository had no `/api/v1/calendar` route or calendar projection RPC. These are necessary to connect UI05 to authorized data rather than a fake calendar; the read-only route and RPC are included under integrator-owned package paths.
- `GET /properties` itself is not implemented. Calendar filter choices use the additive internal `api.list_calendar_property_options` RPC. It returns only visible property id/account id/property name/area and the owner's display name; the latter is scoped by `property.read`, and profile email/phone are never returned.

## Implemented locally so far

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
- Docker daemon is unavailable (`docker info` failed); no local PostgreSQL migration/DB smoke result is claimed. Initial PR CI run `44087423143` applied migration 029 but failed in smoke 0069's owner-option assertion; its `supabase_local` job also found the RLS policy inventory still expected 142 instead of 144 after the two added policies. Smoke 0069 now reports the mismatched projection fields, and the policy count is corrected; CI rerun is pending. Independent read-only follow-up review found no concrete blocker in the session guard/smoke, 320 px sizing, or expiry timer; the reviewer did not run tests.

## Open risks and limitations

- The API route depends on the new migration being applied; until migration and CI pass, local page data loading will fail closed and show an error.
- Independent review found and the implementation now addresses carry-in reservations/blocks missing from agenda, UUID-only owner labels, mismatched ARIA grid semantics, direct RPC access after session revocation, 320 px touch-target width, and stale expiry labels. The final targeted follow-up review found no concrete blocker; it was static and did not run tests.
- The populated month/agenda grid and owner/property filters have not yet had browser accessibility or 320/360/390/430 px checks; the generic mobile shell smoke exercised the calendar route's unauthenticated fail-closed state only.
- No staging/production migration, authenticated hosted response, real-device AT29, p95 query performance, backup/restore, or production readiness is claimed. EVE-013.3 retains readiness and interval-performance acceptance.
