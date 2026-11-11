# Qərar və traceability bağlanması — EVE-001.3

Tarix: 2026-11-11. Giriş: EVE-001.2 main commit `62ced29`, [tələb auditi](REQUIREMENT-AUDIT.md) və [D31](../01-product/DECISIONS.md). Bu nəticə sənəd müqaviləsinin yoxlanmasıdır; tətbiq və provider qəbul sınağı deyil.

## Bağlanmış əlaqələr

- R05 üçün PRD və trace AT11–13, R06 üçün AT14 göstərir. AT13 realtor settlement, AT14 expense approval/allocation ssenarisidir. Hər iki sınaq və M7 AT01–36 öhdəliyi saxlanılır.
- PRD qəbul siyahısı 16 tələbin hər birində machine trace-in alt çoxluğudur. Trace-də R09/AT12, R10/AT28 və R11/AT08 əlavə əlaqələri həmin ssenarilərin `requirements` sahəsində təsdiqlənmiş cross-coverage-dir.
- [traceability.json](traceability.json) və [TRACEABILITY.md](TRACEABILITY.md) generator ilə eyni girişlərdən yenidən yaradıldıqda diff vermədi. UI/task əlaqələri insan review tələb edir; generator yalnız biznes mənasının doğruluğunu sübut etmir.

## Müsbət və mənfi yoxlama

`node scripts/generate-traceability.mjs` 16 tələb üçün dəyişikliksiz nəticə yaratdı. PRD AT siyahılarını genişləndirib machine trace ilə müqayisə edən lokal yoxlama 16/16 uyğunluq və yuxarıdakı üç əlavə cross-coverage əlaqəsini göstərdi.

Mənfi sınaqda müvəqqəti kopyada R01 trace-ə mövcud olmayan operation ID əlavə edildi. `node scripts/verify-contracts.mjs` `R01: operation trace stale` xətası ilə exit 1 qaytardı. Mənbə faylları dəyişdirilmədi. Docs/contracts/schema/prototype yoxlamalarının faktiki commit və CI nəticəsi PR-də verilir.

Reviewer acceptance əlaqələri üçün ayrıca boşluq tapdı: validator yalnız AT ID-nin mövcudluğunu yoxlayırdı. Validator indi hər R üçün trace siyahısını `acceptance-scenarios.json` requirements sahəsindən çıxarılan siyahı ilə müqayisə edir. Müvəqqəti kopyada R01-dən AT01 çıxarılanda `R01: acceptance trace stale` xətası ilə exit 1 alındı; normal müqavilə keçdi.

Validator PRD qəbul siyahısının sintaksisini, qəbul ID-lərinin trace-də mövcudluğunu və hər tələb üçün tək Markdown sətrinin machine trace-ə uyğunluğunu da yoxlayır. Ayrı müvəqqəti kopyalarda R01-ə uyğun olmayan AT04 əlavə edildikdə, `AT01–bogus` aralığı yazıldıqda, R01 Markdown sətri dəyişdirildikdə, alternativ formatlarda və 0–3 boşluq indent ilə ikinci R01 sətri, həmçinin naməlum R17/R001 sətri əlavə edildikdə müvafiq xətalarla exit 1 alındı. Bu yoxlamalar biznes mənası üzrə insan review-ni əvəz etmir.

Müstəqil inteqrasiya baxışı PRD parserində üçrəqəmli naməlum `R001` sətrinin səssiz keçdiyini tapdı. Parser bütün rəqəmli R cədvəl sətirlərini yoxlayacaq şəkildə düzəldildi: müvəqqəti kopyada `| R001 | Naməlum tələb | AT01 |` əlavə edildikdə `R001: unknown PRD requirement` ilə exit 1, normal müqavilədə exit 0 alındı. Reviewer R01–R16, D31, AT11–14, cross-coverage və əsas domain sənədlərində əlavə konkret ziddiyyət tapmadı; bu rəy tətbiq, provider və bütün biznes mənasının tam auditini təsdiqləmir.

## Qalan sübut

Bu sənəd real auth, tenant/RLS, pul, provider, cihaz və ya usability yoxlamalarını keçmiş saymır. EVE-001 parent issue yalnız digər qəbul və müstəqil review şərtləri, merge və main smoke tamamlandıqdan sonra bağlanır. Provider və production qapıları [xarici asılılıqlar reyestrində](../05-delivery/EXTERNAL-DEPENDENCIES.md) qalır.

Reyestrdə EXT01–09 xarici təminatçı, hüquqi, istifadəçi və istismar sübutu kimi açıq qalır. EXT10 üçün native milestones və `main` branch protection faktiki aktivdir; ayrıca ruleset və məcburi GitHub insan approval-u qurulmayıb. Agent review və GitHub check ayrı sübutlardır.
