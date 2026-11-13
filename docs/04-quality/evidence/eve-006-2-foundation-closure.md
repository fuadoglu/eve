# EVE-006.2 — local foundation acceptance closure

Tarix: 2026-11-13 (Asia/Baku). Mənbə commit: PR #65 merge `8e73eec`; status reconciliation PR #69 merge `3cb2970`. Bu artefakt yalnız `docs/05-delivery/work-packages.json`-dakı EVE-006.2 paket sərhədini bağlayır. Hosted HTTP, production və parent AT04–06 inteqrasiya/race qapılarını bağlamır.

## Qəbul meyarlarının sübut xəritəsi

| Meyar | İcra və yoxlama | Nəticə və sərhəd |
|---|---|---|
| 52/52 private cədvəldə ENABLE/FORCE RLS; client base access yoxdur; `app_executor` least privilege; 10 reviewed SELECT allowlist, qalanı default-deny | `supabase/tests/0062_rls_coverage_smoke.sql` migration sonrası 52 cədvəl, role grants, FORCE RLS, 10 policy/grant allowlist və policy inventory-ni yoxlayır. `supabase/tests/0062_access_policy_smoke.sql` rol atributu, membership, ownership və anon/authenticated girişini yoxlayır. CI #43295105583 və merge CI #43295563871 `sql_schema`/`supabase_local` keçib. | PASS, sintetik local Supabase CI. Hosted/prod catalog iddiası deyil. |
| Yalnız imzalı `api` RPC allowlist; authenticated-only, owner/SECURITY DEFINER/empty search_path/JWT actor | `supabase/tests/0062_api_surface_smoke.sql`, `0062_access_policy_smoke.sql`; `scripts/test-local-supabase-http.py`-də imzalı anon denial, auth RPC, base table və private schema denial. Eyni iki CI run-da `sql_schema`/`supabase_local` uğurlu olub. | PASS, local CI; provider-hosted Data API HTTP ayrıca yoxlanmayıb. |
| D33 altı private bucket, classification CHECK və birbaşa anon/authenticated upload/read denial | `supabase/tests/0062_storage_boundary_smoke.sql` classification/policy/bucket SQL yoxlaması; `scripts/test-local-supabase-http.py` altı bucket-in HTTP upload/read matrix-i. CI #43295105583 və #43295563871 `supabase_local` keçib. | PASS, local CI. Public media route, signed URL və scoped proxy bu paketin scope-unda deyil və hazır sayılmır. |
| Owner/A-B tenant/capability/revoke-next-request/safe projection positive/negative | Eyni HTTP harness-də 67 synthetic assertion; read smoke SQL-ləri tenant, capability və həssas sütunları yoxlayır. PR #65 final-head CI #43295105583; main merge CI #43295563871. | PASS, synthetic local. Bu dar read projection-lar tam OpenAPI DTO/axın deyil; full AT04–06 inteqrasiya/race EVE-006.3 və domain paketlərində qalır. |
| Real sintetik fixture ilə local PostgreSQL/Supabase CI; evidence növləri ayrıdır | PR #65 final-head run #43295105583: `docs`, `sql_schema`, `supabase_local` success. Merged main run #43295563871: eyni üç job success. PR #65-in ayrıca hosted SQL smoke-u 2026-11-12 tarixli və [sınaq qeydlərində](eve-006-2-local-supabase-attempt.md) təsvir olunub; hosted HTTP sınağı qeydə alınmayıb. | PASS, local CI. Tarixi hosted SQL yalnız izolyasiya edilmiş test layihəsinə aiddir; layihə cari CLI inventory-də yoxdur. Staging/production və hosted HTTP nəticəsi yoxdur. |

## Review və status qərarı

Merged dəyişikliklərə müstəqil read-only baxış PR #65-də `qa_redteam` scope-unda aparılıb; PR #69 status düzəlişləri də müstəqil yoxlanıb. Bu agent review-u GitHub insan approval-u deyil. CI və review ilə yanaşı paket ledger-ini `done` etmək üçün sübut mövcuddur.

PR #65-dən əvvəlki issue şərhlərində “hosted Data API/Storage və AT04–06 qalıb” ifadələri geniş parent qapılarını paket scope-u ilə qarışdırırdı. Mövcud maşın müqaviləsi EVE-006.2 üçün konkret beş meyarı, `external_gates: []`-i və EVE-006.3/domain paketlərinə aid full integration/concurrency işlərini açıq göstərir. Buna görə bu closure həmin köhnə şərhləri silmir və parent #14/M1-i bağlamır; EVE-006.2 lokal deny-first foundation paketi tamamlanır, hosted HTTP, production, backup/restore, signed media və full AT04–06 parent/release sübutları açıq qalır.

### Növbəti dependency-valid iş

EVE-006.3, EVE-006.2-dən sonra DAG üzrə növbəti paketdir. Onun DB isolation/concurrency fixture-ləri parent AT04–06-dan qalan integration/race sübutunu qiymətləndirməlidir. Bu status heç bir production deploy və ya staging miqrasiya təsdiqləmir.
