# EVE-008.3 — Revoke və cross-owner negative test

Tarix: 2026-11-13. Status: **merged; EVE-008.3 DB/RLS negative-test DoD tamamlandı**.

## İzləmə

- Parent issue: [#16 — EVE-008](https://github.com/fuadoglu/eve/issues/16)
- PR: [#81 — test(EVE-008.3): cover invite revoke and cross-owner denial](https://github.com/fuadoglu/eve/pull/81), squash merge `f491aefd444296237bc884cddbf4362b60e47df1`.
- Branch: `feat/EVE-008-3-revoke-negative`
- Final PR head: `7ec4379546ae597b82516685a6fdd9d2f9af6841`; PR CI [#43407399860](https://github.com/fuadoglu/eve/actions/runs/43407399860) and merge commit CI [#43407696045](https://github.com/fuadoglu/eve/actions/runs/43407696045), all three jobs PASS in both runs.
- SQL test source head: `dd10f09e5672e16daa2794ad3ec8f8278568b7f8`
- CI: [run #43406974550](https://github.com/fuadoglu/eve/actions/runs/43406974550) — `docs`, `sql_schema`, `supabase_local` PASS.
- Paket statusu: `done`; delivery ledger becomes 26/90 (28.9%) after PR #82 closure record merges; main snapshot before PR #82 is 25/90 (27.8%).
- Owned paths: `supabase/tests/0062_manager_invite_smoke.sql`, CI workflow, delivery status/work-package və bu evidence faylı.
- Dependency: EVE-008.2 merged (`59fea750fbb1a3bcb34b6407085c059e1982475e`).

## Scope və sınaq

- Accepted invite-in A1/A2 membership-lərindən A1 fixture revoke edilir; eyni manager JWT ilə növbəti `api.has_property_capability` A1 üçün false, A2 üçün true qaytarmalıdır.
- `api.list_visible_property_summaries` növbəti sorğuda yalnız A2-ni qaytarmalıdır. Beləliklə revoke sonrası authorization cari DB membership-dən oxunur, köhnə sessiya icazəni saxlamır.
- Manager capability digər owner-in B1 property-si üçün false qalmalıdır.
- Owner A-nın invite create əməliyyatında B1 cross-owner property daxil edilməsi rədd edilir; uğursuz əməliyyatdan sonra token hash `b` üçün invite/property association persist olmamalıdır.
- Sonrakı testdə yeni dəvət revoked A1 membership-i yalnız explicit yeni permission ilə bərpa edir.

Bu harness DB rol/JWT fixture-idir. Revoke HTTP route, owner-facing UI, real Data API header/JWT doğrulaması, private Storage, hosted Supabase və tam AT05 acceptance bu sübutun scope-unda deyil.

## Yoxlama nəticələri

- `node scripts/docs-check.mjs` — PASS (61 Markdown files).
- `node scripts/verify-contracts.mjs` — PASS (117 operations, 53 tables, 256 bindings, 90 packages, 36 scenarios).
- `git diff --check` — PASS.
- PostgreSQL 17 `sql_schema` və fresh synthetic Supabase local smoke — CI #43406974550 PASS; local Docker/PostgreSQL service yoxdur.
- Independent read-only integration review final test/evidence diff-də P1/P2 blocker tapmadı; bu GitHub human approval deyil.
- Local component DoD is merged; PR #82 records the package closure in the machine ledger. The parent #16 and full AT05/production gates remain open.
