# EVE-019.3 — inventory copy və import DB nüvəsi

Status: **in progress**. Bu artefakt tam AT35 qəbulu deyil.

## Scope

- `api.copy_inventory` source property üçün `inventory.read`, target üçün aktiv entitlement və `inventory.manage` yoxlayır; target transaction lock altında otaq/əşya əlavə edir. Eyni adlı aktiv hədəf qeydlərini overwrite etmir və təkrar çağırış dublikat yaratmır.
- Copy qonaq, pul, qeyd, seriya nömrəsi və media ID-si köçürmür. `include_media=true` ayrıca server Storage byte clone axını tamamlanmadığı üçün açıq xəta verir.
- `import.manage` property capability-si forward migration-da əlavə olunub. `app_private.preview_inventory_rows` yalnız serverdə yoxlanmış fayldan normallaşdırılmış JSON sətirləri üçün private DB primitive-dir; 10 000 sətir limiti, sətir nömrəsi/sahə üzrə ilk 1000 xəta, ümumi `error_count`, `errors_truncated`, canonical SHA-256 preview hash və `invalid`/`preview_ready` vəziyyətini saxlayır. Xətalı preview raw sətirləri DB-də saxlamır. `app_private.commit_inventory_rows` expected version/hash, actor/property/owner scope və source row key-i yoxlayıb atomik insert edir; eyni job-un completed replay-i yeni insert etmir.
- Private primitive-lərə `anon`/`authenticated` EXECUTE yoxdur. Onlar Data API-də yayımlanmır. Server adapter və CSV/XLSX fayl parseri bu paketdə hələ yoxdur.

## Faktiki yoxlama

- PostgreSQL **16** lokal, təzə sintetik DB: repo migration-ları 001–033 tətbiq edildi; `0073_inventory_copy_import_smoke.sql` exit **0**. Sınaq eyni-property/draft/başqa owner source və target rəddi, media-copy fail-closed, sensitive field xaric edilməsi, təkrar copy, səhv sətir preview, 1001 səhvdə `invalid`/1000 göstərilən xəta/`error_count=1001`/`errors_truncated=true`, 10001 sətir rəddi, invalid/yanlış hash/stale version commit rəddi, uğurlu commit, eyni job replay, təkrar source row və başqa tenant preview/commit rəddini yoxlayır. Bu hosted Supabase və production sübutu deyil.
- `node --conditions=react-server --experimental-strip-types --test tests/unit/inventory/inventory-contract.test.ts` — 3/3 keçdi (Node 24.22.2); overflow acknowledgement və ziddiyyətli count/flag rəddi daxil.
- `node scripts/docs-check.mjs`, `node scripts/verify-contracts.mjs`, `node scripts/test-prototype.mjs` — exit **0**. Prototip 71 synthetic assertion-dır, backend sübutu deyil.
- `/tmp/eve0193-venv/bin/python scripts/validate-schemas.py` — exit **0**; izolə venv-də `jsonschema 4.25.1` və `openapi-spec-validator 0.7.2` ilə 207 schema, 14 müsbət və 23 mənfi nümunə yoxlandı. Bu tətbiq sınağı deyil.
- `git diff --check` exit **0**.

## Açıq qəbul sərhədi

`ImportPreviewInput.media_id` üçün import faylı classification/bucket, byte validation, CSV/XLSX parser, server-only HTTP adapter, private media copy, mobil UI və real provider inteqrasiyası hələ yoxdur. Buna görə EVE-019.3 `done` deyil və AT35-in full acceptance hissəsi açıqdır. `0062_api_surface_smoke.sql`, `0062_rls_coverage_smoke.sql` və CI explicit migration/test addımlarının shared allowlist yenilənməsi inteqrator ownership-indədir; həmin CI nəticəsi bu branch üçün hələ mövcud deyil.

Migration yalnız forward tətbiq olunur: yeni RPC/policy/function əlavə edir və mövcud `has_property_capability`-yə `import.manage` tanınmasını genişləndirir. Tətbiq olunmuş migration redaktə edilmir. Rollback üçün əvvəlcə server adapteri dayandırmaq, sonra yeni RPC/policy/private primitive-ləri ayrıca forward fix ilə çıxarmaq lazımdır; import edilmiş əşyalar avtomatik silinmir.
