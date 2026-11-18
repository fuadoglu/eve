# EVE-017.3 — scoped task link boundary

Task: EVE-017.3, parent EVE-017 / issue #25. Acceptance: AT15–16.

## Implemented

- Forward migration 035 adds **server-only** task link mint/revoke RPCs and a service-only scoped read/transition bridge. A verified user session supplies actor and session IDs; the database checks that exact active session again, then checks actor, task, owner, property, active entitlement, expiry (at most 30 days and due + 48 hours), exact scopes, revoke and idempotency. Direct authenticated/anonymous Data API grants for mint/revoke are absent. The database stores bearer and idempotency hashes; raw token is returned only by the server mint route.
- `POST /tasks/{id}/share-link` derives a 256-bit HMAC token with `EVE_SCOPED_LINK_HMAC_KEY`, the verified actor, task and request key. A retry produces the same URL; a changed request with the same key is rejected. The key is server-only and must be 64 lowercase hex characters. It is never exposed to the browser. Rotation stops replay of old idempotency keys but existing links remain valid until expiry or revoke. The URL is built from canonical `APP_BASE_URL`; a forged request origin is rejected before mint.
- `GET /s/{token}/task` requires the exact HttpOnly scoped cookie hash from explicit `POST /link-session`. GET is read-only. Accept/report use same-origin POST, an idempotency key, and a DB transaction. Revoke is owner-only and applies to the next request. Responses are no-store/no-referrer/noindex.
- Forward migration 039 extends only the scoped report bridge: valid OpenAPI `expense_proposal` writes a single `proposed`/`unpaid` expense with the task/link owner and one exact-sum allocation to the linked property **in the same transaction** as `report_done`, media association and owner outbox. The property is derived from the task/link, never accepted from the client. A link/action-scoped SHA-256 idempotency key and canonical request hash bind the expense proposal to the transition event. Replay cannot insert a second expense; changed amount/note/category with the same key conflicts. Failure rolls back task state, expense and outbox together. Prior migration 035 is unchanged.
- Browser landing requires an explicit button before token exchange. It clears the bearer URL from browser history before the first fetch; no WhatsApp sent/read claim is made. Client success appears only after server acknowledgement. On an ambiguous network failure the same action/body reuses its idempotency key; a visible refresh action reads the current server state.

## Current verification

- `pnpm test:operations` — 14/14 passed, including GET/prefetch, missing/mismatched cookie, same-origin POST, proposed expense shape/scope, forged request host rejection, revoke and expiry handling, and deterministic 256-bit token derivation.
- `tsc --noEmit` — passed.
- `pnpm build` — passed and lists all task routes and landing page.
- `node scripts/docs-check.mjs` and `node scripts/verify-contracts.mjs` — passed (91 Markdown files, 118 operations, 90 packages).
- `git diff --check` — passed.
- PostgreSQL 16 temporary local cluster: all main migrations through 034, branch migrations 035 and 039, then SQL smoke 0074 and EVE-016.1 regression smoke 0075 passed with `ON_ERROR_STOP=1`. 0074 checks direct authenticated denial, missing active session, cross-owner mint/revoke, GET purity, scoped action denial, expired/revoked links, invalid amount and cross-property input, one proposed/unpaid allocation, replay count and changed-payload conflict. This is local synthetic integration proof. PostgreSQL 17 CI and fresh Supabase HTTP smoke must still pass before counting this package done.
- Integrator's rebased branch additionally applied 035/039 on the merged 034 schema and reran 0074, `0062_api_surface_smoke.sql`, and `0062_rls_coverage_smoke.sql` in PostgreSQL 16 with `ON_ERROR_STOP=1`; all exited 0. It ran operations 14/14, media 15/15, typecheck, docs/contracts/schema/prototype validators and `git diff --check`, all exit 0. The API allowlist now checks the four service-only bridge functions and 42 total RPCs; RLS checks 161 policies and the scoped write-policy roles. This is still local synthetic evidence.

## Contract coordination and limits

The shared data dictionary, `EVE_SCOPED_LINK_HMAC_KEY` environment contract, `ScopedTask.title` OpenAPI maxLength 180 (matching DB), CI migration/smoke sequence and API/RLS allowlists are updated on the integration branch. The media scoped cookie now uses a generic path that omits its raw bearer token. The landing page is a functional local flow; hosted Supabase credentials/configuration, WhatsApp delivery and production deployment are not evidenced here. UI test is synthetic, not real-device proof. Package closeout still requires independent review, PostgreSQL 17/fresh Supabase CI and merged-main regression. Readiness recompute/notification delivery belongs to EVE-018; full AT16 across parents is not claimed.
