# EVE-015.3 — AT13 istiqamət və double-income race acceptance

Status: **`done` for the EVE-015.3 component acceptance scope**. Parent EVE-015 acceptance is complete and issue #23 is ready to close after this closeout merge; release gates remain open.

## İzləmə və ownership

- Parent issue: [#23 — EVE-015](https://github.com/fuadoglu/eve/issues/23)
- Branch: `feat/EVE-015-3-at13-race`
- Worktree: `/Users/fuadoglu/.codex/worktrees/eve0153-at13-race`
- Pull request: [#144](https://github.com/fuadoglu/eve/pull/144), squash-merged as `8f43ee01b77709e5e0a4d70512f3f6b736930542`; final PR head `ce111683ba3e6a0ea24d4109cacd680da838ccb7`.
- Depends on: EVE-015.2 merged in PR #142; closeout PR #143.
- Owned paths: `supabase/tests/0072_realtor_settlement_smoke.sql`, `scripts/test-db-concurrency.py`, this evidence file, `docs/05-delivery/work-packages.json`, `docs/05-delivery/STATUS.md`, and `docs/INDEX.md`.
- Shared contract/API/schema/lockfile changes: none planned.

## Normative acceptance

The test covers the EVE-015.3 acceptance in `docs/05-delivery/work-packages.json` and AT13/D44:

1. 10,000 qəpik collected and 3,000 qəpik earned commission yields owner due 7,000 and realtor due 0; transferring 7,000 and offsetting 3,000 yields both due directions 0.
2. An alternative full 10,000 transfer yields owner due 0 and realtor due 3,000.
3. A settlement does not create a rent entry or change collected rent totals.
4. Two concurrent writes with distinct idempotency keys and the same balance version yield exactly one committed event and one stale-version conflict; aggregate version and all balances reflect the single committed event.

## Implementation and verification

- `supabase/tests/0072_realtor_settlement_smoke.sql` — added exact AT13 initial due assertion and the alternative full-transfer case with rent-entry count comparison. PostgreSQL 17 execution passed in PR CI #44178624582 and merged-main CI #44179202801.
- `scripts/test-db-concurrency.py` — added a synthetic isolated owner/reservation fixture and synchronized two-session settlement race. Python syntax and `git diff --check` pass; the race passed in PostgreSQL 17 CI #44178624582 and #44179202801.
- Local runtime: Node `v24.5.0` is below the repository-pinned Node `24.22.2`; pinned pnpm `12.18.0` is unavailable in this worktree runtime. Docker daemon is unavailable and local PostgreSQL is 14.18; no local database result is claimed.
- Independent read-only review found no AT13/D44 acceptance blocker and identified fixture cleanup edge cases, which were fixed. Setup is transactional; cleanup covers receipt failures and subprocess execution, including failure to start either race process. The reviewer did not run tests.
- `node scripts/docs-check.mjs` — PASS; `node scripts/verify-contracts.mjs` — PASS; Python schema validator — PASS (207 schemas, 14 positive and 23 negative examples); `node scripts/test-prototype.mjs` — PASS (71 synthetic assertions); `python3 -m py_compile scripts/test-db-concurrency.py` — PASS; `git diff --check` — PASS.
- Final-head independent read-only review for `f2d9f9f` found no AT13/D44 or harness blocker; the final docs-only PR head was checked for evidence accuracy. The reviewer did not run tests.
- Final PR-head CI [#44178624582](https://github.com/fuadoglu/eve/actions/runs/44178624582) and merged-main CI [#44179202801](https://github.com/fuadoglu/eve/actions/runs/44179202801) passed `docs`, PostgreSQL 17 `sql_schema` (including migration 032, SQL smoke 0072, and `scripts/test-db-concurrency.py`), and fresh synthetic `supabase_local`.
- The two earlier CI attempts exposed a JSON formatting `KeyError` and a literal `\\n` in the test harness. Both were corrected; the final-head run above passed.
- The EVE-015.3 implementation is merged and verified on main. Its package-ledger/evidence closeout is the only remaining repository change for this task.

## Limits

These are synthetic PostgreSQL acceptance fixtures, not hosted Eve database, real user, device, or production evidence. EVE-015/#23 component acceptance is complete; hosted migration, backup/restore, and production release gates remain open in their respective scopes.
