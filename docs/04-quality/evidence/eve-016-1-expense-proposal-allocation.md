# EVE-016.1 — Expense proposal and allocation component

## Scope and acceptance

`POST /api/v1/expenses` validates the documented category, safe integer AZN qəpik amount,
1–100 distinct property allocations, exact allocation sum, civil dates and optional task/contact
scope. The DB command checks every property against one owner, current actor capability and active
entitlement before inserting the header and all allocations in one transaction. Owner and a full
manager on every allocated property create an approved but unpaid expense; a daily manager creates
a proposed and unpaid expense. `mark_paid=true` is rejected in this component, so a proposal cannot
be reported as paid. Receipt media association remains closed until the validated media binding
path is wired. No provider or production payment is implied.

The `Idempotency-Key` requirement is enforced at HTTP and in the DB with the existing 24-hour
`idempotency_keys` record. The request hash is SHA-256 of canonical JSONB; same actor, key and
payload return the same expense, while a changed payload conflicts. Deferred constraint triggers
check the whole allocation sum at commit. The private header RLS helper checks **all** allocation
rows, including those hidden by row security, before a full manager sees the total. A manager with
only one property of a multi-property expense cannot see its header.
The forward migration removes the older permissive media `USING (true)` SELECT policies for
expense headers/allocations. The private receipt-media predicate now joins the bound allocation
directly, so a partial-scope manager may read the receipt for their property without seeing the
whole expense header. The SQL smoke tests both the actual table SELECT denial and allowed scoped
receipt read.
Allocation header IDs are immutable, so an UPDATE cannot move a row to another expense and leave
the old header below its required sum. The replay query accepts both `proposed` and `approved`
original rows, matching owner/full creation behavior.

## Verification

- Local `pnpm test:finance`: 15/15 passed, including safe integer, duplicate allocation,
  unauthorized Origin and server acknowledgement checks.
- Local `pnpm typecheck`: passed.
- `git diff --check`: passed.
- Local PostgreSQL 16 temporary cluster: all 34 migration files through `034` applied with
  `ON_ERROR_STOP=1`; `0075_expense_proposal_allocation_smoke.sql`,
  `0062_api_surface_smoke.sql`, `0062_rls_coverage_smoke.sql`, and existing
  `0222_media_access_smoke.sql` each exited 0. The test
  asserts approved owner replay, sum/cross-owner rejection, immutable allocation header, full
  header visibility guard and daily proposed/unpaid state. This is synthetic local proof.
- PR #146 final-head CI #44184973021 and merged-main CI #44185603088 each passed
  `docs`, PostgreSQL 17 `sql_schema`, and fresh synthetic `supabase_local`.
- Independent read-only review found three P1 issues in the first commit/follow-up: approved
  replay, allocation header move, and a permissive media policy overriding header scope. All
  were corrected; final follow-up review found no remaining blocker and did not run tests.

## Limits

This component does not implement `GET /expenses`, expense patch/approve/reject/payment endpoints,
recurring draft UI or financial reporting. `mark_paid=true` and non-empty `receipt_media_ids` are
rejected until payment and media flows are implemented. EVE-016.2/.3 and AT14 end-to-end remain
open. The local tests and SQL fixture are synthetic, not hosted Supabase or production evidence.
