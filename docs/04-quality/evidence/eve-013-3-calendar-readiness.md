# EVE-013.3 — Təqvim readiness və interval query ölçümü

Tarix: 2026-11-17 (Asia/Baku). Status: **implementation in progress; CI və müstəqil review gözlənir**. Parent issue: [#21](https://github.com/fuadoglu/eve/issues/21).

## Scope

- EVE-013.3 acceptance: AT29 calendar mobile/accessibility readiness and interval query performance.
- Normativ interval `GET /calendar` OpenAPI, AT29 and PRD read p95 ≤500 ms target remain unchanged.
- Browser test uses a synthetic user and reservation in the repository's disposable Supabase stack; it is not production data or a provider-hosted test.
- PostgreSQL performance test seeds 5,000 valid, non-overlapping synthetic reservations for one property, queries one 30-day interval returning 30 records, measures 30 complete `api.get_calendar` calls, and enforces measured p95 ≤500 ms. CI prints the p95 notice. This measures the synthetic PostgreSQL RPC path, not hosted network, Next.js end-to-end, or real traffic.

## Verification plan

- Extend the existing authenticated browser-to-PostgreSQL E2E: create a reservation through the UI/API, load `/calendar`, navigate into the reservation month, assert the returned DB-backed reservation appears in agenda and month views, and verify keyboard day selection, the counted day button name/pressed state in the accessibility tree, and axe WCAG 2.2 AA scans of populated agenda and month states.
- At 320/360/390/430 CSS px, assert no horizontal document overflow and each rendered month-day button is at least 44×44 CSS px.
- Run PostgreSQL 17 `sql_schema` CI with the 5,000-row/30-sample interval p95 smoke. Existing `0069_calendar_projection_smoke.sql` continues to cover range bounds, half-open intervals, mixed/foreign property rejection, read purity, and revoked-session denial.
- Local focused reservation unit tests, typecheck/build, docs and contract validation are reported separately from CI PostgreSQL/browser integration.

## Local checks completed

- `pnpm test:reservations`: **45/45 passed**.
- `pnpm typecheck`: passed; `pnpm build`: passed on Node 24.22.2 / pnpm 12.18.0.
- `pnpm test:ui`: generic shell **124 assertions passed** at 320/360/390/430 px, including axe, keyboard, accessibility tree and no-overflow. This test does not contain authenticated calendar data.
- `node scripts/docs-check.mjs`, `node scripts/verify-contracts.mjs`, `python scripts/validate-schemas.py` (207 schemas; 14 positive, 23 negative examples), `python scripts/verify-storage-config.py`, `node scripts/test-prototype.mjs` (71 assertions), `node --check scripts/test-reservation-route-http.mjs`, and `git diff --check`: passed.
- Independent read-only review found no remaining concrete blocker after the populated-state axe/name/pressed-state checks were added. The reviewer did not execute tests.
- Local authenticated browser-to-PostgreSQL and PostgreSQL 17 perf smoke **not run**: Docker daemon is unavailable here. Awaiting required CI execution; no pass is claimed.

## Evidence boundary

- Docker is unavailable in this local environment; PostgreSQL 17 and authenticated browser-to-PostgreSQL acceptance must come from the repository CI job.
- CI evidence is synthetic local Supabase and Chromium emulation only. Real iPhone/Android keyboard, human screen-reader use, hosted Eve migration/application, hosted p95/traffic, backup restore, and production readiness remain open.
