# EVE-019.3 — inventory copy/import parser və DB acceptance sübutu

Tarix: 2026-11-18. Branch: `feat/EVE-019-3-import-parser-final`. Status: **in progress; PR CI və müstəqil review gözləyir**. Bu paket scope-u tam AT35, tam import route/UI və production qəbulu deyil.

## Scope və davranış

- `api.copy_inventory` source property üçün `inventory.read`, target üçün aktiv entitlement və `inventory.manage` yoxlayır; transaction lock altında yalnız otaq/əşya məlumatını əlavə edir. Eyni adlı aktiv hədəf qeydlərini overwrite etmir. Guest, pul, qeyd, serial nömrəsi və media ID-si köçürülmür; `include_media=true` fail-closed olur.
- Private DB preview/commit primitive-lər `app_private` daxilindədir; `anon`/`authenticated` üçün birbaşa execute yoxdur. Preview yalnız serverdə yoxlanmış/normalize edilmiş rows alır, xətalı raw row-ları saxlamır, preview hash + version yoxlayır və atomik commit/replay verir.
- CSV/XLSX parser 10 MiB, 5,000 data row, 6 column, 2,000 UTF-16 code unit/cell və D46-da qeydə alınmış XLSX ZIP/workbook limitlərini tətbiq edir. Preview response-da source file row number saxlanır; CSV-də quoted multiline record-un başlanğıc fiziki sətri, XLSX-də worksheet sətri istifadə edilir.
- Import faylı `private_import` / `eve-private-import` private bucket boundary-sinə bağlanıb. Bucket client birbaşa upload-a bağlıdır; media DTO və permanent inventory media axınından ayrıdır. Upload/retention route-u bu task scope-unda yoxdur.

## Cari branch-də faktiki yoxlama

Runtime: Node.js 24.22.2 və pnpm 12.18.0 (`/tmp/eve0193-toolchain`, repository xaricində).

- `pnpm test:inventory` — **14/14 keçdi**; CSV/XLSX positive/negative, source row number, row/file/cell bounds, ZIP compression-ratio/entry/inflated-size caps, traversal path/XML entity rejection, formula/extra workbook və contract DTO.
- `pnpm typecheck` — **keçdi**.
- `pnpm build` — **keçdi**; Next.js production build.
- `node scripts/docs-check.mjs` — **keçdi**, 93 Markdown faylı.
- `node scripts/verify-contracts.mjs` — **keçdi**, 118 operation, 56 table, 258 binding, 90 package.
- `python3 scripts/verify-storage-config.py` — **keçdi**, 8 bucket, D46 byte/check boundary.
- `node scripts/test-prototype.mjs` — **keçdi**, 71 synthetic assertion; backend/UX acceptance sübutu deyil.
- `/tmp/eve0193-venv/bin/python scripts/validate-schemas.py` — **keçdi**, 207 schema, 14 positive / 23 negative example.
- `git diff --check` — **keçdi**.

## DB/CI və müstəqil review

`supabase/tests/0073_inventory_copy_import_smoke.sql`-a 5,001 row rejection, source row number, private bucket privacy/policy və anon/authenticated Storage write denial əlavə edildi. `sql_schema` Storage fixture-ə `eve-private-import` bucket əlavə olunub. CI-yə migration 033, sonrakı private-import migrations 037/038, parser suite və smoke 0073 daxil edilib. Cari host-da Docker/PostgreSQL yoxdur, ona görə migration/smoke localda işlədilməyib. Bunun əvəzinə PR #150 CI run [#44264914510](https://github.com/fuadoglu/eve/actions/runs/44264914510) `docs`, PostgreSQL 17 `sql_schema` və fresh `supabase_local` job-larının üçünü də **pass** etdi; `0073_inventory_copy_import_smoke.sql`, 0062 allowlist-ləri və HTTP storage boundary sınaqları CI-də işlədildi. Bu hosted CI/synthetic local stack sübutudur, Eve staging/production DB sübutu deyil.

Müstəqil read-only integration review PR head `a31a8c339deae656f930e4f52b4596398adbde09`-da tamamlandı; ilkin tapıntılar (sql_schema bucket seed və ZIP adversarial coverage) düzəldildi, follow-up review əlavə P0/P1 blocker tapmadı. Review agenti sınaqları özü işlətməyib; test sübutu yuxarıdakı local/CI nəticələridir. Squash merge və merged-main CI hələ gözlənir.

## Qəbul sərhədləri və risk

Server HTTP/session adapteri, upload/fayl byte verification lifecycle, import preview/confirm mobil UI, CSV/XLSX-dən DB-yə canlı route-to-DB E2E və AT35 full acceptance bu taskda yoxdur. Buna görə parent #27 və full AT35 açıq qalır; bu iş production-ready iddiası vermir. Migration 033 və 037/038 forward-only-dir; tətbiq edilmiş migration dəyişdirilmir. DB CI uğursuz olsa merge dayandırılmalı və migration/allowlist düzəldilməlidir; uğursuz cəhd yarımçıq import məlumatı yaratmamalıdır.
