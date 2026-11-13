# EVE-007.1 — Email request and confirmation evidence

Status: **implementation in progress; not Done**. This record covers local code and contract behavior only. No hosted Supabase project, SMTP provider, real email, or production credential was used.

## Acceptance mapping

| Acceptance | Local artefact and evidence | Boundary |
|---|---|---|
| Email request and confirm/resend artefacts with positive behavior | `/login` and `/login/check-email`; `POST /api/v1/auth/email-link`; `GET /auth/confirm` renders a landing page without consuming the token; explicit user submit sends `POST /api/v1/auth/confirm`. `tests/unit/identity/auth.test.ts` covers accepted request, validation, throttling response, provider failure, explicit confirmation, expired/replay, and scanner-safe landing behavior. | API paths match OpenAPI's `/api/v1` server prefix. Request acknowledgement means only that the provider request was accepted; it does not prove account existence or delivery. The 60-second resend and 15-minute link TTL are response policy values; hosted provider configuration and durable IP/email throttling are unverified. |
| Component/contract scope and provider separation | Supabase adapter uses `@supabase/ssr`, PKCE and request-scoped HttpOnly cookies. Canonical `APP_BASE_URL` fixes redirects; user input cannot select an origin. OpenAPI confirm operation includes the documented 410 expired-link response. | Unit tests use injected providers. They do not prove Supabase hosted behavior, real cookies, scanner behavior across email clients/devices, or SMTP delivery. `@supabase/ssr` is a beta package and its installed API may change. |
| Downstream interface consistency | `docs/03-engineering/openapi.json`, `ARCHITECTURE.md`, and `INTEGRATIONS.md` updated with the fixed redirect and evidence boundary. | Parent AT01–03 and production auth gate remain open; refresh/logout belongs to EVE-007.2. |

## Local checks

| Check | Result |
|---|---|
| `pnpm typecheck` | Passed locally. |
| `pnpm test:identity` | 11/11 passed locally, including actual `/api/v1` route wrapper validation and noindex/private headers. |
| `pnpm test:env` | 10/10 passed locally. |
| `node scripts/docs-check.mjs` | Passed locally. |
| `node scripts/verify-contracts.mjs` | Passed locally: 117 operations, 52 tables, 255 field bindings, 90 packages, 36 scenarios. |
| `python3 scripts/verify-storage-config.py` | Passed locally. |
| `node scripts/test-prototype.mjs` | 71 synthetic VM/fake-DOM assertions passed; not browser/backend evidence. |
| `pnpm build` | Passed locally after the `/api/v1` route-prefix adjustment. Next.js reported both `/api/v1/auth/confirm` and `/api/v1/auth/email-link`, with the separate `/auth/confirm` landing page. |
| `pnpm test:ui` | 124 assertions passed locally against the final production build on port 4177: 320/360/390/430 widths, safe area, accessibility tree, axe checks, keyboard, 404 recovery and overflow. The test exercises the existing mobile shell, not the new auth flow. |
| Python JSON Schema validator | Passed locally: 207 schemas, 12 positive and 20 negative examples. |

Independent read-only QA/red-team review found no code blocker after the route-prefix correction. This is not GitHub human approval. No CI run or merge exists yet.

## Remaining evidence and limitations

- No CI run exists for this branch yet; this evidence is not a PR merge or Done record.
- Real SMTP delivery/template, Supabase provider TTL, hosted session cookie behavior and durable server-side IP/email limits require the appropriate staging setup.
- AT01–03 scanner, replay, expiry, cross-device and rate-limit acceptance has not been run against the real provider.
- Session refresh/logout-all is outside this package and remains EVE-007.2.
- This implementation does not establish production readiness.
