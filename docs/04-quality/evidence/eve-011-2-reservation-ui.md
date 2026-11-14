# EVE-011.2 — Rezervasiya form/detail və server balance

**Status:** component scope `done`; tam AT07–11 integration EVE-011.3-də açıqdır.
**Feature PR:** [#93](https://github.com/fuadoglu/eve/pull/93), squash merge `d16b36c6fed98b0fc6ffcb1bb3169a3d282fce9a`.
**Branch commit:** `9d695b14d03ac8273e015c144eae9202481d61f0`.
**Müstəqil review:** `qa_redteam`; API error envelope ilkin finding-i düzəldildi, follow-up-da qalıq finding yoxdur.

## Scope və davranış

- `ReservationForm` OpenAPI create sahələri/enum-larından input yaradır; AZN məbləğləri integer qəpiklə serializasiya edir.
- Telefon üçün `+` beynəlxalq format tələb edilir; ayırıcılar normallaşdırılır, ölkə kodu təxmin edilmir.
- Eyni payload retry zamanı idempotency key saxlanır; payload dəyişəndə yeni key yaradılır.
- Uğur yalnız strict, property-scoped server `ReservationEnvelope` təsdiqindən sonra göstərilir. Offline/server error halında form məlumatı saxlanır və raw provider/backend mətni göstərilmir.
- API error `{ error: { code, message, field_errors?, request_id } }` formasından yalnız allowlist sahələri lokallaşdırılır.
- Detail `ReservationBalance` server DTO-sunu göstərir; client qalıq hesablamır.
- `FLOW-SPEC.md` qonaq adı limitini OpenAPI/data model ilə 150 simvola uyğunlaşdırır.
- UI component-ləri route/provider-a qoşulmayıb; bu paket inteqrasiya sübutu iddia etmir.

## Yoxlama sübutu

Feature PR CI run #43574410269: `docs`, PostgreSQL 17 `sql_schema`, fresh synthetic `supabase_local` — hamısı SUCCESS. `docs` job daxilində yeni `test:reservations` 9/9, typecheck, production build, Chromium mobile shell, docs-check, contract verification, storage config, JSON schema və prototype smoke keçdi. `supabase_local` migration/RLS/Storage smoke-ları keçdi; bu paketdə yeni DB migration yoxdur.

Əlavə local yoxlamalar:

- `pnpm test:reservations` — 9/9.
- `pnpm typecheck` — exit 0.
- `pnpm build` — exit 0.
- `node scripts/docs-check.mjs` — 66 Markdown faylı.
- `node scripts/verify-contracts.mjs` — 117 operations, 53 tables, 256 field bindings, 90 acyclic packages, 16 trace rows, 36 scenarios.
- `python3 scripts/verify-storage-config.py` — 7 private bucket, D33/D34 uyğunluğu.
- JSON Schema validator — 207 schema, 12 positive / 20 negative.
- `node scripts/test-prototype.mjs` — 71 synthetic assertion; VM/fake-DOM smoke, brauzer və backend sübutu deyil.
- `pnpm install --frozen-lockfile`, `git diff --check` — keçdi.

## Açıq sərhədlər

Bu paket full AT07–11 E2E, mobile reservation route/provider integration, hosted Eve Supabase migration history, backup/restore, real iOS/Android/accessibility cihaz sübutu və production deploy-u bağlamır. Bunlar EVE-011.3 və release gate-lərində qalır. Paket production-ready deyil.
