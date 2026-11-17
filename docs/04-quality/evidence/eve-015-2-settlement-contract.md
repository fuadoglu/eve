# EVE-015.2 — Realtor settlement contract

## Scope

Records D44 before implementation: settlement kinds, net due equations, aggregate version source, idempotency order, and OpenAPI/data-dictionary alignment. This documentation step does not claim the settlement API or database command is implemented.

## Contract decisions

- `C` is realtor-custody rent collected net of source-linked refunds/reversals; `T` is cash transferred to owner; `E` is stored earned commission; `P` is cash paid by owner to realtor; `O` is explicit non-cash commission offset.
- Held rent is `C−T−O`; unpaid earned commission is `E−P−O`; paid commission is `P+O`.
- `owner_due=max(0, held−unpaid)` and `realtor_due=max(0, unpaid−held)`, so the two due directions cannot both be positive.
- `commission_offset` creates no rent receipt or cash event and is bounded by both held rent and unpaid earned commission. Cash commission prepayment is rejected.
- `SettlementInput.expected_version` uses `realtor_accounts.version`; `RealtorBalance.version` supplies it and `RealtorSettlement.balance_version` returns the resulting aggregate version.
- The version increments for balance-affecting realtor receipts/refunds/reversals, earned-commission review, and settlement writes. Identical actor/key/payload replay occurs before stale-version validation; same key with changed payload conflicts.
- Settlement response no longer promises `updated_at` or a per-row `version`, because the settlement record is append-only and has neither field. The unsupported optional `note` request field is removed because no persistence field exists.

## Verification

- `node scripts/docs-check.mjs` passed (88 Markdown files).
- `node scripts/verify-contracts.mjs` passed (118 operations, 56 tables, 258 field bindings, 90 acyclic packages, 16 trace rows, 36 scenarios).
- `node scripts/test-prototype.mjs` passed (71 assertions; fake-DOM scope only).
- `git diff --check` passed.
- Local `python3 scripts/validate-schemas.py` could not run because `jsonschema` is not installed. Repository CI validation is pending.
- Independent contract review is pending. No PostgreSQL settlement implementation/test exists in this package yet.

## Limitations

EVE-015.2 remains in progress. D44 does not prove runtime behavior, RLS, transaction isolation, race handling, or production readiness. EVE-015.3 still requires negative, idempotency, concurrency, and no-double-income acceptance.
