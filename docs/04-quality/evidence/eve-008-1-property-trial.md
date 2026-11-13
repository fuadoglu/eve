# EVE-008.1 — Ev yaradılması və ilk trial atomikliyi

Tarix: 2026-11-13. Status: **local DB/RPC component tamamlandı; full AT04–06 və production acceptance deyil**.

## İzləmə

- Issue: [#16 — EVE-008](https://github.com/fuadoglu/eve/issues/16)
- Pull request: [#75](https://github.com/fuadoglu/eve/pull/75), squash merge `a4a0eb08c0977536d3fcd30bc392cc87622a502f`
- Final PR head: `cbf0a0745e4d724a3892c0e0951ff47d6656e060`
- Kod migration-u: `supabase/migrations/20261113001300_eve_property_create_trial.sql`
- CI: [run #43391826215](https://github.com/fuadoglu/eve/actions/runs/43391826215) — `docs`, `sql_schema`, `supabase_local` SUCCESS.
- İcmal: müstəqil read-only QA/red-team review iki ilk tapıntını (mutasiya RPC volatility allowlist-i və arxiv/silmə sonrası AT25 ssenarisi) çıxardı. Düzəlişdən sonra follow-up review blocker tapmadı. GitHub review approval verilməyib; main protection approval sayını 0 tələb edir.

## Dəyişiklik

`api.create_property` JWT-dən cari actor-u götürür; owner ID client input-u deyil. Owner hesabı, ev, trial claim və subscription bir tranzaksiyada yazılır. Actor üzrə transaction advisory lock paralel ilk create qərarını seriallaşdırır. İlk owner evinə server vaxtından 7×24 saatlıq trial yazılır; sonrakı və arxivdən sonrakı ev `draft` olur. Trial claim owner üzrə unique saxlanır, silinməyə FK mane olur. `app_executor` üçün yalnız dörd cədvəldə `INSERT` verilir; `UPDATE`/`DELETE` grant açılmır. RPC anon-a bağlı deyil, `authenticated` üçün explicit allowlist-dir.

Migration mövcud `PropertyCreate` DTO sahələrinə uyğundur və yeni DB cədvəli/API spec sahəsi yaratmır. Migration 013 additive-dir; tətbiq olunmuş migration dəyişdirilmir. Geri dönüş tətbiqdən əvvəl commit revert-dir; tətbiqdən sonra düzəliş forward migration tələb edir.

## Qəbul sübutu

| Müqavilə | Sübut | Nəticə və sərhəd |
|---|---|---|
| EVE-008.1 positive create | `0062_property_create_trial_smoke.sql` | Authenticated owner create DTO qaytarır; property, subscription və claim birlikdə yaranır. PostgreSQL 17 CI-də keçdi. |
| İlk ev üçün R12/AT25 | eyni smoke | Sınaq 7×24 saatdır; ikinci ev `draft`; arxivləndikdən sonra yeni ev də `draft`; ilk claim dəyişməz qalır. Trial claim FK səbəbindən ilk ev silinmir. |
| Paralel AT25 race | `scripts/test-db-concurrency.py`, CI `sql_schema` | İki paralel create nəticəsi: 1 claim, 1 `trialing`, 1 `draft`; CI log-da PASS. Sintetik lokal PostgreSQL sınağıdır. |
| R02/AT04–06 sərhədinin lokal hissəsi | eyni smoke və `0062_api_surface_smoke.sql` | Owner actor JWT-dən çıxır; authenticated base-table access rədd edilir; anon execute yoxdur. Multi-owner/manager permission matrix, Data API HTTP və private storage tam AT04–06 sayılmır. |
| Error/atomicity | eyni smoke | Boş name rədd olunur və partial property yazılmır; unauthenticated çağırış rədd olunur. |
| Ümumi regression | CI run #43391826215 | 52 cədvəl RLS/grant coverage, 10 API RPC allowlist, migration zənciri və fresh local Supabase Data API/Storage negative HTTP sınaqları keçdi. |

## Lokal yoxlamalar və məhdudiyyətlər

- `node scripts/docs-check.mjs` — PASS.
- `node scripts/verify-contracts.mjs` — PASS (117 operation, 52 table, 255 binding, 90 package).
- `node scripts/test-prototype.mjs` — PASS (71 VM/fake-DOM assertion; bu DB/UI browser qəbulu deyil).
- Identity unit suite — PASS, 19/19; TypeScript, production build, mobile shell browser smoke və Python schema validator CI-də PASS.
- Lokal PostgreSQL 14-də yeni RPC davranışının hədəf smoke-u keçdi. Tam migration zənciri lokalda işlədilmədi: repository migration-ları PostgreSQL 17 `GRANT ... WITH SET/INHERIT` rol sintaksisinə bağlıdır, lokal PostgreSQL 14 bunu dəstəkləmir. Rəsmi tam migration sübutu CI PostgreSQL 17-dir.
- İlk CI cəhdi sintetik `auth.users` fixture-i olmadığı üçün test mərhələsində dayandı; test fixture-i əlavə edildikdən sonra final head-də göstərilən run tam keçdi.
- `POST /properties` HTTP/server route və onun Idempotency-Key wrapper-i bu paketdə qurulmayıb. Hosted Eve Supabase, real istifadəçi/cihaz acceptance-i və production deploy edilməyib.
