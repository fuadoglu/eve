# EVE-008.3 — Revoke və cross-owner negative test

Tarix: 2026-11-13. Status: **testlər və müstəqil review keçib; merge gözlənilir**.

## İzləmə

- Parent issue: [#16 — EVE-008](https://github.com/fuadoglu/eve/issues/16)
- PR: [#81 — test(EVE-008.3): cover invite revoke and cross-owner denial](https://github.com/fuadoglu/eve/pull/81)
- Branch: `feat/EVE-008-3-revoke-negative`
- SQL test source head: `dd10f09e5672e16daa2794ad3ec8f8278568b7f8`
- CI: [run #43406974550](https://github.com/fuadoglu/eve/actions/runs/43406974550) — `docs`, `sql_schema`, `supabase_local` PASS.
- Paket statusu: `in_progress`; main ledger 25/90 (27.8%), bu branch sayılmır.
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
- Main ledger 25/90 (27.8%) olaraq qalır; PR merge olunana qədər EVE-008.3 `in_progress` sayılır.
