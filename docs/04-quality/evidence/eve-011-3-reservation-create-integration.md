# EVE-011.3 — Reservation create integration

## Scope

Package scope was corrected before implementation because the former “AT07–11 E2E” acceptance included downstream work that EVE-012 and EVE-014 depend on EVE-011.3 to implement. This package now covers authenticated reservation creation, form validation and acknowledgement, create idempotency, occupancy conflict/expired-hold behavior, and the initial receipt/server balance slice. Parent issue #19 remains open for full AT07–11 acceptance. Public availability stays in EVE-025; reservation transitions stay in EVE-012; refunds and overpayment stay in EVE-014.

## Implemented

- Calendar reads only currently writable property contexts through the cookie-scoped authenticated Supabase client.
- Reservation form submits to `POST /api/v1/reservations`; the route enforces same-origin JSON requests against canonical `APP_BASE_URL` and an idempotency key. Browser POSTs that omit `Origin` use same-origin Fetch Metadata, a same-origin `Referer`, or the form's custom `X-Eve-Same-Origin` header only when the request Host matches canonical `APP_BASE_URL`; cross-site fetch metadata is rejected.
- The route requires an authenticated, active session and calls `api.create_reservation` and then the scoped safe DTO RPC using the user's session. It does not use the service role.
- A success response is returned only after the server DTO passes the existing reservation envelope parser. The UI shows the detail/balance only after that acknowledgement.
- Safe DTO balance projection accounts for receipt/refund/deposit entries and reversals. SQL smoke verifies retry and reversal cases.
- SQL API/RLS allowlists and CI include the new property-context and reservation DTO RPCs.

## Verification

| Check | Result |
|---|---|
| Reservation unit tests | Passed, 21/21 via `node --conditions=react-server --experimental-strip-types --test tests/unit/reservations/*.test.ts`; includes absent-Origin Referer/Fetch Metadata/custom-header fallback, cross-site rejection, canonical Host/Origin enforcement, empty-Origin rejection, and missing-config fail-closed behavior |
| Browser integration script syntax | Passed via `node --check scripts/test-reservation-route-http.mjs`; the browser-to-PostgreSQL script itself is pending CI because local Docker is unavailable |
| TypeScript | Passed via `node node_modules/typescript/bin/tsc --noEmit` |
| Next production build | Passed via `node node_modules/next/dist/bin/next build` |
| Documentation links/IDs | Passed via `node scripts/docs-check.mjs` |
| Contract/dependency checks | Passed via `node scripts/verify-contracts.mjs` |
| JSON Schema examples | Passed: 207 schemas, 12 positive and 20 negative via `/tmp/eve0222-schema-venv/bin/python scripts/validate-schemas.py` |
| Prototype smoke | Passed: 71 assertions via `node scripts/test-prototype.mjs`; this is VM/fake-DOM evidence only |
| PostgreSQL 17 migration/RLS/DTO smoke | Not run locally: Docker daemon is unavailable and no local PostgreSQL server is listening. CI evidence is pending. |
| Browser form through cookie-scoped route into PostgreSQL | Not yet proven; package remains `in_progress` and is not counted done. |

Local `pnpm` could not start because the pinned Corepack file is missing; repository Node is 24.5.0, below its declared 24.22.2 floor. Direct Node test/typecheck/build commands above did run successfully. No hosted Eve database or production environment was changed.
