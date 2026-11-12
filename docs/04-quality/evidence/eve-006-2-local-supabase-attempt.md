# EVE-006.2 — lokal Data API/Storage sınaq cəhdi

Tarix: 2026-11-12, Asia/Baku. Branch: `feat/EVE-006-2-access-closure`. Mühit: macOS 27.2 arm64, Colima Docker, Supabase CLI 2.33.9, lokal Supabase PostgreSQL image `17.4.1.068`; sonra CLI 3.1.0 sınağı. Yalnız lokal sintetik mühit; hosted Supabase, real istifadəçi və real media yoxdur.

## Faktiki nəticə

1. `colima start --cpu 4 --memory 6` exit 0. `supabase start` CLI 2.33.9 migration `20261111000200_eve_access_policies.sql` tətbiqində exit 1 / `unexpected EOF` verdi. PostgreSQL konteyner logunda həmin migration-ın `grant app_executor to current_user with set true, inherit false` əmri işləyərkən backend prosesinin `signal 11: Segmentation fault` ilə dayandığı görünür. Bu, PostgreSQL 17 CI nəticəsini əvəz etmir: CI-nin adi `postgres:17` image-i bu əmri keçirir.
2. Eyni lokal image-də ayrıca minimal təkrar: `create role app_executor nologin nobypassrls noinherit` keçdi; `grant app_executor to current_user with set true, inherit false` bağlantını server crash ilə bağladı; sadə `grant app_executor to postgres` keçdi; explicit option-lu GRANT təkrar crash verdi. Bu, image/əmr uyğunluğuna dair lokal müşahidədir; hosted provayderin davranışı barədə nəticə deyil.
3. CLI 3.1.0 ilə ilkin tam stack sınağı image yüklənərkən host diskində 184 MiB yer qalması və Docker/containerd `input/output error` ilə dayandı. Müvəqqəti cache təmizlənib Colima dayandırıldıqdan sonra diskdə yer açıldı. Yalnız DB, Kong, PostgREST və Storage API saxlayan ikinci CLI 3.1.0 cəhdində migration 002-nin `grant execute on function api.has_property_capability(uuid,text) to authenticated` sətri `SQLSTATE 42501: permission denied for function` ilə dayandı. SQL ardıcıllığına əsasən səbəb: funksiya sahibi `app_executor` edildikdən və migratorun müvəqqəti üzvlüyü ləğv edildikdən **sonra** GRANT çağırılır. Eyni ardıcıllıq migration 004, 005, 007, 008, 010 və 011-də də var. Bu cəhddə də Data API və Storage HTTP mənfi sınaqları **icra edilmədi**. Colima ilkin dayandırılmış vəziyyətinə qaytarıldı; başqa layihənin məlumatı və repository migration-ları dəyişdirilmədi.

## Bu incrementin yoxlaması

`supabase/tests/0062_api_surface_smoke.sql` mövcud yeddi `api` RPC-nin inventory-sini, funksiyanın `app_executor` sahibi olmasını, `SECURITY DEFINER` və boş `search_path`-ı, anon EXECUTE rəddini, authenticated EXECUTE allowlist-ini və `api` relation olmamasını kataloqda yoxlayır. Lokal Supabase-in əvvəl server crash, sonra SQLSTATE 42501 ilə migration 002-də dayanması səbəbilə bu SQL həmin stack-də işlədilmədi; PR #61 və merged main CI #43181388193 PostgreSQL 17 `sql_schema` job-unda exit 0 verdi. Mövcud 52 cədvəl RLS/grant guard-ı dəyişməyib.

## Qapı

EVE-006.2 `in_progress` qalır. Əsas repository migration-ları ilə Data API/Storage və hosted provider testləri keçmiş kimi yazılmır. Tarixdəki migration 002 və eyni nümunəli altı sonrakı migration redaktə edilmədi. Təzə quraşdırma 002-də dayandığına görə sonrakı forward migration bunu təkbaşına düzəldə bilmir. Repo STATUS-a görə persistent Supabase tətbiqi yoxdur, lakin istifadəçi təsdiqi alınmadan bu fakt qəti sayılmır; AGENTS.md tətbiq edilmiş migration redaktəsini qadağan edir. Dəyişiklik qərarı həmin faktın təsdiqi və ayrıca review-dən asılıdır. Gələcək domain write/media RPC-ləri öz asılı paketlərində default-deny qaydası ilə açılır.

## Yalnız müvəqqəti checkout-da patch sınağı

Eyni gün main `08c3f92` bazasının `git archive` surəti ayrıca `/tmp` qovluğunda açıldı. SHA-256 `74b24eceb837d0fe82287766ceae8666bf290cedd57ff8c630f700f5d304ef59` olan **tətbiq edilməmiş namizəd patch** yalnız yeddi migration-da `GRANT EXECUTE TO authenticated` əmrini həmin funksiyanın sahibi dəyişməzdən əvvələ keçirdi; qalan SQL və repo main dəyişmədi. Supabase CLI 3.1.0-ın minimal lokal DB/Kong/PostgREST/Storage stack-i bu surətdə 001–011 migration-ların hamısını tətbiq etdi (exit 0). `0062_api_surface_smoke.sql` və `0062_rls_coverage_smoke.sql` exit 0 verdi; altı Eve bucket-i private idi.

Sintetik A/B/M fixture-i ilə doqquz lokal HTTP/DB yoxlaması exit 0 verdi: sahibin öz evi və menecerin verilmiş ev oxusu; daily menecer üçün `finance.read` rəddi; başqa sahibin evinin rəddi; base table 404 və `app_private` profile header 406; anonim RPC 401; membership revoke-dan sonrakı request-də rədd; private Storage bucket-ə birbaşa upload-un RLS `AccessDenied` cavabı. Bu sübut **yalnız həmin müvəqqəti patch surətinə** aiddir. Əsl repo migration-ları dəyişdirilmədi; patch main-da və davamlı Supabase-də tətbiq olunmayıb. Signed URL/media proxy, hosted provider və tam AT04–06/AT21 sınaqları keçmiş sayılmır. Stack dayandırılıb, sintetik DB və lokal secret faylları silinib.

| Sintetik Given | Lokal HTTP When | Faktiki Then |
|---|---|---|
| Sahib A və A1 evi | A JWT ilə `has_property_capability(A1, property.read)` | `200 true` |
| A1-də daily menecer M | M JWT ilə eyni RPC | `200 true` |
| A1-də daily menecer M | `finance.read` | `200 false` |
| Başqa sahib B | A1 üçün `property.read` | `200 false` |
| A JWT | `GET /rest/v1/properties` | `404`, `api`-də base table yoxdur |
| A JWT | `Accept-Profile: app_private` ilə həmin GET | `406`, private schema expose deyil |
| Anonim request | A1 üçün RPC POST | `401` |
| M-in üzvlüyü DB-də revoke edildi | Növbəti request-də A1 üçün `property.read` | `200 false` |
| M JWT | Private task bucket-ə birbaşa object POST | HTTP `400`, daxildə `AccessDenied`/RLS rəddi |

Bu, müvəqqəti skriptlə aparılmış **kəşfiyyat sınağıdır**: skript və raw cavab logu repoda saxlanmayıb. Formal AT04–06 qəbul sınağında təkrarlanan fixture, redaktə olunmuş request/response logu, reviewer və main-dakı eyni migration commit-i ayrıca tələb olunur.
