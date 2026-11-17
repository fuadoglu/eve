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

## Verification

- Local `pnpm test:finance`: 15/15 passed, including safe integer, duplicate allocation,
  unauthorized Origin and server acknowledgement checks.
- Local `pnpm typecheck`: passed.
- `git diff --check`: passed.
- PostgreSQL 17 integration test artifact: `supabase/tests/0075_expense_proposal_allocation_smoke.sql`.
  It asserts RPC grants, owner approved/unpaid creation, replay, mismatched sum, cross-owner
  rejection, partial manager header isolation, daily proposed/unpaid creation and deferred sum.
  The local machine has no running PostgreSQL or Docker daemon, so this SQL test is **not yet run**;
  it requires CI before package closeout.

## Limits

This component does not implement `GET /expenses`, expense patch/approve/reject/payment endpoints,
recurring draft UI or financial reporting. `mark_paid=true` and non-empty `receipt_media_ids` are
rejected until payment and media flows are implemented. EVE-016.2/.3 and AT14 end-to-end remain
open. The local tests and SQL fixture are synthetic, not hosted Supabase or production evidence.
