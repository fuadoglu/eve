# EVE-006.2 — lokal Data API/Storage sınaq cəhdi

Tarix: 2026-11-12, Asia/Baku. Branch: `feat/EVE-006-2-access-closure`. Mühit: macOS 27.2 arm64, Colima Docker, Supabase CLI 2.33.9, lokal Supabase PostgreSQL image `17.4.1.068`; sonra CLI 3.1.0 sınağı. Yalnız lokal sintetik mühit; hosted Supabase, real istifadəçi və real media yoxdur.

## Faktiki nəticə

1. `colima start --cpu 4 --memory 6` exit 0. `supabase start` CLI 2.33.9 migration `20261111000200_eve_access_policies.sql` tətbiqində exit 1 / `unexpected EOF` verdi. PostgreSQL konteyner logunda həmin migration-ın `grant app_executor to current_user with set true, inherit false` əmri işləyərkən backend prosesinin `signal 11: Segmentation fault` ilə dayandığı görünür. Bu, PostgreSQL 17 CI nəticəsini əvəz etmir: CI-nin adi `postgres:17` image-i bu əmri keçirir.
2. Eyni lokal image-də ayrıca minimal təkrar: `create role app_executor nologin nobypassrls noinherit` keçdi; `grant app_executor to current_user with set true, inherit false` bağlantını server crash ilə bağladı; sadə `grant app_executor to postgres` keçdi; explicit option-lu GRANT təkrar crash verdi. Bu, image/əmr uyğunluğuna dair lokal müşahidədir; hosted provayderin davranışı barədə nəticə deyil.
3. CLI 3.1.0 ilə ilkin tam stack sınağı image yüklənərkən host diskində 184 MiB yer qalması və Docker/containerd `input/output error` ilə dayandı. Müvəqqəti cache təmizlənib Colima dayandırıldıqdan sonra diskdə yer açıldı. Yalnız DB, Kong, PostgREST və Storage API saxlayan ikinci CLI 3.1.0 cəhdində migration 002-nin `grant execute on function api.has_property_capability(uuid,text) to authenticated` sətri `SQLSTATE 42501: permission denied for function` ilə dayandı. SQL ardıcıllığına əsasən səbəb: funksiya sahibi `app_executor` edildikdən və migratorun müvəqqəti üzvlüyü ləğv edildikdən **sonra** GRANT çağırılır. Eyni ardıcıllıq migration 004, 005, 007, 008, 010 və 011-də də var. Bu cəhddə də Data API və Storage HTTP mənfi sınaqları **icra edilmədi**. Colima ilkin dayandırılmış vəziyyətinə qaytarıldı; başqa layihənin məlumatı və repository migration-ları dəyişdirilmədi.

## Bu incrementin yoxlaması

`supabase/tests/0062_api_surface_smoke.sql` mövcud yeddi `api` RPC-nin inventory-sini, funksiyanın `app_executor` sahibi olmasını, `SECURITY DEFINER` və boş `search_path`-ı, anon EXECUTE rəddini, authenticated EXECUTE allowlist-ini və `api` relation olmamasını kataloqda yoxlayır. Lokal Supabase-in əvvəl server crash, sonra SQLSTATE 42501 ilə migration 002-də dayanması səbəbilə bu SQL həmin stack-də işlədilmədi; PR #61 və merged main CI #43181388193 PostgreSQL 17 `sql_schema` job-unda exit 0 verdi. Mövcud 52 cədvəl RLS/grant guard-ı dəyişməyib.

## Qapı

EVE-006.2 `in_progress` qalır. Bu ilkin lokal sınaqda hosted Data API/Storage HTTP və provider-inteqrasiya testləri aparılmayıb. Migration 002 və eyni nümunəli altı sonrakı migration faylındakı PR #65 dəyişikliyi yalnız fresh-install grant sırasını dəyişir. İlkin CLI baxışı yalnız cari hesabın layihələrini əhatə edib; başqa təşkilat/hesab barədə nəticə çıxarılmır. Sonrakı hosted sınaq və istifadəçinin 2026-11-12 scope qərarı bu branch-in migration tarixçəsini ayrıca hosted test layihəsi ilə bağlayır; həmin qərarın sərhədi və başqa hesabların yoxlanmadığı aşağıda göstərilib. Gələcək domain write/media RPC-ləri öz asılı paketlərində default-deny qaydası ilə açılır.

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

## PR #65 branch-ində təkrarlanan lokal sınaq

`fix/EVE-006-2-migration-grant-order` / `a015ee5` branch-ində, 2026-11-12 tarixində, eyni yeddi SQL grant dəyişməsi ilə Supabase CLI 3.1.0-ın yalnız lokal DB/Kong/PostgREST/Storage stack-i **təzədən** quruldu. Migration 001–011 ardıcıl tətbiq olundu (exit 0). Bu, davamlı və ya hosted mühit deyil. `supabase/tests/0062_api_surface_smoke.sql` və `0062_rls_coverage_smoke.sql` lokal DB-də `supabase_admin` ilə exit 0 verdi. `0062_rent_read_smoke.sql`-in sintetik A/B/M, move və ledger fixture-i də həmin rolda exit 0 verdi. `postgres` ilə ilkin cəhd fixture-in sonundakı `SET ROLE app_executor` sətrində dayandı: lokal Supabase `postgres` rolu müvəqqəti üzvlük ləğv ediləndən sonra bu rola keçə bilmir; DB təzədən qurulub smoke superuser `supabase_admin` ilə icra edildi. Həmin ilkin cəhd PASS sayılmır.

Təkrarlama: yalnız təmiz, **sintetik** lokal Eve stack-ində `npx -y supabase@3.1.0 start -x gotrue,realtime,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor`; sonra `docker exec -i supabase_db_eve psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 < supabase/tests/0062_rent_read_smoke.sql`; sonra `python3 scripts/test-local-supabase-http.py`. Mövcud lokal verilənləri silmək üçün bu əmrləri başqa layihədə işlətmək olmaz. Skript yalnız `127.0.0.1:54321` və `supabase_*_eve` konteynerlərini işlədir, lokal JWT açarını yaddaşda oxuyur, açar/token/raw cavab yazmır. Sintetik Storage obyektini `service_role` ilə yaradıb oxuyur, authenticated birbaşa oxunu rəddini yoxlayır və sonda silir.

Müstəqil QA baxışından sonra anonim sorğu imzalı `anon` JWT ilə, revoke öncəsi/sonrası sorğular isə **eyni bearer** ilə təkrarlandı; kirayə DTO-da fixture-in entry ID/məbləği də yoxlandı. Skript exit 0 ilə aşağıdakı **17** redaktə olunmuş nəticəni verdi; identifikatorlar yalnız fixture-dəki sintetik sabitlərdir:

| ID | Sorğu və gözlənən sərhəd | Lokal nəticə |
|---|---|---|
| AT04 | A sahib → A1 `property.read` | `200 true` |
| AT04 | B sahib → A1 `property.read` | `200 false` |
| AT06 | A2 daily → `finance.read` | `200 false` |
| AT06 | A2 daily → cari rezervasiyanın kirayə yazısı | `200`, 1 safe DTO; target entry/4000 qəpik düz; guest/note/actor yoxdur |
| AT06 | A sahib → öz rezervasiyasının tarixi | `200`, 3 safe DTO |
| AT04 | B sahib → A rezervasiyasının pulu | `200 []` |
| AT04 | B1 full menecer → verilmiş evin pulu | `200`, 1 safe DTO |
| AT05 | M A1 üzvlüyü aktivkən `property.read` | `200 true` |
| AT05 | Eyni JWT, üzvlük revoke sonrası növbəti sorğu | `200 false` |
| AT04 | Base `properties` Data API GET | `404` |
| AT04 | `Accept-Profile: app_private` ilə GET | `406` |
| AT04 | İmzalı `anon` JWT ilə RPC POST | `401`, PostgREST `42501` |
| AT06 | Daily birbaşa private bucket upload | HTTP `400`, daxildə `AccessDenied`/`403` |
| AT06 | Lokal service fixture obyektinin yaradılması | `200` |
| AT06 | Həmin obyektin service ilə mövcudluq yoxlaması | `200`, sintetik baytlar |
| AT06 | Daily eyni private obyektin birbaşa oxusu | HTTP qeyri-`200`, `NoSuchKey` |
| AT06 | Service fixture obyektinin silinməsi | `200` |

Bu, branch-in lokal Data API/Storage deny-first davranış sübutudur. Export route-u, scoped media proxy-si, hosted mühit, tam AT04–06 və production qəbulunu təsdiqləmir. PR #65-in merge scope-u hosted test layihəsinin migration tarixçəsi və istifadəçinin qərarı ilə müəyyən edilir; EVE-006.2 `Done` isə ayrıca acceptance sübutu və merged commit tələb edir.

## PR #65 son head: read API və altı bucket matrisi

`5a5f8c8` head-indəki genişləndirilmiş `scripts/test-local-supabase-http.py` GitHub Actions CI #43232944670-də, təmiz sintetik Supabase stack-ində exit 0 verdi: **67 lokal HTTP/DB assertion**. Bu run-da `docs`, `sql_schema`, `supabase_local` job-larının hər üçü `success` oldu. Əlavə yoxlamalar beş read RPC-nin HTTP DTO/scope davranışını, xarici reservation ID və gözlənilməyən owner override parametrinin rəddini, A1-dən sonrakı property cursor səhifəsinin yalnız A2-ni qaytarmasını, eyni manager bearer-i ilə A1 revoke sonrası A1-in itirilib B1-in qalmasını əhatə edir. Manual block və contact fixture-ləri yalnız sintetik A2/B1 sətirləridir.

Altı D33 bucket-in hər birində authenticated və signed `anon` upload rəddi, service-role ilə yaradılmış eyni obyektin authenticated və anon birbaşa read rəddi yoxlanılır; service fixture hər bucket-dən sonra silinir. Bu, lokal CI stack-i üçün HTTP deny-first sübutdur. Hosted/prod konfiqurasiya, signed URL, scoped media proxy və full AT04–06 sübutu deyil; hosted SQL nəticələri aşağıda ayrıca verilib. Cari desktop mühitində Docker daemon olmadığı üçün eyni stack-i lokalda təkrar başlatmaq mümkün olmadı; nəticə yalnız GitHub Actions CI-dan götürülüb.

### Main sync və CI təkrarı

2026-11-12-də PR #68 merge olduqdan sonra branch `origin/main` ilə sinxronlaşdırıldı. Merge commit `0ef5b8a` üzrə CI #43278886453 `docs`, `sql_schema`, `supabase_local` job-larını uğurla tamamladı; sintetik lokal stack-də 67 HTTP/DB assertion yenidən icra edildi. Bu, main sync regression sübutudur, hosted Supabase və ya migration history sübutu deyil. Work-package ledger 18/90 Done göstərir; EVE-006.2 `in_progress`, parent #14 açıq qalır.

## PR #65 — izolyasiya olunmuş hosted Supabase sınağı

2026-11-12-də istifadəçinin icazəsi ilə Eve staging/production-dan ayrı, yeni Free plan Supabase layihəsi yaradıldı. Layihə yalnız PR #65 migration/sınaq üçün nəzərdə tutulub; real istifadəçi və production məlumatı yoxdur. PR branch-indəki migration 001–011 boş bazaya tətbiq olundu. `supabase migration list`-də lokal və remote versiyalar 001–011 hamısı uyğun göründü. `0062_api_surface_smoke.sql` və `0062_rls_coverage_smoke.sql` uzaq bazada exit 0 verdi.

`0062_rent_read_smoke.sql` Management API SQL runner üzərindən ilk dəfə uğursuz oldu: `SET LOCAL`/rol dəyişmə ardıcıllığı həmin sorğu runner-i üçün etibarlı psql sessiyası vermədi; bunu məhsul testi kimi qiymətləndirmədik. Sonra hosted session pooler üzərindən psql sessiyası ilə repodakı eyni smoke faylı icra edildi. Test `SET ROLE app_executor` mərhələsində dayandı, çünki `postgres` rolu `app_executor`-ə keçə bilmirdi. Yalnız bu ayrıca, silinə bilən test layihəsində `postgres` üçün müvəqqəti üzvlük verildikdən sonra eyni smoke faylı bütün assertion-ları keçdi. Sintetik fixture sətirləri silindi və sayğaclar sıfır təsdiqləndi.

Müvəqqəti rolu ləğv etmək cəhdi adi `postgres` bağlantısından alınmadı: üzvlük grantor-u `supabase_admin` idi və bu bağlantının həmin grantor adından ləğv etmək səlahiyyəti yoxdur. Nəticədə `postgres` admin rolu üzərində `app_executor` üçün test üzvlüyü qalır; `anon`, `authenticated` və digər tətbiq rollarına üzvlük verilməyib. Bu, ayrıca test layihəsinin admin konfiqurasiyasında qalıqdır və production/staging-də belə dəyişiklik edilməyib. Uzaq test layihəsi PR #65 üçün saxlanılır; bu layihə Eve-nin hər hansı mövcud davamlı mühitinin tarixçəsini müəyyən etmir.

Bu hosted sınaq fresh-install SQL ardıcıllığı və həmin izolə olunmuş bazadakı RLS/RPC smoke-u sübut edir. 2026-11-12-də istifadəçi mövcud əlçatan resurslarla davam etməyi və bu scope barədə qərarı inteqratora həvalə etdi. Əlçatan Supabase təşkilatında yalnız bu test layihəsi Eve adı ilə görünür; ayrıca Eve staging/production layihəsi və GitHub deploy qeydi tapılmadı. Bu PR-in branch migration-ları həmin boş test bazasına tətbiq edilmiş versiyalarla eynidir və migration siyahısı 001–011 üzrə uyğun gəlib. Buna görə bu PR yalnız cari, tanınmış Eve test tarixçəsi üçün merge edilə bilər; başqa Supabase hesabı/təşkilatı yoxlanmış sayılmır və ora deploy qərarı verilmir. Hosted smoke tam AT04–06, signed media, backup/restore və production qəbulunu əvəz etmir.
