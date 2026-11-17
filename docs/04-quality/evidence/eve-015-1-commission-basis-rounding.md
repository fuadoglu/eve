# EVE-015.1 — Commission basis and half-up rounding

## Scope

Adds a targeted case to the existing synthetic PostgreSQL reservation-create smoke. It verifies the documented percentage-commission basis and half-up calculation without changing runtime code or schema.

## Acceptance evidence

- The commission basis is the reservation rent quote (`total_minor`), not the separate deposit receipt.
- A 1 qəpik rent basis at 5,000 basis points produces a 1 qəpik commission (`0.5` qəpik rounds half-up). The same reservation carries a separate 5,000 qəpik deposit receipt, which must not inflate the commission basis.
- Existing 30,000 qəpik at 1,000 basis points example remains asserted at 3,000 qəpik.
- Test artifact: `supabase/tests/0064_reservation_create_smoke.sql`, run in PostgreSQL 17 `sql_schema` CI after reservation-create migration.

## Verification state

Final-head CI and merged-main CI must pass the PostgreSQL 17 `sql_schema` job before the package is closed. The smoke uses synthetic records and is not hosted or production evidence.

## Limitations

This package checks commission calculation at creation. It does not cover realtor settlements, transferred/offset amounts, net direction, cancellation review, provider behavior, or production readiness.
