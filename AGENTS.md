# Eve — Codex multiagent icra müqaviləsi

Bu fayl bütün repository-yə aiddir. Məqsəd Azərbaycan dilindəki məhsul müqaviləsini işlək, təhlükəsiz, sürətli və sadə mobil məhsula çevirməkdir. İstifadəçi multiagent icranı açıq tələb edib. Paralelləşmə keyfiyyət məqsədinə xidmət edir, özü məqsəd deyil.

## 1. Başlanğıc

İnteqrator əvvəl README, docs/INDEX, DECISIONS, PRD, ROADMAP, BACKLOG, SECURITY və STATUS oxuyur. Aid modulun spesifikasiyası və qəbul testləri oxunmadan kod yazılmır. Mövcud repo/code/test faktiki yoxlanılır; sənəddə planlanan qovluq və script işlək hesab edilmir.

Maşın müqavilələri openapi.json, data-dictionary.json, state-machines.json, field-bindings.json, configuration.json, traceability.json və work-packages.json-dır. Sənəd dəyişəndə node scripts/docs-check.mjs, node scripts/verify-contracts.mjs, Python schema validator və prototip smoke işlədilir. API/DB enum və sahə limitləri fərqli qala bilməz. 90 iş paketi mövcud 30 parent issue daxilində izlənir; provider sandbox gate-i müstəqil local scaffold/schema/UI işini bloklamır.

Göstəriş prioriteti: cari istifadəçi tapşırığı → bu müqavilə və qərar reyestri → modul sənədi → task. Ziddiyyəti gizlətmək olmaz; təsirlənən müqavilələri eyni PR-də düzəlt. Provider/hüquqi faktı uydurma.

## 2. Rollar

| Rol | Məsuliyyət |
|---|---|
| İnteqrator | Plan, kritik yol, interface/fayl bölgüsü, integration, status və yekun sübut |
| UX/frontend | Mobil ekranlar, accessibility, loading/error/offline, dizayn tokenləri |
| Data/backend | Schema, RPC, RLS, domain state machine və API |
| İnteqrasiya | Auth/SMTP/Payriff/media/scheduler adapterləri və sandbox |
| QA/red-team | Müstəqil mənfi sınaq, regression, privacy, performance və release gate |

Kiçik task üçün hamısını spawn etmək lazım deyil. Asılı olmayan işlər paraleldir; müəllif öz kritik işinin yeganə reviewer-i olmur. Agent slot sayı mühitə görə seçilir.

## 3. Hər agentə verilən task müqaviləsi

Task ID; məqsəd; daxil/daxil olmayan iş; asılılıqlar; dəyişdirilə bilən fayl/qovluqlar; dəyişdirilməsi qadağan ortaq fayllar; API/schema müqaviləsi; qəbul ID-ləri; yoxlama əmrləri; gözlənən artefakt; bloklayıcılar.

Agent taskdan kənar böyük refaktor və funksiya əlavə etmir. Tələbi sadələşdirmək adı ilə təhlükəsizlik və data invariantı çıxarılmır.

## 4. Paralel iş və fayl ownership

- Hər yazan agentə ayrıca branch və Git worktree; ortaq working tree-də paralel mutasiya yoxdur.
- Branch: feat/EVE-012-reservation-flow, fix/EVE-042-policy, docs/EVE-005-ux.
- İnteqrator əvvəl task→branch→owned paths cədvəlini issue/PR-də qeyd edir.
- Eyni faylın eyni vaxtda iki yazarı yoxdur. Ortaq dəyişiklik tələb olunarsa inteqratora təklif göndərilir.
- DB schema/migration nömrəsi, API types/OpenAPI, lockfile, env kontraktı və dizayn tokenləri inteqratorun koordinasiyasındadır.
- Dependency input-ları dəyişərkən ikinci agent install/lockfile update etmir.
- Ortak müqavilələr hazır olmadan frontend/backend ziddiyyətli fərziyyələrlə paralel getmir.
- Rebase/cherry-pick inteqrator nəzarətindədir; başqa agentin dəyişikliyi revert edilmir.
- Migration eyni nömrə ilə yaranmır, tətbiq edilmiş migration edit edilmir; yeni migration yazılır.

## 5. İş üsulu

1. Repo və task vəziyyətini yoxla.
2. Minimal plan, interfaces və qəbul testlərini müəyyən et.
3. Lazım olan bounded işləri agentlərə ver.
4. Məhsul davranışını implement et, stub/mock-u production kimi göstərmə.
5. Uyğun testləri bir dəfə mənalı icra et; failure və yeni dəyişiklik varsa təkrarla.
6. Müstəqil reviewer/red-team nəticəsini həll et.
7. İnteqrator merged nəticədə regression yoxlasın.
8. Status və sübutları eyni PR-də yenilə.

Uzun işləyən agent 60 saniyədən çox susmamaq üçün mənalı irəliləyiş məlumatı verir. Bloklanan task qalan müstəqil işi dayandırmır; lakin gate uydurma yolla keçilmir.

## 6. Qəti invariantlar

- Şifrə axını yoxdur; email link + yenilənən sessiya.
- Tenant/property/capability hər server əməliyyatında yoxlanır; RLS və storage uyğun.
- Public səhifə noindex-dir, amma private sayılmır; yalnız safe DTO.
- Public təqvim dolu/blok səbəbi göstərmir; date seçimi rezervasiya deyil.
- Eve kirayə pulu qəbul etmir; Payriff yalnız abunə.
- Pul integer qəpik; deposit gəlir deyil; settlement ikinci receipt deyil.
- Occupancy DB constraint və transaction ilə qorunur.
- Gündəlik inventar day/event/side/revision modelidir, snapshot dəyişməzdir.
- GET heç bir task/inspection/payment vəziyyətini dəyişmir.
- Tokenlər hash, dar scope, expiry/revoke; logda raw token yoxdur.
- Safety QR abunə bitdiyi üçün qəfil bağlanmır.
- Server ack yoxdursa UI uğur/saved göstərmir.

## 7. Multiagent təhvil formatı

Agent nəticəsində: task ID; commit/branch; dəyişmiş fayllar; davranış; hər acceptance üzrə sübut; işlədilən əmrlər və exit nəticəsi; işlədilməyən test və səbəb; məlum risk; migration/rollback təsiri. “Testlər keçdi” yalnız real nəticə ilə.

Mock / local integration / provider sandbox / production sübutu ayrı işarələnir. Screenshot backend və RLS sübutu deyil. Review agenti təsdiq üçün konkret fayl/line və test tələb edir.

## 8. GitHub intizamı

Issue → Ready → branch/worktree → draft PR → CI/review → squash merge → issue Done. Main-a kod işi birbaşa push edilmir; bu ilkin docs bootstrap-dan sonrakı siyasətdir. Commitlər bir məqsədli Conventional Commits-dir. PR-də task/tələb/test ID, mobile proof, schema/API, migration və limitations var.

Main ruleset, required checks və native milestone faktiki aktivliyi ayrıca yoxlanılır; sənəddə olması aktiv olduğu demək deyil. İnsan reviewer mövcud deyilsə self-approval uydurulmur; müstəqil agent review sübutu və mövcud repo merge qaydası açıq göstərilir.

Secret, .env, real qonaq məlumatı və provider credential repoya getmir. İstifadəçi dəyişikliklərini silmək, history force-push və production destructive migration scope-dan kənardır.

## 9. Definition of Done və release

ACCEPTANCE sənədindəki DoD məcburidir. P0/P1 açıq ikən production yoxdur. Provider sandbox və backup restore yoxdursa onların nəticəsi “blocked”dır. Feature flag gate-i aradan qaldırmır, yalnız istifadə olunmayan funksiyanı təhlükəsiz kənarda saxlaya bilər.

Sənəd icrası live deploy icazəsi ilə eyni deyil; cari istifadəçinin konkret scope-u əsasdır. Bu repository tapşırığında tətbiqin kodlanması/yayımlanması deyil, sənədləşməsi edilir.

## 10. Yekun hesabat

Nə dəyişdi; hansı commit/PR-dədir; hansı test həqiqətən keçdi; hansı iş qaldı; hansı risk/bloklayıcı var. Tamamlanmamış məhsula “production-ready” yazma. STATUS, milestone gate və external dependencies faktiki vəziyyətlə eyni olmalıdır.
