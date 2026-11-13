# EVE-008.3 — Revoke və cross-owner negative test

Tarix: 2026-11-13. Status: **branch-də test əlavəsi; CI və müstəqil review gözlənilir**.

## İzləmə

- Parent issue: [#16 — EVE-008](https://github.com/fuadoglu/eve/issues/16)
- Branch: `feat/EVE-008-3-revoke-negative`
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

- PR CI və müstəqil review: pending.
- Local Docker/PostgreSQL mühiti yoxdur; DB nəticəsi yalnız CI `sql_schema` və fresh synthetic Supabase local job-ları yaşıl olduqdan sonra yazılacaq.
