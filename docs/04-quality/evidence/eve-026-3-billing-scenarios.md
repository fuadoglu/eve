# EVE-026.3 — Trial/leap/month-end/plan-transition scenarios

Status: **partial local scenario evidence; EVE-026.3 remains open**. This suite exercises the local calendar-period component across a single multi-step purchase timeline. The work-package expected result additionally requires a real integration result for the parent acceptance scenario; this helper-only suite does not meet that requirement, so it is not counted as Done.

## Scenario covered

- A verified annual purchase before trial end begins at the exact trial boundary.
- A February 29 Asia/Baku anchor clamps in a non-leap year while preserving its original day, month and microsecond time.
- Early annual renewal queues at the preceding paid period end and advances one calendar year.
- Annual-to-monthly switch starts at the current period boundary and preserves the documented day/time anchor.
- The following monthly period proves the original day anchor did not drift after the February clamp.
- Corrupt prior history with a zero-length period fails closed.

## Verification

- Node 24.22.2 / pnpm 12.18.0 `pnpm test:billing` — **14/14 passed** (12 catalog/period cases and 2 cross-period scenario cases).
- `pnpm typecheck` — passed.
- `pnpm build` — passed.
- `node scripts/docs-check.mjs` — passed, 75 Markdown files.
- `node scripts/verify-contracts.mjs` — passed, 118 operations, 56 tables, 256 field bindings, 90 acyclic packages, 16 trace rows, 36 scenarios.
- `/tmp/eve0222-schema-venv/bin/python scripts/validate-schemas.py` — passed, 207 schemas; 12 positive and 20 negative examples.
- `python3 scripts/verify-storage-config.py` — passed, seven private buckets aligned.
- `node scripts/test-prototype.mjs` — passed, 71 synthetic VM/fake-DOM assertions; not browser/device or billing UI evidence.
- `git diff --check` — passed.
- GitHub PR CI and merge-commit CI — not run; this partial suite is not being submitted as a completed work package.

This is local component-level scenario coverage only. It does not prove AT25 database concurrency/idempotency or AT28 persisted expiry authorization, safety QR continuity, task write windows, provider reconciliation or production behavior. The package remains backlog and contributes no ledger percentage until the documented real integration evidence exists.
