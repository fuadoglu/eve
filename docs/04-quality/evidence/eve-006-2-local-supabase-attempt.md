# EVE-006.2 — lokal Data API/Storage sınaq cəhdi

Tarix: 2026-11-12, Asia/Baku. Branch: `feat/EVE-006-2-access-closure`. Mühit: macOS 27.2 arm64, Colima Docker, Supabase CLI 2.33.9, lokal Supabase PostgreSQL image `17.4.1.068`; sonra CLI 3.1.0 sınağı. Yalnız lokal sintetik mühit; hosted Supabase, real istifadəçi və real media yoxdur.

## Faktiki nəticə

1. `colima start --cpu 4 --memory 6` exit 0. `supabase start` CLI 2.33.9 migration `20261111000200_eve_access_policies.sql` tətbiqində exit 1 / `unexpected EOF` verdi. PostgreSQL konteyner logunda həmin migration-ın `grant app_executor to current_user with set true, inherit false` əmri işləyərkən backend prosesinin `signal 11: Segmentation fault` ilə dayandığı görünür. Bu, PostgreSQL 17 CI nəticəsini əvəz etmir: CI-nin adi `postgres:17` image-i bu əmri keçirir.
2. Eyni lokal image-də ayrıca minimal təkrar: `create role app_executor nologin nobypassrls noinherit` keçdi; `grant app_executor to current_user with set true, inherit false` bağlantını server crash ilə bağladı; sadə `grant app_executor to postgres` keçdi; explicit option-lu GRANT təkrar crash verdi. Bu, image/əmr uyğunluğuna dair lokal müşahidədir; hosted provayderin davranışı barədə nəticə deyil.
3. CLI 3.1.0 ilə tam stack sınağı image yüklənərkən host diskində 184 MiB yer qalması və Docker/containerd `input/output error` ilə dayandı. Nəticədə Data API və Storage HTTP mənfi sınaqları **icra edilmədi**. Yalnız bu task üçün yaranmış müvəqqəti npm/Playwright cache-i təmizlənəndən sonra host diskində 426 MiB boş yer var idi. Başqa layihənin konteynerləri və repository migration-ları dəyişdirilmədi.

## Bu incrementin yoxlaması

`supabase/tests/0062_api_surface_smoke.sql` mövcud yeddi `api` RPC-nin inventory-sini, funksiyanın `app_executor` sahibi olmasını, `SECURITY DEFINER` və boş `search_path`-ı, anon EXECUTE rəddini, authenticated EXECUTE allowlist-ini və `api` relation olmamasını kataloqda yoxlayır. Lokal Supabase crash üzündən bu SQL orada işlədilmədi; PR CI-nin PostgreSQL 17 `sql_schema` job-u nəticəni ayrıca göstərəcək. Mövcud 52 cədvəl RLS/grant guard-ı dəyişməyib.

## Qapı

EVE-006.2 `in_progress` qalır. Lokal Supabase Data API/Storage və hosted provider testləri keçmiş kimi yazılmır. Tarixdəki migration 002 redaktə edilmədi; bu uyğunsuzluğun təhlükəsiz aradan qaldırılması ayrıca review tələb edir. Gələcək domain write/media RPC-ləri öz asılı paketlərində default-deny qaydası ilə açılır.
