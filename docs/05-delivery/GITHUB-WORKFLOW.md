# GitHub üzərindən peşəkar icra

## Repository qaydası

main stabil integration xəttidir. İlkin sənəd bootstrap-dan sonra kod üçün qısa branch+PR, squash merge. feature branch həftələrlə ayrı məhsul kimi saxlanmır. GitHub ruleset/branch protection, required checks, review və secret scanning mövcud planla faktiki aktivləşdirilməlidir; sənəddə yazılması ayarın aktiv olduğu demək deyil.

## Issue və milestone

8 milestone ROADMAP-dadır; hər birinin GitHub epic issue-su task checklist və gate saxlayır. Native milestone API/UI əlçatan olduqda eyni M0–M7 başlıqları ilə yaradılıb issue-lara bağlanır. Epic issue native milestone əvəzi kimi yanlış adlandırılmır.

Təklif label-lar: type:feature/bug/docs/security; area:auth/calendar/finance/inventory/sharing/billing; priority:p0/p1/p2; status:blocked. Label yaratma səlahiyyəti yoxdursa issue body-də eyni metadata saxlanır.

Task ID EVE-xxx sabitdir, GitHub issue nömrəsi ilə eyni olmaq məcburiyyətində deyil. Issue başlığı: [EVE-010] Rezervasiya toqquşmasının DB müdafiəsi.

## İcra və push ardıcıllığı

1. Ready issue seç, main-i yenilə, ayrıca branch/worktree aç.
2. Owned paths və dependencies inteqratorla sabitləşsin.
3. Kiçik məqsədli commit: feat(calendar): ..., fix(access): ..., docs(ux): ...
4. Branch remote-a push; draft PR aç; task/spec/test bağlantılarını yaz.
5. Code/DB/API/mobile yoxlamalarını icra et; nəticə və limitations əlavə et.
6. Müstəqil security/UX review; P0/P1 tapıntıları həll et.
7. Required checks faktiki yaşıl olduqdan sonra ready; squash merge.
8. Main-da smoke/regression; issue Done; milestone gate yenilə.
9. Release tag yalnız M7 gate və release notes-dan sonra.

## PR təsviri

Problem və yeni davranış; bağlı EVE/R/AT ID; daxil olmayan iş; data/API təsiri; mobil ekran sübutu; işlədilmiş test və nəticə; işlədilməyən yoxlama; migration/rollback; risk. Multiline body structured API və ya --body-file ilə verilir.

## CI minimumu

Docs link/ID check, typecheck, unit, DB/RLS, build. Aid tasklarda API contract, Playwright E2E, secret scan, a11y əlavə olunur. Workflow least privilege, third-party action SHA pin, untrusted PR-də production secret yoxdur. Preview deploy production bazasını istifadə etmir. Cache key dependency lock-a bağlıdır.

Bu repo ilkin docs mərhələsindədir; tətbiq CI-sı və branch ruleset aktiv kimi göstərilmir. M1 onları yaradıb real run sübutu gətirir.

## Təhlükəsizlik tapıntısı

Real secret və şəxsi məlumat issue/comment-ə yazılmır. Revoke/rotate birinci, redacted hadisə hesabatı sonra. Force-push və history silmə ayrıca əsaslandırılmış prosedurdur; agent özbaşına istifadəçi tarixçəsini yenidən yazmır.
