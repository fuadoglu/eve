# EVE-014.3 — Rent refund and deposit acceptance

## Scope

Extends the synthetic PostgreSQL rent-ledger acceptance smoke for AT11 and the financial boundary in AT12. No runtime behavior or migration changes are included. The test uses integer AZN qəpik inputs and verifies that fractional qəpik values are rejected.

## Acceptance evidence

- **AT11:** reservation quote 30,000 qəpik; receipts of 10,000 and 25,000 show 5,000 qəpik overpayment. A 6,000 qəpik source-linked refund replays to the same immutable row, leaving 29,000 received, 6,000 refunded, 1,000 remaining, and no overpayment. A subsequent 19,001 qəpik refund against the same source is rejected because only 19,000 qəpik remains. A fractional 1.5 qəpik receipt is rejected.
- **AT12 financial boundary:** a completed inspection submission records a damaged inventory item. Creating a 5,000 qəpik deposit receipt does not create a damage allocation; only the explicit finance-authorized 1,200 qəpik allocation changes held deposit to 3,800 qəpik. A return above the remaining deposit is rejected. Deposit remains excluded from rent receipts.
- PostgreSQL test artifact: `supabase/tests/0071_rent_ledger_commands_smoke.sql`, run by the `sql_schema` CI job after migration `20261117003000_eve_rent_ledger_commands.sql`.

## Verification state

Implementation PR CI and merged-main CI must both pass the PostgreSQL 17 `sql_schema` job before this package is closed. This document does not claim a passing result before those runs. Local Docker availability is not assumed.

## Limitations

The fixture seeds a synthetic completed inspection record directly in PostgreSQL; it is not an inspection UI/API integration test. It does not prove hosted database deployment, real guests, backup/restore, realtor settlement, or production readiness.
