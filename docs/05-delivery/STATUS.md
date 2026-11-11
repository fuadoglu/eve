# Faktiki icra vəziyyəti

Tarix: 2026-11-11 (Asia/Baku). Mərhələ: **M1 scaffold və CI inteqrasiyası**. Tətbiq production-ready deyil.

## Tamamlanmış sənəd müqaviləsi

R01–R16 tələb xəritəsi, 117 OpenAPI əməliyyatı, 52 data cədvəli, 257 field binding, 5 state machine və 36 qəbul ssenarisi yoxlanır. EVE-001 PR #43–#46 və EVE-004 PR #47–#49 main-a merge edilib. `node scripts/docs-check.mjs`, `node scripts/verify-contracts.mjs`, Python OpenAPI/JSON Schema validatoru və prototip smoke main-da keçib. Bu yoxlamalar işləyən API/DB və ya məhsul qəbul sınağı deyil.

## M1 kod və yoxlama

- EVE-005.1 PR #40 merge `3dc2d89`: pinlənmiş Node/pnpm/Next.js/TypeScript scaffold. Merged main-da frozen lockfile install, typecheck və build keçdi.
- EVE-005.2 PR #41 merge `6c3cddb`: boş env nümunəsi, public Supabase konfiqurasiya validatoru, server-only secret accessor. Merged main-da 9/9 env testi, typecheck və build keçdi. Real Supabase hesabı/credential işlədilməyib.
- EVE-005.3 PR #42: təmiz checkout GitHub Actions CI (frozen install, env test, typecheck, build, docs/contracts/schema/prototip) review/merge mərhələsindədir. PR CI və merge commit sübutu həmin PR-də qeyd olunur; main-a merge edilmədən Done sayılmır.
- Sənəd prototipi VM/fake-DOM-da 71 assertion keçir. Brauzer layout, real cihaz və 5 iştirakçılı usability sınağı aparılmayıb.

## GitHub qoruması

Repo public-dir. M0–M7 native milestone-lar yaradılıb. `main` branch protection PR, `docs` required check, linear history və admin enforcement tələb edir; approval sayı 0-dır. Secret scanning və push protection aktivdir. Ayrıca GitHub ruleset qurulmayıb; daxili müstəqil agent review-u GitHub insan approval-u kimi göstərilmir.

## Açıq production qapıları

Executable SQL migrations/RLS, real API route-ları, passwordless auth, tenant/property/capability mənfi testləri və bütün domain axınları hələ yoxdur. Supabase/SMTP/Payriff/Vercel hesabları, provider sandbox, hüquqi mətn təsdiqi, real usability, DB+private media restore və AT01–36 tətbiq sınaqları da açıqdır. [Xarici asılılıqlar](EXTERNAL-DEPENDENCIES.md) reyestrində ayrıca izlənir. Provider yoxluğu local schema/UI işini dayandırmır; sandbox PASS iddia edilmir.

## Növbəti iş

PR #42 CI və müstəqil baxışdan sonra squash merge edilir, merged-main smoke işlədilir. Sonra EVE-006 SQL schema/RLS paketinə keçilir. EVE-005 yalnız merge, yoxlama və status sübutu tamamlandıqda Done edilir.
