# Faktiki icra vəziyyəti

Tarix: 2026-11-11 (Asia/Baku). Mərhələ: **icra üçün genişləndirilmiş sənəd və müqavilə təhvili**.

## Mövcud artefaktlar

- Azərbaycan dilində məhsul, qərar, əməliyyat, maliyyə, paylaşım və təhlükəsizlik müqavilələri.
- Hər endpoint üçün request/response/security metadata olan OpenAPI 3.1 JSON.
- Cədvəl/sütun/constraint/RLS/retention data dictionary və API→DB field bindings.
- Status keçidləri, versiyalanmış konfiqurasiya, 16 tələb üzrə izləmə matrisi.
- UI01–19 kliklənən sənəd prototipi və dəqiq forma axınları.
- 30 parent GitHub issue daxilində 90 atomik iş paketi, dependency və external gate fərqi.
- 36 ətraflı Given/When/Then qəbul ssenarisi; Codex multiagent müqaviləsi.
- Müstəqil security/delivery sənəd red-team baxışı və düzəliş reyestri.
- Sənəd, kontrakt, schema və demo smoke script-ləri, GitHub Actions konfiqurasiyası.

## Faktiki yoxlama

2026-11-11-də sənəd linkləri, müqavilə bütövlüyü, OpenAPI/JSON Schema və demo smoke yerli icra edildi: docs-check, contract verification, 207 JSON Schema və 32 müsbət/mənfi nümunə, həmçinin 71 assertion-lı demo smoke uğurlu oldu. Prototip smoke-u VM/fake-DOM yoxlamasıdır; brauzer layout və real istifadəçi sınağı deyil. Python validatorı layihənin `scripts/requirements-docs.txt` asılılıqları müvəqqəti venv-ə qurulduqdan sonra keçdi.

EVE-005.1 üçün `feat/EVE-005-1-scaffold` branch-ində Node 24.22.2, pnpm 12.18.0 və Next.js 16.4.6 ilə ilkin App Router scaffold yaradıldı. Həmin dəqiq Node/pnpm versiyaları ilə typecheck və production build keçdi. Dəyişiklik remote PR #40-da review üçün açıqdır; main-a merge edilməyib.

EVE-005.2 üçün `feat/EVE-005-2-env-contract` branch-ində boş `.env.example`, public URL/publishable key validatorı və `server-only` ilə qorunan privileged-key accessor əlavə edildi. 9 env contract testi, typecheck və production build keçdi. Müstəqil review URL path-inin rəddini tələb etdi; validator və mənfi sınaq düzəldildi, təkrar yoxlamada 9/9 keçdi. Real Supabase key və hesab istifadə olunmayıb. PR #41 review üçün açıq və #40 üzərinə stacked-dir; öz base branch-ində workflow check görünmür. #40 merge olduqdan sonra #41-i `main`-a retarget edib CI-ni işə salmaq lazımdır.

EVE-005.3 üçün `feat/EVE-005-3-ci-build` branch-ində mövcud docs workflow təmiz checkout CI-yə genişləndirildi: Node/pnpm/Python pin, frozen-lockfile install, env test, typecheck, build, contract/schema/prototype checks; action-lar full SHA ilə pinlidir və job `contents: read` səlahiyyəti ilə işləyir. `pull_request` trigger-i EVE-005 stacked base branch-lərini də əhatə edir. GitHub Actions run [#42914633039](https://github.com/fuadoglu/eve/actions/runs/42914633039) push, [#42914643281](https://github.com/fuadoglu/eve/actions/runs/42914643281) pull request event-ində `b2261ad` commit-i, `ubuntu-24.04` runner-də tam keçdi. PR #42 review üçün açıqdır; #41 üzərinə stacked və main-a merge edilməyib.

Prototip smoke-u 71 assertion ilə VM/fake-DOM yoxlamasıdır. Cloud browser workspace localhost-a qoşula bilmədiyindən screenshot/layout QA keçilmiş sayılmır. Real cihaz və 5 iştirakçılı usability testi hələ aparılmayıb.

## Hələ tamamlanmayan icra

- Production tətbiqi, executable SQL migrations/RLS, real API route-ları.
- Supabase/SMTP/Payriff/Vercel faktiki canlı konfiqurasiyası və provider sandbox sınaqları.
- Tətbiq integration/E2E/security/performance testləri, DB+media restore və rollback.
- Native GitHub Milestones, branch ruleset və required-check aktivliyinin təsdiqi. Private repo planı ruleset/branch protection API-sini 403 ilə rədd edir; qayda aktivliyi təsdiqlənməyib.
- Hüquqi retention/refund/məxfilik mətnlərinin təsdiqi və production deploy.

## Növbəti iş

EVE-005.1–005.3 remote PR #40–#42-də review üçün açıqdır. #40 və #42 CI nəticələri uğurludur; #41 stacked base-i səbəbilə check almır və #40 merge olduqdan sonra `main`-a retarget edilməlidir. İnsan GitHub review qərarı yoxdur; daxili müstəqil agent review-lər bloklayıcı tapıntısız bitib. Branch ruleset/required-check enforcement plan məhdudiyyəti səbəbilə təsdiqlənməyib. Squash merge və main smoke-dan sonra issue Done edilə bilər; o vaxta qədər tasklar Done deyil. Sonrakı M1 işi EVE-006 schema/RLS-dir və 005 əsas branch-ə inteqrasiya olunandan sonra başlanmalıdır.
