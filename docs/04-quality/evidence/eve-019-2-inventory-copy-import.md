# EVE-019.2 — icazəli inventory copy və import preview kontraktı

Status: **Done, local component/contract scope**. Feature PR #83 squash-merge commit `ce4fbb74a1d76b48befda86cd356edbc380c0d52`; final head `8f8fd82870fff90239270b43cae461bd4ea4a7d2`.

## Scope və artefakt

`src/modules/inventory/inventory-contract.ts` OpenAPI-dəki `InventoryCopyInput`, `ImportPreviewInput` və `ImportPreview` maşın kontraktlarını runtime-da yoxlayır. Copy üçün yalnız `source_property_id` və opsional `include_media` qəbul edilir; default qərarı `false` olaraq saxlanır. Inventory preview `kind=inventory` tələb edir, `property_id` və media ID qəbul edir, əlavə/naməlum sahəni rədd edir. Preview acknowledgement state/enum, 64 simvolluq hex hash, row count və error limitləri, integer version və RFC3339 datetime daxilində yoxlanır. `InventoryProvider` yalnız serverdən alınmış DTO vəd edir; valid request lokalda server uğurunu göstərmir.

D34 private-media sərhədində URL/path DTO-ya daxil edilmir. Media authorization və property/capability yoxlaması server məsuliyyətidir və bu package-ın artefaktı deyil. Contract check source/destination icazə yoxlamasının və ya copy əməliyyatının icrası sayılmır.

## Sübut

- `node --conditions=react-server --experimental-strip-types --test tests/unit/inventory/inventory-contract.test.ts` — 3 test keçdi; invalid payload/enum/limit, SHA-256 formatı, impossible calendar date, lowercase RFC3339 `t/z`, UTC/offset leap second və year 0000–0099 künc halı əhatə olunur.
- `pnpm typecheck` — keçdi, Node `24.22.2`, pnpm `12.18.0` ilə.
- `node scripts/docs-check.mjs` — 61 Markdown faylında keçdi.
- `node scripts/verify-contracts.mjs` — 117 operation, 53 table, 256 binding, 90 DAG package və 36 scenario ilə keçdi.
- `python scripts/validate-schemas.py` — 207 schema, 12 positive və 20 negative example ilə keçdi.
- `node scripts/test-prototype.mjs` — 71 synthetic assertion keçdi; VM/fake-DOM smoke, browser/device və backend sübutu deyil.
- `git diff --check` — keçdi.
- PR #83 final head CI run #43410091454: `docs`, PostgreSQL 17 `sql_schema`, fresh synthetic `supabase_local` hamısı SUCCESS. Bu CI job-ları repo-wide gate-lərdir; import parser/copy integration bu PR-də olmadığı üçün onların EVE-019.2 server behavior sübutu kimi şərhi yoxdur.
- Müstəqil read-only QA review əvvəl P1/P2 tapmadı, RFC3339 tarix yoxlamasında iki P3 kənar hal göstərdi; düzəliş və regression-lardan sonra follow-up review aşağı-il Date.UTC remapping halının da bağlandığını, qalan konkret tapıntı olmadığını təsdiqlədi. Bu GitHub insan approval-u deyil.

## Açıq sərhədlər

Server route/RPC, source/destination tenant authorization, DB transaction/copy, private media copy, CSV/XLSX file parsing, import deduplication/commit, UI, hosted Eve Supabase və production yoxlaması bu scope-da yoxdur. Buna görə AT35-in tenant-safe copy və real import/commit E2E hissəsi EVE-019.3/full acceptance üçün açıqdır; parent issue #27 və production gate-ləri açıq qalır.
