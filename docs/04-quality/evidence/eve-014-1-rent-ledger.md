# EVE-014.1 — Rent/deposit/refund immutable ledger

## Scope

Adds the reservation money GET/POST route, strict `RentEntryCreate` / `RentEntry` parsing, a Supabase RPC adapter, append-only SQL commands, authorization and balance smoke coverage. It does not implement the money sheet (EVE-014.2) or the full refund, rounding and concurrency acceptance slice (EVE-014.3).

## Contract behavior

- Values are safe integer AZN qəpik. Eve records owner-side guest money and does not receive rent.
- Each command is a new `rent_entries` row. Direct authenticated table mutation is not granted.
- Every write locks the reservation first. Source linked refunds, returns, allocations and reversals validate the immutable source row and its effective remaining amount while that reservation lock is held. This serializes ledger writes without granting UPDATE on the append-only ledger table.
- Current reservation write permission and active entitlement are checked for each create. Daily managers may record guest money with manager custodian attribution; allocation and reversal require owner/full access on the source property.
- Stable SHA-256 `operation_key` values scope idempotency to actor, reservation and request key. The raw request key is never persisted. Identical retry returns the original entry; changed payload conflicts.
- GET pages use an opaque keyset cursor and the same current placement / historical finance-read scope as existing rent history. HTTP replies are private, no-store and noindex.
- The immutable ledger table has no version or update timestamp. The DTO's `version: 1` and `updated_at = created_at` are read-only projections for the existing OpenAPI `RentEntry` schema; `actor_display_name` remains omitted because it is optional.

## Verification

- Local: `pnpm install --frozen-lockfile` completed without lockfile changes; `pnpm test:finance` passed 4/4; TypeScript check passed.
- PR #128 head `8aa3bd6` passed docs, PostgreSQL 17 (`0071_rent_ledger_commands_smoke.sql`) and synthetic Supabase browser/API integration in CI run [#44144131867](https://github.com/fuadoglu/eve/actions/runs/44144131867).
- Independent SQL review found no remaining blocker. The review confirmed the shared reservation row lock serializes ledger commands without granting UPDATE on immutable ledger rows; the reviewer did not run tests.
- PR #128 was squash-merged as `a4d4c1ce9626976e3b530ff9b673c26da1c49d92`; merged-main CI [#44145340943](https://github.com/fuadoglu/eve/actions/runs/44145340943) passed docs, PostgreSQL 17 schema/smoke and synthetic Supabase integration.
- EVE-014.1 is complete for its documented component scope and may count in the package ledger. Hosted/production database application, the UI money sheet, full AT11–12 and release gates remain outside this package.

## Limits

The CI fixture is synthetic. It does not prove hosted Eve Supabase deployment, production data, UI money-sheet behavior, provider settlement, backup/restore, full AT11–12, or production readiness.
