# EVE-014.1 — Rent/deposit/refund immutable ledger

## Scope

Adds the reservation money GET/POST route, strict `RentEntryCreate` / `RentEntry` parsing, a Supabase RPC adapter, append-only SQL commands, authorization and balance smoke coverage. It does not implement the money sheet (EVE-014.2) or the full refund, rounding and concurrency acceptance slice (EVE-014.3).

## Contract behavior

- Values are safe integer AZN qəpik. Eve records owner-side guest money and does not receive rent.
- Each command is a new `rent_entries` row. Direct authenticated table mutation is not granted.
- Every write locks the reservation first. Source linked refunds, returns, allocations and reversals lock their source and are bounded by its effective remaining amount.
- Current reservation write permission and active entitlement are checked for each create. Daily managers may record guest money with manager custodian attribution; allocation and reversal require owner/full access on the source property.
- Stable SHA-256 `operation_key` values scope idempotency to actor, reservation and request key. The raw request key is never persisted. Identical retry returns the original entry; changed payload conflicts.
- GET pages use an opaque keyset cursor and the same current placement / historical finance-read scope as existing rent history. HTTP replies are private, no-store and noindex.
- The immutable ledger table has no version or update timestamp. The DTO's `version: 1` and `updated_at = created_at` are read-only projections for the existing OpenAPI `RentEntry` schema; `actor_display_name` remains omitted because it is optional.

## Verification

- Local: `pnpm install --frozen-lockfile` completed without lockfile changes; `pnpm test:finance` passed 4/4; TypeScript check passed.
- PostgreSQL 17 migration and authorization/balance smoke are wired into CI as `0071_rent_ledger_commands_smoke.sql`; this environment has no Docker daemon, so local PostgreSQL execution is unavailable.
- CI, independent review and merged-main verification are pending. Package is not Done and must not be counted in the package ledger until those gates pass.

## Limits

The CI fixture is synthetic. It does not prove hosted Eve Supabase deployment, production data, UI money-sheet behavior, provider settlement, backup/restore, full AT11–12, or production readiness.
