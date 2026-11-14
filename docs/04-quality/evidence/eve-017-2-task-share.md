# EVE-017.2 — Task share handoff component

- **Task:** EVE-017.2, parent EVE-017 / GitHub issue #25
- **Feature branch:** `feat/EVE-017-2-task-share`
- **Feature commits:** `e13e6db` (handoff UI), `07bc7fb` (payload/URL bounds), `820c056` (full manual fallback)
- **Feature PR:** [#97](https://github.com/fuadoglu/eve/pull/97), squash-merged
- **Main commit:** `a6249c3afa5b901369c899c61ed043cb7b05248d`
- **CI:** [run #43578181675](https://github.com/fuadoglu/eve/actions/runs/43578181675) — `docs`, clean production build, Chromium mobile shell, PostgreSQL 17 `sql_schema`, and fresh synthetic `supabase_local` all passed.
- **Independent review:** found and the implementation corrected copied-payload label mismatch, a missing URL in fallback text, and encoded WhatsApp URL exceeding the OpenAPI 2048-character limit. Final follow-up found no remaining issues. This is not GitHub human approval; branch protection requires zero approvals.

## Implemented component

- `TaskSharePanel` consumes the existing server-acknowledged `ShareLinkResult` and shows the scoped URL and expiry.
- WhatsApp handoff uses only the fixed `https://wa.me/` origin. It is hidden when the encoded URL would exceed 2048 characters.
- Copied message contains both the server message and scoped URL, bounded to the OpenAPI 3000-character limit.
- Clipboard success is shown only after the browser resolves `writeText`; failure exposes a selectable full message+URL textarea for manual copy.
- UI copy makes no sent/read claim (`delivery_state: not_tracked`).

## Verification evidence

- `node --conditions=react-server --experimental-strip-types --test tests/unit/operations/*.test.ts` — 7/7 passed.
- `node_modules/.bin/tsc --noEmit` — passed (using a temporary symlink to existing dependencies, removed afterward).
- `node scripts/docs-check.mjs` — passed.
- `node scripts/verify-contracts.mjs` — passed.
- CI production build and Chromium mobile shell — passed.
- CI PostgreSQL 17 SQL and fresh synthetic Supabase smoke jobs — passed; this component adds no database migration.
- `git diff --check` — passed.

## Scope limits

This package is a UI component only. It does not mint/persist the scoped task token, implement `POST /tasks/{id}/share-link`, mount the component on a task route, or implement scoped cookie exchange. GET/prefetch/revoke endpoint tests, full AT15–16, real devices, hosted Eve Supabase, provider delivery, backup/restore, and production proof remain open.
