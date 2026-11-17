# EVE-014.2 — Money sheet and reservation balance

## Scope

Implements the F05 reservation money sheet on the created-reservation detail: rent/deposit receipts, receipt-linked rent refunds and deposit returns, custodian, Baku calendar date, optional note, server balance refresh, deposit summary and ledger history. Adds the already documented authenticated `GET /reservations/{id}` HTTP route so the sheet can refresh the canonical balance after a ledger acknowledgement.

Does not implement realtor settlement, deposit allocation/reversal controls, EVE-014.3’s full rounding/refund/idempotency acceptance, provider/hosted integration or production deployment.

## Contract behavior

- Money is entered as safe integer AZN qəpik, using the reservation parser that rejects unsupported precision.
- Refund and deposit-return options select a source ledger entry. The UI shows the remaining source limit from the immutable ledger history; the server command remains authoritative and rejects excess amounts.
- Receipt attribution defaults to the current reservation/property custodian. If the reservation has a configured realtor contact, realtor is selectable; refund attribution/contact comes from its source receipt.
- Date defaults to the current Asia/Baku date and is converted to a noon instant in that time zone without hard-coding the offset.
- A stable per-payload idempotency key is reused after an unacknowledged retry. “Saxlanıldı” appears only after a valid HTTP 201 rent-entry DTO. The reservation GET refreshes balance from the server. If that refresh fails after write acknowledgement, the UI says the entry was saved and the balance needs refresh.
- The balance GET validates same-origin, active session, resource DTO and id, and responds private/no-store/noindex. The ledger GET continues to use its existing documented endpoint.
- Eve records a money entry; the UI does not claim to move money between bank accounts.

## Verification

Local checks: `pnpm typecheck`; `pnpm test:finance` (9/9); `pnpm test:reservations` (47/47); `pnpm build`; `node --check scripts/test-reservation-route-http.mjs`; `node scripts/docs-check.mjs`; `node scripts/verify-contracts.mjs`; `python3 scripts/verify-storage-config.py`; `python scripts/validate-schemas.py` (207 schemas; 14 positive/23 negative); `node scripts/test-prototype.mjs` (71 fake-DOM assertions); `git diff --check` — all passed. The prototype smoke is not browser/layout evidence.

The synthetic E2E extension in `scripts/test-reservation-route-http.mjs` covers the 300 AZN reservation with 100 AZN initial receipt, a 250 AZN receipt, overpayment preview, over-limit refund rejection, a valid source-linked 50 AZN refund and refreshed server balance. It is wired into CI but has not run on this branch yet. Local Docker is unavailable in this environment, so route-to-PostgreSQL E2E depends on CI. Independent QA/red-team review found no remaining blocker and did not run tests.

## Limitations

The accessible reservation detail is reached through the current reservation creation flow; a standalone `/reservations/{id}` page is not yet implemented. A realtor choice appears when the reservation contains its commission contact; broader realtor account/settlement management is out of scope. This work does not close AT11–12 end-to-end, hosted DB, production, backup/restore, or real-device gates.
