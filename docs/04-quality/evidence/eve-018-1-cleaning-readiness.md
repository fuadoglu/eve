# EVE-018.1 — Reservation cleaning readiness component

Status: **implementation branch, not Done**. EVE-017.3 dependency, shared D47/
OPERATIONS/data-dictionary alignment, independent review, PR CI and merged-main CI
remain required. This is synthetic local DB proof, not hosted or production proof.

## Behavior

Migration `036` adds an internal task trigger that recomputes property readiness in
the same transaction as checkout/move task creation or task state update. An active
`required_for_readiness` task blocks `ready` until it is `completed` and its linked
inspection has a completed submission with an explicit answer for every snapshot
room. Multiple required tasks are considered together. A cancelled task no longer
blocks readiness. An existing `attention_required` state is preserved; cleaning
completion cannot silently clear it. The helper matches property and owner and
does not grant direct execute to client or `app_executor` roles. It locks the
property before reading tasks to serialize updates from separate tasks.
An existing future cleaning task that was not marked readiness-required becomes
required when checkout completes, without replacing its task ID or instruction.

The existing reservation checkout, date patch and move operations remain the
upsert writers. This migration does not create another cleaning task or modify an
applied migration. Existing required tasks are projected once on migration apply.
The existing partial unique index on `(reservation_id, kind)` guards active cleaning
task duplicates; the existing reservation transition idempotency key guards replay.

## Verification

- Temporary local PostgreSQL 16 database: repository migrations 001–032, merged
  EVE-016.1 migration 034, EVE-017.3 branch migration 035, and migration 036 all
  applied with `ON_ERROR_STOP=1`, exit 0. Migration 033 is a separate unmerged
  EVE-019.3 branch and was not in this chain.
- `0076_cleaning_readiness_smoke.sql` exit 0: property scope, multiple required
  tasks, incomplete inspection and missing room answer staying pending, completion
  becoming ready, task write recomputation, reused checkout task promotion,
  duplicate active reservation cleaning rejection, cancellation, explicit attention
  preservation, and direct helper execute denial.
- Existing `0065_task_transition_history_smoke.sql` exit 0 against the branch
  migration chain; it covers authenticated/scoped transition rules and the
  inspection requirement for `report_done`.
- Existing `0068_reservation_at10_transition_smoke.sql` exit 0 against the branch
  migration chain; it exercises reservation checkout, future cleaning task
  reschedule, move, replay and preservation of completed task history.

## Limits and rollback

The SQL component does not prove the HTTP/WhatsApp scoped flow, real notification
delivery, full AT16, hosted migration or UI acceptance. An operation that updates a
task after locking it and a reservation move that locks the property first may
deadlock under rare concurrency; PostgreSQL aborts one transaction, so callers need
safe retry handling. This risk needs independent review before merge.

Rollback in a non-production test database is dropping the trigger and both new
functions. The migration does not remove task or inspection history. A production
rollback requires a forward migration and projection review, never editing 036.
