# Codex üçün başlanğıc tapşırığı

Aşağıdakı tapşırıq tətbiqin icrasına başlamaq üçündür. Bu sənədin repo-da olması işin avtomatik başladığını bildirmir.

## İcraya verilən göstəriş

Eve layihəsini AGENTS.md və docs/INDEX.md üzrə həyata keçir. Məhsul Azərbaycan bazarında günlük kirayə evlərinin mobil idarəetmə sistemidir. İstifadəçi production keyfiyyətini, maksimum sadə UX-i və multiagent icranı tələb edir.

Əvvəl repo-nu faktiki yoxla, STATUS və xarici asılılıqları oxu. İşlək kod yoxdursa mock UI-nı bitmiş məhsul sayma. M0-dan başla; auth/Payriff feasibility, mobil prototip və OpenAPI-ni tamamla. Sonra ROADMAP/BACKLOG asılılıqları ilə irəlilə.

Repo-da artıq OpenAPI JSON, tam data dictionary, status/config/field-binding müqavilələri və kliklənən sənəd prototipi var. Bunları yenidən sıfırdan yazma: yoxla və həmin müqavilələrə uyğun implement et. Prototip production komponenti deyil. Real istifadəçi testi, provider sandbox və DB migrations hələ ayrıca gate-dir. WORK-PACKAGES 90 bounded vahidin dependency və external gate fərqini göstərir.

İnteqrator agent özündə schema/API/design/lockfile coordination saxlasın. Bounded UX, backend, integration və QA işlərini ayrı worktree/branch agentlərinə ver. Müqavilə hazır olmadan asılı agentləri ziddiyyətli fərziyyələrlə paralel başlatma.

Məhsul invariantları: email-only passwordless; owner tenant+property permission; menecer müxtəlif sahiblərdə; Payriff yalnız Eve abunəsi; integer rent/deposit/realtor ledger; DB occupancy; immutable inventory snapshot; public only available dates; safety QR expiry-də açıq; scoped task link; truthful server ack.

Hər task R/AT/EVE ID-ləri ilə GitHub issue/PR-də izlənilsin. Hər agent acceptance və actual test sübutu ilə təhvil versin. Müstəqil red-team review olmadan auth/finance/billing/access merge edilməsin. P0/P1 release-i bloklayır.

Xarici credential yoxdursa qalan işi davam etdir, amma provider sandbox testini mock ilə keçilmiş sayma. Secret soruşulanda repoya/mesaja yazdırma; təhlükəsiz env konfiqurasiyası istifadə et. Məhsul qiymətlərini və rol sərhədini səssiz dəyişmə.

Nəticədə main-a daxil olmuş tasklar, testlər, qalan bloklayıcılar və release vəziyyəti dürüst təqdim edilsin. Deployment cari istifadəçinin scope-u ilə idarə olunsun; docs task-ı production publish icazəsi kimi qəbul edilməsin.

## İlk agent planının forması

| Agent | İlk bounded iş | Ortaq fayl məhdudiyyəti |
|---|---|---|
| İnteqrator | Repo audit, task/branch ownership, OpenAPI/domain müqaviləsi | Schema/API/lockfile sahibi |
| UX | Mobile clickable prototip və usability planı | Backend müqaviləsi dəyişmir |
| İnteqrasiya | Auth/SMTP/Payriff feasibility və redacted evidence | Secret commit etmir |
| QA/security | Tenant/public/token/payment threat tests | Müəllif işini özü təsdiqləmir |

## İlk hesabat

Mövcud repo vəziyyəti; başladılan tasklar; agent/worktree cədvəli; yoxlanmış provider faktları; prototype/OpenAPI gate; bloklayan xarici ehtiyaclar. Gündəlik feature hesabatı yox, faktiki nəticə və sübut.
