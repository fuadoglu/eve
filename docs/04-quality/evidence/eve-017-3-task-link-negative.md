# EVE-017.3 — scoped task link boundary

Task: EVE-017.3, parent EVE-017 / issue #25. Acceptance: AT15–16.

## Implemented

- Forward migration 035 adds **server-only** task link mint/revoke RPCs and a service-only scoped read/transition bridge. A verified user session supplies actor and session IDs; the database checks that exact active session again, then checks actor, task, owner, property, active entitlement, expiry (at most 30 days and due + 48 hours), exact scopes, revoke and idempotency. Direct authenticated/anonymous Data API grants for mint/revoke are absent. The database stores bearer and idempotency hashes; raw token is returned only by the server mint route.
- `POST /tasks/{id}/share-link` derives a 256-bit HMAC token with `EVE_SCOPED_LINK_HMAC_KEY`, the verified actor, task and request key. A retry produces the same URL; a changed request with the same key is rejected. The key is server-only and must be 64 lowercase hex characters. It is never exposed to the browser. Rotation stops replay of old idempotency keys but existing links remain valid until expiry or revoke. The URL is built from canonical `APP_BASE_URL`; a forged request origin is rejected before mint.
- `GET /s/{token}/task` requires the exact HttpOnly scoped cookie hash from explicit `POST /link-session`. GET is read-only. Accept/report use same-origin POST, an idempotency key, and a DB transaction. Revoke is owner-only and applies to the next request. Responses are no-store/no-referrer/noindex.
- Browser landing requires an explicit button before token exchange. It clears the bearer URL from browser history before the first fetch; no WhatsApp sent/read claim is made. Client success appears only after server acknowledgement.

## Current verification

- `pnpm test:operations` — 13/13 passed, including GET/prefetch, missing/mismatched cookie, same-origin POST, forged request host rejection, revoke and expiry handling, and deterministic 256-bit token derivation.
- `tsc --noEmit` — passed.
- `pnpm build` — passed and lists all task routes and landing page.
- `node scripts/docs-check.mjs` and `node scripts/verify-contracts.mjs` — passed (91 Markdown files, 118 operations, 90 packages).
- `git diff --check` — passed.
- PostgreSQL 16 temporary local cluster: all existing 001–032 migrations, forward migration 035 and SQL smoke 0074 passed with `ON_ERROR_STOP=1`, including direct authenticated denial, missing active session, cross-owner mint/revoke, GET purity, scoped action denial and expiry. This is local synthetic integration proof. Docker daemon was absent; PostgreSQL 17 CI and fresh Supabase HTTP smoke must still pass before counting this package done.

## Contract coordination and limits

The integrator owns updates to the shared data dictionary for `access_links.idempotency_key_hash` / `request_hash`, the environment contract for `EVE_SCOPED_LINK_HMAC_KEY`, and `ScopedTask.title` OpenAPI maxLength 180 (DB permits 180; response is not truncated). The landing page is a functional local flow; hosted Supabase credentials/configuration, WhatsApp delivery and production deployment are not evidenced here. UI test is synthetic, not real-device proof. **This package remains partial:** `ScopedTaskDoneInput.expense_proposal` is specified by OpenAPI but the handler rejects it until EVE-016.1 provides the expense command and the integrator adds an atomic scoped transition + proposed expense wrapper. Readiness recompute/notification delivery belongs to EVE-018. Full AT16 is not claimed.
