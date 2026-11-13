# EVE-008.2 — Email dəvəti və ev icazəsi

Tarix: 2026-11-13. Status: **branch-də implementasiya; CI və müstəqil review gözlənilir**.

## İzləmə

- Issue: [#16 — EVE-008](https://github.com/fuadoglu/eve/issues/16)
- Branch: `feat/EVE-008-2-manager-invite`
- Paket statusu: `in_progress`; main ledger 24/90 (26.7%), bu branch hələ sayılmır.
- DB migration: `20261113001700_eve_manager_invites.sql` (yalnız forward).
- D35: birdəfəlik email-match dəvət üçün 24 saatlıq maximum TTL; NIST istinadı yalnız comparator-dur, Eve auth deyil.
- D33 media seçimi: ayrı private inventory bucket artıq main-dakı D34 qərarı və EVE-019.1 ilə tətbiq olunub.

## Dəyişiklik

- `api.create_manager_invite` path property-nin siyahıda olmasını, 1–100 eyni-owner property-ni, hər evdə active/trial entitlement-i, `daily`/`full` permission-u, normalized email və SHA-256 token hash-i transaction daxilində yoxlayır. Hər owner/email üçün əvvəlki pending invite ləğv olunur; raw bearer token qəbul edilmir və cavabda hash yoxdur.
- `api.accept_manager_invite` hash/email/state/expiry-ni yoxlayır, bütün property entitlement-lərini yenidən yoxlayır, revoked membership-i bərpa edə və bütün property membership-lərini atomik yarada bilir. Yanlış email neytral 404-dür, expiry state-ni `expired` edib membership yaratmır; replay rədd edilir.
- Pending recipient yalnız öz dəvətində seçilmiş property və subscription sətirlərini executor/RLS daxilində entitlement recheck üçün görə bilər; normal property-list RPC capability yoxlaması ilə invite olunmuş, hələ qəbul edilməmiş evi qaytarmır.
- `invited_by_user_id` dəvət sahibini membership `granted_by` üçün saxlayır, beləliklə manager accept zamanı owner_accounts tenant sətirinə əlavə read policy açılmır.
- `invite-token.ts` serverdə 256-bit token yaradır və SHA-256 hex qaytarır; raw token yalnız delivery adapterinə ötürülməlidir.
- Data dictionary, field bindings, state machine, OpenAPI, RLS/grant/API allowlist smoke və CI migration zənciri yenilənib.

## Hazırkı yoxlama

- `node scripts/docs-check.mjs` — PASS (60 Markdown files).
- `node scripts/verify-contracts.mjs` — PASS (117 API operations, 52 tables, 256 field bindings, 90 acyclic packages, 16 trace rows, 36 scenarios).
- `python3 scripts/verify-storage-config.py` — PASS (7 private buckets).
- `node scripts/test-prototype.mjs` — PASS (71 synthetic VM/fake-DOM assertions; backend/mobile acceptance deyil).
- `node --conditions=react-server --experimental-strip-types --test tests/unit/access/invite-token.test.ts` — PASS (2/2).
- `node_modules/.bin/tsc --noEmit -p tsconfig.json` — PASS.
- `git diff --check` — PASS.
- `supabase/tests/0062_manager_invite_smoke.sql` PostgreSQL 17 və fresh Supabase local CI-da işləmək üçün əlavə edilib; local Docker daemon yoxdur, ona görə real DB nəticəsi hələ yoxdur.
- Python JSON Schema validatori bu worktree-də `jsonschema` quraşdırılmadığı üçün işləməyib; CI nəticəsi gözlənilir.

## Scope və açıq gate-lər

Bu komponent yoxlaması HTTP/server route, browser UI, real SMTP/provider delivery, hosted Eve Supabase, full AT04–06/AT25, backup/restore və production acceptance deyil. SMTP göndərmə təsdiqi yoxdursa server `saved/sent` uğuru göstərməməlidir. PR CI, SQL smoke, independent QA/red-team review və merge başa çatmamış paket `done` sayıla bilməz.
