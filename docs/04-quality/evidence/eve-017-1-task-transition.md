# EVE-017.1 — Task transition database component

- **Task:** EVE-017.1, parent EVE-017 / GitHub issue #25
- **Feature branch:** `feat/EVE-017-1-task-history`
- **Feature commits:** `8d3c689` (implementation), `cb3cd86` (subscription RLS scope correction)
- **Feature PR:** [#95](https://github.com/fuadoglu/eve/pull/95), squash-merged
- **Main commit:** `b2b5c3b041a062e414e2392b709deeccce910751`
- **CI:** [run #43577303606](https://github.com/fuadoglu/eve/actions/runs/43577303606) — `docs`, PostgreSQL 17 `sql_schema`, and fresh synthetic `supabase_local` all passed.
- **Independent review:** read-only QA follow-up found no remaining blocker. The review is not represented as GitHub human approval; branch protection has zero required approvals.

## Implemented component

- Append-only task transition events and validated same-property `private_task` media associations.
- Version-checked `api.transition_task` command with actor/action-scoped idempotency and strict acknowledgement.
- Authenticated owner/manager path and server-only `service_role` scoped-link path; token hash, exact action scope, expiry, revoke, task/property scope are checked in the database. `anon` has no execute permission.
- A readiness-required task cannot be reported done unless a linked completed inspection submission has an answer for each snapshot room.
- `report_done` and a deduplicated owner-notice outbox event commit atomically.
- Scoped `app_executor` subscription read policy: owner or a current, non-revoked daily/full member of that property. CI caught and prevented a broader permissive policy from exposing pending invite data.

## Verification evidence

- `node scripts/docs-check.mjs` — passed (67 Markdown files; R01–16, AT01–36, EVE-001–030).
- `node scripts/verify-contracts.mjs` — passed (117 operations, 55 tables, 256 bindings, 90 acyclic packages, 16 trace rows, 36 scenarios).
- `node --conditions=react-server --experimental-strip-types --test tests/unit/operations/*.test.ts` — 3/3 passed.
- `node_modules/.bin/tsc --noEmit` — passed.
- `node node_modules/next/dist/bin/next build` — passed.
- Python schema validator — passed (207 schemas, 12 positive and 20 negative examples).
- Storage config validator — passed (7 private buckets).
- Prototype fake-DOM smoke — passed (71 assertions); this is not real-device proof.
- CI `sql_schema` — migration and transition smoke passed on PostgreSQL 17, including tenant/link scope, idempotent replay and mismatch, required-inspection rejection, media association, outbox, append-only behavior, RLS/grant catalog, API allowlist and concurrency suite.
- CI `supabase_local` — fresh synthetic stack, all SQL smoke suites, Data API and Storage negative HTTP matrix passed.
- `git diff --check` — passed.

Local Docker was unavailable, so PostgreSQL execution is evidenced by CI. CI uses synthetic local infrastructure; it is not hosted Eve staging/production proof.

## Scope limits and open acceptance

This package is the database transition component only. It does not implement a browser/HTTP route, scoped-link cookie exchange, WhatsApp handoff, notification worker/delivery, or full AT15–16. `confirm` does not recompute readiness because the normative recompute algorithm is not specified here. EVE-017.2/.3, hosted migration history, backup/restore, real device/accessibility evidence, and production gates remain open.
