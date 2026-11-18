# EVE-017.3 — scoped task link boundary

Task: EVE-017.3, parent EVE-017 / issue #25. Acceptance: AT15–16.

## Implemented

- Forward migration 035 adds **server-only** task link mint/revoke RPCs and a service-only scoped read/transition bridge. A verified user session supplies actor and session IDs; the database checks that exact active session again, then checks actor, task, owner, property, active entitlement, expiry (at most 30 days and due + 48 hours), exact scopes, revoke and idempotency. Direct authenticated/anonymous Data API grants for mint/revoke are absent. The database stores bearer and idempotency hashes; raw token is returned only by the server mint route.
- `POST /tasks/{id}/share-link` derives a 256-bit HMAC token with `EVE_SCOPED_LINK_HMAC_KEY`, the verified actor, task and request key. A retry produces the same URL; a changed request with the same key is rejected. The key is server-only and must be 64 lowercase hex characters. It is never exposed to the browser. Rotation stops replay of old idempotency keys but existing links remain valid until expiry or revoke. The URL is built from canonical `APP_BASE_URL`; a forged request origin is rejected before mint.
- `GET /s/{token}/task` requires the exact HttpOnly scoped cookie hash from explicit `POST /link-session`. GET is read-only. Accept/report use same-origin POST, an idempotency key, and a DB transaction. Revoke is owner-only and applies to the next request. Responses are no-store/no-referrer/noindex.
- Forward migration 039 extends only the scoped report bridge: valid OpenAPI `expense_proposal` writes a single `proposed`/`unpaid` expense with the task/link owner and one exact-sum allocation to the linked property **in the same transaction** as `report_done`, media association and owner outbox. The property is derived from the task/link, never accepted from the client. A link/action-scoped SHA-256 idempotency key and canonical request hash bind the expense proposal to the transition event. Replay cannot insert a second expense; changed amount/note/category with the same key conflicts. Failure rolls back task state, expense and outbox together. Prior migration 035 is unchanged.
- Browser landing requires an explicit button before token exchange. It clears the bearer URL from browser history before the first fetch; no WhatsApp sent/read claim is made. Client success appears only after server acknowledgement. On an ambiguous network failure the same action/body reuses its idempotency key; a visible refresh action reads the current server state.

## Current verification

- `pnpm test:operations` — 14/14 passed, including GET/prefetch, missing/mismatched cookie, same-origin POST, proposed expense shape/scope, forged request host rejection, revoke and expiry handling, and deterministic 256-bit token derivation. `pnpm test:media` — 15/15 passed.
- `tsc --noEmit`, `pnpm build`, `node scripts/docs-check.mjs`, `node scripts/verify-contracts.mjs`, schema validation, prototype smoke, and `git diff --check` passed on the PR head.
- PostgreSQL 16 temporary local cluster: migration 035/039 and SQL smoke 0074, EVE-016.1 regression smoke 0075, manager-invite isolation, API surface, and RLS coverage completed with `ON_ERROR_STOP=1`; all exited 0. These are local synthetic integration checks.
- PR #148 head `108c3d0` CI run [#44256825061](https://github.com/fuadoglu/eve/actions/runs/44256825061) passed `docs`, `sql_schema`, and fresh synthetic `supabase_local`.
- Squash merge commit `fbaad7109b186c8bc28a631eedf4d3073fbd6e31` merged-main CI [#44258465509](https://github.com/fuadoglu/eve/actions/runs/44258465509) passed all three jobs, including migration 035/039 smoke, API/RLS allowlists, fresh Supabase HTTP denial checks, and cookie-scoped browser-to-PostgreSQL reservation regression.
- Independent final integration review of PR head `108c3d0` found no concrete blocker. The reviewer did not run tests; test claims above are from local command and CI results.

## Contract coordination and limits

The shared data dictionary, `EVE_SCOPED_LINK_HMAC_KEY` environment contract, `ScopedTask.title` OpenAPI maxLength 180 (matching DB), CI migration/smoke sequence and API/RLS allowlists are updated on the integration branch. The media scoped cookie now uses a generic path that omits its raw bearer token. PR-head review, PostgreSQL 17/fresh synthetic Supabase CI, and merged-main regression passed as recorded above. Hosted Eve Supabase application, WhatsApp delivery and production deployment are not evidenced here. The browser test is synthetic, not real-device proof. EVE-018 readiness recompute/notification delivery and full AT16 across parent scopes remain outside this package and open.
