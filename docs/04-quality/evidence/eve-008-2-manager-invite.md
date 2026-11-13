# EVE-008.2 — Email dəvəti və ev icazəsi

Tarix: 2026-11-13. Status: **merged; EVE-008.2 local DB/RPC component DoD tamamlandı**.

## İzləmə

- Issue: [#16 — EVE-008](https://github.com/fuadoglu/eve/issues/16)
- Branch: `feat/EVE-008-2-manager-invite`
- PR: [#79 — feat(EVE-008.2): add manager invite persistence](https://github.com/fuadoglu/eve/pull/79), squash merge `59fea750fbb1a3bcb34b6407085c059e1982475e`.
- Final PR head: `afc24586155f42f905d3de1712b034984a3812fd`; main branch merge commit CI: [run #43405445062](https://github.com/fuadoglu/eve/actions/runs/43405445062); final PR CI: [run #43405186105](https://github.com/fuadoglu/eve/actions/runs/43405186105). Hər iki run-da `docs`, `sql_schema`, `supabase_local` PASS.
- Paket statusu: `done`; PR #80 closure-record merge olunduqdan sonra delivery ledger 25/90 (27.8%) olacaq; PR #80-dən əvvəlki main snapshot 24/90 (26.7%) idi.
- DB migration: `20261113001700_eve_manager_invites.sql` (yalnız forward; verified `auth.users` email və client tərəfindən saxtalaşdırıla bilməyən transaction-scoped accept context ilə).
- D35: birdəfəlik email-match dəvət üçün 24 saatlıq maximum TTL; NIST istinadı yalnız comparator-dur, Eve auth deyil.
- D33 media seçimi: ayrı private inventory bucket artıq main-dakı D34 qərarı və EVE-019.1 ilə tətbiq olunub.

## Dəyişiklik

- `api.create_manager_invite` path property-nin siyahıda olmasını, 1–100 eyni-owner property-ni, hər evdə active/trial entitlement-i, `daily`/`full` permission-u, normalized email və SHA-256 token hash-i transaction daxilində yoxlayır. Hər owner/email üçün əvvəlki pending invite ləğv olunur; raw bearer token qəbul edilmir və cavabda hash yoxdur.
- `api.accept_manager_invite` hash/email/state/expiry-ni yoxlayır, JWT email-ini Supabase Auth-da təsdiqlənmiş cari email ilə tutuşdurur, bütün property entitlement-lərini yenidən yoxlayır, revoked membership-i bərpa edə və bütün property membership-lərini atomik yarada bilir. Yanlış email neytral 404-dür, expiry state-ni `expired` edib membership yaratmır; replay rədd edilir.
- Recipient-in entitlement üçün lazım olan property/subscription oxunuşu yalnız kilidlənmiş, pending, təsdiqli email-ə aid və müddəti keçməmiş konkret invite ID üçün DB transaction context-i ilə mümkündür. Context transaction ID/backend PID/actor ilə bağlanır, yalnız SECURITY DEFINER RPC yaradır; ayrıca dar SECURITY DEFINER cleanup funksiyası accept bitəndə silir, xəta zamanı transaction rollback edir. User-settable custom GUC authorization üçün istifadə edilmir; adi property list-ə invite property-ləri daxil olmur.
- Pending recipient yalnız öz dəvətində seçilmiş property və subscription sətirlərini executor/RLS daxilində entitlement recheck üçün görə bilər; normal property-list RPC capability yoxlaması ilə invite olunmuş, hələ qəbul edilməmiş evi qaytarmır.
- `invited_by_user_id` dəvət sahibini membership `granted_by` üçün saxlayır, beləliklə manager accept zamanı owner_accounts tenant sətirinə əlavə read policy açılmır.
- `invite-token.ts` serverdə 256-bit token yaradır və SHA-256 hex qaytarır; raw token yalnız delivery adapterinə ötürülməlidir.
- Data dictionary, field bindings, state machine, OpenAPI, RLS/grant/API allowlist smoke və CI migration zənciri yenilənib.

## Hazırkı yoxlama

- `node scripts/docs-check.mjs` — PASS (60 Markdown files).
- `node scripts/verify-contracts.mjs` — PASS (117 API operations, 53 tables, 256 field bindings, 90 acyclic packages, 16 trace rows, 36 scenarios); CI Python JSON Schema/OpenAPI validator — PASS.
- `python3 scripts/verify-storage-config.py` — PASS (7 private buckets).
- `node scripts/test-prototype.mjs` — PASS (71 synthetic VM/fake-DOM assertions; backend/mobile acceptance deyil).
- `node --conditions=react-server --experimental-strip-types --test tests/unit/access/invite-token.test.ts` — PASS (2/2).
- `node_modules/.bin/tsc --noEmit -p tsconfig.json` — PASS.
- `git diff --check` — PASS.
- `supabase/tests/0062_manager_invite_smoke.sql` və `0062_rls_coverage_smoke.sql` PostgreSQL 17 `sql_schema` job-unda, həmçinin fresh synthetic Supabase local stack-də CI run #43405186105 və main CI #43405445062 ilə PASS; local Docker daemon yoxdur.
- EVE-008.2 üzrə müstəqil read-only QA review son diff-də P1/P2 blocker tapmadı; bu GitHub human approval deyil.

## API sərhədi və idempotency

OpenAPI create/accept əməliyyatları `Idempotency-Key` tələb edir. Bu PR-dəki DB RPC komponenti HTTP/server idempotency wrapper-ını və `idempotency_keys` yazısını implement etmir; buna görə OpenAPI əməliyyatlarının tam idempotent API davranışı kimi təqdim edilmir və bu paket yalnız lokal DB/RLS komponent sübutu ilə məhduddur. Full route acceptance ayrıca qalır.

## Scope və açıq gate-lər

Bu komponent yoxlaması HTTP/server route, browser UI, real SMTP/provider delivery, hosted Eve Supabase, full AT04–06/AT25, backup/restore və production acceptance deyil. SMTP göndərmə təsdiqi yoxdursa server `saved/sent` uğuru göstərməməlidir. Bu paket DoD-ni bağlayır, amma parent EVE-008/#16 və production gate-lərini bağlamır.
