# EVE-015.2 — Versioned realtor settlement

## Scope and status

Implements the D44 realtor balance read and append-only settlement write at the database command and HTTP adapter layers. EVE-015.2 is `done` for this component/API package after PR #142 merge, PostgreSQL 17 and synthetic Supabase CI, and independent review. It does not claim hosted Eve database deployment, provider acceptance, full AT13 concurrency/no-double-income acceptance, or production readiness.

## Implemented behavior

- `GET /reservations/{id}/realtor-balance` reads the aggregate `realtor_accounts.version` and C/T/E/P/O-derived integer-qəpik totals. It requires `finance.read`; the GET path contains no writes.
- `POST /reservations/{id}/realtor-settlements` uses the cookie-authenticated active session, origin check, strict DTO parser and Idempotency-Key. A narrow `api.record_realtor_settlement` transaction checks current reservation, placement, entitlement, owner/full-manager finance authority and contact/account scope.
- Settlement writes are append-only. Realtor→owner cash is bounded by held rent, owner→realtor cash by unpaid earned commission, and offset by the lesser of both; commission prepayment is rejected. No settlement inserts a rent entry.
- `C` follows D44’s exact rent-receipt scope: realtor-custody `rent_receipt` less its linked refund/reversal. Deposit receipts and `deposit_to_rent` allocation or their linked refund/reversal do not enter C and do not bump the settlement version. Reversing a refund restores C only when that refund traces to a `rent_receipt`.
- The reservation lock serializes balance inputs. D44-affecting realtor receipt/refund/reversal inserts bump the matching aggregate version; existing reservation commission update and cancellation review commands already increment it. Settlement stores its resulting `balance_version` and a canonical request hash.
- Idempotency replay checks the same actor/resource/key and canonical payload before `expected_version`; exact replay returns its original settlement/version, changed payload conflicts, and new stale writes conflict.
- The migration retains `app_private` base-table denial, `app_executor` SECURITY DEFINER functions with an empty search path, RLS policies, authenticated-only API grants and anon denial.

## Verification

**Completed locally on Node 24.22.2 and pnpm 12.18.0:**

- `pnpm install --frozen-lockfile` — passed; lockfile unchanged.
- `pnpm test:finance` — 13/13 passed, including request validation, same-origin, privacy headers and response DTO validation.
- `pnpm typecheck` — passed.
- `pnpm build` — passed; Next.js included both realtor endpoints.
- `node scripts/docs-check.mjs` — passed (89 Markdown files).
- `node scripts/verify-contracts.mjs` — passed (118 operations, 56 tables, 258 field bindings, 90 packages).
- `python scripts/validate-schemas.py` with `scripts/requirements-docs.txt` — passed (207 schemas, 14 positive and 23 negative examples).
- `node scripts/test-prototype.mjs` — passed (71 fake-DOM assertions; not an application/browser test).
- `git diff --check` — passed.

**CI and independent review:**

- PR #142 head CI [#44173072955](https://github.com/fuadoglu/eve/actions/runs/44173072955) passed `docs`, PostgreSQL 17 `sql_schema` and fresh synthetic `supabase_local`.
- Merged-main CI [#44173539341](https://github.com/fuadoglu/eve/actions/runs/44173539341) passed all three jobs: `docs`, PostgreSQL 17 `sql_schema` and fresh synthetic `supabase_local`.
- The PostgreSQL smoke covers owner create/read/write, full-manager finance read, daily and cross-tenant denial, anon/direct-table grant boundaries, receipt/refund version bumps, deposit exclusion and refund/reversal lineage, transfer/offset bounds, stale version, replay/conflict and unchanged rent-entry count.
- Independent read-only implementation review found and helped close three concrete issues (deposit activity in C/version, refund lineage, migration-role trigger grant ordering); final follow-up found no blocker. Reviewer did not run tests.
- PR #142 squash-merged as `b95805315b5dd6d948e4320b01fdf2bdfa27ce10`.

## Limitations

The manager has no separate realtor account list/detail UI, the owner panel does not yet expose settlement controls, and existing guest-facing finance pages are outside this package. The implementation is component/API scope only; AT13 full concurrent-write/no-double-income QA is EVE-015.3. Hosted Eve migration application, backup/restore and release gates remain open.
