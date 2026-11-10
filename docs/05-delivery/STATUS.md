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

EVE-005.1 üçün `feat/EVE-005-1-scaffold` lokal branch-ində Node 24.22.2, pnpm 12.18.0 və Next.js 16.4.6 ilə ilkin App Router scaffold yaradıldı. Həmin dəqiq Node/pnpm versiyaları ilə typecheck və production build keçdi. Bu dəyişiklik hələ remote-a göndərilməyib və main-a merge edilməyib. EVE-005.2 mühit/secret kontraktı və EVE-005.3 təmiz checkout CI işi açıq qalır.

EVE-005.2 üçün `feat/EVE-005-2-env-contract` branch-ində boş `.env.example`, public URL/publishable key validatorı və `server-only` ilə qorunan privileged-key accessor əlavə edildi. 9 env contract testi, typecheck və production build keçdi. Müstəqil review URL path-inin rəddini tələb etdi; validator və mənfi sınaq düzəldildi, təkrar yoxlamada 9/9 keçdi. Real Supabase key və hesab istifadə olunmayıb; EVE-005.2 nəticəsi də remote/main-a göndərilməyib. Bu branch lokal EVE-005.1 commit-i üzərində stacked vəziyyətdədir.

EVE-005.3 üçün `feat/EVE-005-3-ci-build` branch-ində mövcud docs workflow təmiz checkout CI-yə genişləndirildi: Node/pnpm/Python pin, frozen-lockfile install, env test, typecheck, build, contract/schema/prototype checks; action-lar full SHA ilə pinlidir və job `contents: read` səlahiyyəti ilə işləyir. Detached clean worktree-də frozen install, bütün workflow əmrləri və actionlint keçdi. GitHub Actions remote run [#42913232888](https://github.com/fuadoglu/eve/actions/runs/42913232888) `ef994cc` commit-ində, `ubuntu-24.04` runner-də tam keçdi. `.3` nəticəsi main-a merge edilməyib.

Prototip smoke-u 71 assertion ilə VM/fake-DOM yoxlamasıdır. Cloud browser workspace localhost-a qoşula bilmədiyindən screenshot/layout QA keçilmiş sayılmır. Real cihaz və 5 iştirakçılı usability testi hələ aparılmayıb.

## Hələ tamamlanmayan icra

- Production tətbiqi, executable SQL migrations/RLS, real API route-ları.
- Supabase/SMTP/Payriff/Vercel faktiki canlı konfiqurasiyası və provider sandbox sınaqları.
- Tətbiq integration/E2E/security/performance testləri, DB+media restore və rollback.
- Native GitHub Milestones, branch ruleset və required-check aktivliyinin təsdiqi.
- Hüquqi retention/refund/məxfilik mətnlərinin təsdiqi və production deploy.

## Növbəti iş

EVE-005.1–005.3 lokal nəticələrini issue/PR axınına keçirmək lazımdır; remote CI, review və merge sübutu tamamlanmayıb. Sonrakı M1 işi EVE-006 schema/RLS-dir və 005 əsas branch-ə inteqrasiya olunandan sonra başlanmalıdır. İmplementasiya taskları sübut və merge olmadan Done işarələnmir.
