# EVE-010.1 — unified occupancy və overlap constraint

Status: **Done, DB constraint component scope**. Feature PR #85 squash-merge commit `ffe64277bd64fae274c412556ca1e58219895f77`; final head `d0f53a06ae6952189bf5d1b7d2e9f64986e587f0`.

## Scope

Normativ modeldə gecələmə intervalı `[check_in,check_out)`-dır. Core migration-da `occupancy` reservation placement və manual block source-larını eyni cədvəldə saxlayır; `one_source`, finite `[)` range/FK constraint-ləri və `occupancy_no_overlap` (`EXCLUDE USING gist (property_id WITH =, date_range WITH &&) WHERE (active)`) ilə qorunur. Bu package migration/schema-nı dəyişmir; core schema smoke-u mövcud invariantı cross-source ssenaridə sınayır.

## Acceptance və test sübutu

- Mövcud manual block `[2027-01-01, 2027-01-04)` occupancy-si saxlanır.
- Reservation + placement + occupancy `[2027-01-04, 2027-01-05)` uğurla daxil olur; checkout gecəsi növbəti reservation intervalına daxildir.
- Eyni reservation occupancy ilə kəsişən `[2027-01-04, 2027-01-05)` manual block occupancy `exclusion_violation` ilə rədd olunur. Exception handler yalnız həmin SQLSTATE-i udur; testin öz “unexpectedly” exception-u uğursuzluğu üzə çıxarır.
- Əvvəlki block-vs-block overlap mənfi smoke saxlanır.

Yoxlamalar:

- PostgreSQL 14.18 synthetic lokal cluster: `20261111000100_eve_core_schema.sql` və `0061_core_schema_smoke.sql` exit 0.
- PR #85 CI #43411481627: `sql_schema` (PostgreSQL 17), `docs`, təzə synthetic `supabase_local` hamısı SUCCESS.
- `node scripts/docs-check.mjs` — 62 Markdown faylı; keçdi.
- `node scripts/verify-contracts.mjs` — 117 operation, 53 table, 256 field binding, 90 package, 36 scenario; keçdi.
- `python scripts/validate-schemas.py` — 207 schema, 12 positive/20 negative example; keçdi.
- `node scripts/test-prototype.mjs` — 71 synthetic VM/fake-DOM assertion; keçdi, bu DB/UI acceptance deyil.
- `git diff --check` — keçdi.
- Müstəqil read-only QA review cross-source overlap, `[)` adjacency, deferred circular FK check və fixture-ni yoxladı; P1/P2/P3 tapmadı. Bu GitHub human approval-u deyil.

## Qalan scope

Bu test AT07–09 full concurrency/RPC acceptance deyil. Expired hold transaction catch-up, retry/idempotency, parallel booking-vs-booking/hold/block, reservation HTTP route/UI, hosted Eve DB history və production gate-ləri EVE-010.2/.3 və sonrakı acceptance işlərində açıq qalır. Production-ready iddiası yoxdur.
