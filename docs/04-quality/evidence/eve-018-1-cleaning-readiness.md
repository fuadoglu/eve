# EVE-018.1 — Reservation cleaning readiness component

Date: 2026-11-18. Branch: `fix/EVE-018-1-readiness-review`. Status: **in progress; current review/CI not yet complete**. Package scope is the DB readiness projection and checkout task behavior, not full AT16/AT36.

## Behavior

Migration `036` recomputes property readiness in the same transaction as task and inspection writes. An active `required_for_readiness` task blocks `ready` until it is completed and its linked inspection event has a completed submission with an explicit answer for every snapshot room. Multiple required tasks are considered together. A cancelled task no longer blocks readiness. An existing `attention_required` state is preserved; cleaning completion cannot silently clear it. The helper matches property and owner, has no direct execute grant to client or `app_executor` roles, and locks the property with `FOR UPDATE NOWAIT`; a lock conflict raises `40001/readiness_retry_required` so the complete idempotent command is retried.

Checkout reuses the existing non-cancelled cleaning task for the same reservation placement. If it was already completed before checkout, the task remains completed with its identity, title, instruction, assignee and append-only transition history intact; checkout marks it readiness-required and links it to the new checkout inspection. The property stays `cleaning_pending` until that inspection is completed and all snapshot rooms have answers. If no reusable task exists, the checkout transition creates one. The partial unique index still prevents multiple non-cancelled cleaning tasks for one reservation.

## Verification

- Earlier local PostgreSQL 16 runs applied migrations 001–032, 034–036 and smoke `0076`; those runs preceded the latest `OLD`/`NEW` inspection event handling, `NOWAIT` lock retry behavior and completed-before-checkout correction. They are historical diagnostics and **do not verify the current diff**.
- The current host has no running PostgreSQL/Docker service, so current migration/smoke execution must be evidenced by the branch CI. No hosted Eve staging or production database is used.
- Current SQL smoke `supabase/tests/0076_cleaning_readiness_smoke.sql` covers helper execute denial, tenant/property isolation, multiple required tasks, incomplete/missing inspection answers, reopening after answer deletion, task completion, cancellation, attention preservation, checkout reuse, active duplicate rejection, and a pre-checkout completed task whose state/instructions/assignee/history remain unchanged while its checkout inspection gates readiness.
- Current branch validators and CI, independent follow-up review, and merged-main CI will be recorded here only after they actually complete.

## Review and limits

Initial independent review found a gap for a completed cleaning task that existed before checkout. The current branch promotes that same task to readiness-required and attaches the checkout inspection without reopening its state or rewriting its transition history. A new regression fixture exercises this case. Follow-up review and final branch CI are still required before this package can be marked done.

This SQL component does not prove the HTTP/scoped-cookie flow, notification delivery, outbox/cron, quiet hours, HTTP retry mapping, full AT16/AT36, hosted migration or UI acceptance. Migration `036` is forward-only. Disposable test databases can be reset; any deployed rollback must use a reviewed forward migration, not edit `036` or claim that dropping its triggers reverses readiness metadata.
