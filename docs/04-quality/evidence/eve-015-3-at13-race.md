# EVE-015.3 — AT13 istiqamət və double-income race acceptance

Status: **implementation in progress; acceptance is not yet claimed**.

## İzləmə və ownership

- Parent issue: [#23 — EVE-015](https://github.com/fuadoglu/eve/issues/23)
- Branch: `feat/EVE-015-3-at13-race`
- Worktree: `/Users/fuadoglu/.codex/worktrees/eve0153-at13-race`
- Pull request: [#144](https://github.com/fuadoglu/eve/pull/144), currently draft; final implementation head `62f16407c6bbe533ff8e0bd541e74063f627444a`.
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

- `supabase/tests/0072_realtor_settlement_smoke.sql` — added exact AT13 initial due assertion and the alternative full-transfer case with rent-entry count comparison. Execution pending CI PostgreSQL 17.
- `scripts/test-db-concurrency.py` — added a synthetic isolated owner/reservation fixture and synchronized two-session settlement race. Python syntax and `git diff --check` pass. Execution pending PostgreSQL 17 CI.
- Local runtime: Node `v24.5.0` is below the repository-pinned Node `24.22.2`; pinned pnpm `12.18.0` is unavailable in this worktree runtime. Local Docker was not reported by the attempted version command. No local database result is claimed.
- Independent read-only review found no AT13/D44 acceptance blocker and identified fixture cleanup edge cases. Setup is transactional; cleanup now covers receipt failures and subprocess execution, including failure to start the first race process. The reviewer did not run tests.
- `node scripts/docs-check.mjs` — PASS; `node scripts/verify-contracts.mjs` — PASS; Python schema validator — PASS (207 schemas, 14 positive and 23 negative examples); `node scripts/test-prototype.mjs` — PASS (71 synthetic assertions); `python3 -m py_compile scripts/test-db-concurrency.py` — PASS; `git diff --check` — PASS.
- PR-head CI [#44177467308](https://github.com/fuadoglu/eve/actions/runs/44177467308) passed `docs`, PostgreSQL 17 `sql_schema` (including migration 032, SQL smoke 0072, and `scripts/test-db-concurrency.py`), and fresh synthetic `supabase_local`.
- The two earlier CI attempts exposed a JSON formatting `KeyError` and a literal `\\n` in the test harness. Both were corrected; the final-head CI run above passed.
- Final-head independent review, squash merge, merged-main CI, and package closeout are pending.

## Limits

These are synthetic PostgreSQL acceptance fixtures, not hosted Eve database, real user, device, or production evidence. EVE-015 parent remains open until its full documented acceptance and other package gates close.
