# Sənədləşmə keyfiyyəti və müstəqil audit

## Məqsəd və qiymətləndirmə

Bu iterasiya “10/10” ifadəsini reklam balı kimi deyil, icraçının yoxlaya biləcəyi on təhvil meyarı kimi tətbiq edir. Sənəd müqaviləsinin tamlığı işləyən proqramın təhlükəsizliyini, real cihaz rahatlığını və ya provider inteqrasiyasını avtomatik sübut etmir.

| Meyar | Təhvil artefaktı |
|---|---|
| DQ01 — Vahid scope və qərar | PRD, DECISIONS, CONFIGURATION; tələb/texniki seçim/xarici gate ayrıdır |
| DQ02 — Sadə və konkret mobil UX | UI01–19, FLOW-SPEC, self-contained clickable prototip, vəziyyətlər və fallback |
| DQ03 — Tam API forması | OpenAPI 3.1; operationId, request/response, auth/capability/entitlement, xəta və schema nümunələri |
| DQ04 — Tam data lüğəti | Hər sütun üçün tip/null/default/validation; PK/FK/unique/index/RLS/retention |
| DQ05 — API/data uyğunluğu | Field bindings, canonical enum/limitlər və cross-contract validator |
| DQ06 — Davranış deterministikdir | State machines; şərt, action, atomik yan təsir, idempotency və rədd cavabı |
| DQ07 — İş ölçülə biləndir | 30 parent issue daxilində 90 bounded paket, dependency və external gate |
| DQ08 — Tələbdən sübuta əlaqə | 16 tələb üzrə ekran/API/data/task/36 acceptance matrisi |
| DQ09 — Müstəqil review | Security və delivery reviewer-ləri; tapıntı və düzəliş reyestri |
| DQ10 — Dürüst və təkrar yoxlanan təhvil | Script/CI, evidence, real işləyən və planlaşdırılan yoxlamanın ayrılığı |

## İkinci iterasiyada tapılan və düzəldilən məsələlər

| ID | Risk | Düzəliş və regression sərhədi |
|---|---|---|
| DA01 | API/DB/UI name/area və qeyd limitləri fərqlidir | Canonical limit + field mapping; validator fərqi rədd edir |
| DA02 | Readiness üç ayrı enum idi | ready / cleaning_pending / attention_required hər üç müqavilədə |
| DA03 | Tərəf, otaq nəticəsi, permanent inventar və task enum-ları fərqlidir | Giver/receiver; room problems; daimi inventarda needs_repair, unable yalnız yoxlamada |
| DA04 | Media public/private təsnifatı xəritələnməyib | Property/guide/private target kateqoriyaları açıqdır; RLS sərhədi saxlanır |
| DA05 | property_type data-da saxlanmır | Enum və sütun əlavə edilir, API binding yoxlanır |
| DA06 | Erkən çıxışdan sonra qalan günləri açmaq legal transition deyil | completed → same release_remaining_days; tarix/quote açıq təsdiq, stay yenidən açılmır |
| DA07 | Ləğvdə pul qərarı ziddiyyətlidir | Pul varsa explicit qərar; keep_as_is da şüurlu təsdiqdir, omission ilə səssiz qərar deyil |
| DA08 | Provider credential bütün scaffold/UI işini saxlayır | Hard dependency ilə external acceptance gate ayrıldı, DAG yenidən yoxlandı |
| DA09 | Daily manager reversal hüququ qeyri-müəyyəndir | Reversal/deposit allocation owner/full finance.manage, negative test |
| DA10 | Ev dəyişəndə köhnə guest-private keçidi qalır | Move/cancel/no_show atomik revoke; current placement read predicate |
| DA11 | Dərhal media revoke və direct signed URL ziddiyyəti | Private media proxy hər fetch-də yoxlayır; əvvəldən endirilən baytları geri almaq vədi yoxdur |
| DA12 | Yalnız prose invariantı local conditional payloadı rədd etmir | Commission/original receipt/free stay/hold conditional schema və mənfi nümunələr |
| DA13 | Row RLS sütun grant sərhədini tam göstərmir | app_private base schema, api allowlist RPC; birbaşa user/anon base grant yoxdur |
| DA14 | Source və target move entitlement qaydası fərqlidir | Hər iki ev aktiv, eyni sahib və hər ikisində cari capability |
| DA15 | `.1/.2` paketləri parent-in sandbox acceptance-sini blok kimi miras alır | Komponent kontraktı ayrıca; real provider/istifadəçi `.3` external gate-də |

Müstəqil reviewer-lər: final_security_audit və final_delivery_audit. Bunlar sənəd və müqavilə baxışlarıdır; tətbiq pentest-i deyil. İlkin tapıntıların root-owned hissələri ayrıca təkrar yoxlanılıb. Final API/data uyğunluq sübutu aşağıdakı evidence və validator nəticəsi ilə birlikdə oxunur.

## Yoxlama sübutu və sərhədlər

Faktiki çıxışlar və yoxlanmış source hash-ləri [evidence/contracts.json](evidence/contracts.json)-dadır. Yerli Node/Python müqavilə yoxlamaları real icra edilir. Prototip testi VM/fake-DOM smoke-dur; layout və real usability deyil.

Brauzer QA üçün workspace localhost-u cloud brauzerdən açmaq cəhdi connection refused ilə nəticələndi. Buna görə brauzer screenshot/layout və real iPhone/Android nəticəsi bu təhvildə PASS kimi təqdim edilmir. Prototip local server ilə açılıb həmin testlər sonrakı icra gate-ində aparılır.

Payriff/SMTP sandbox, executable DB/RLS, backup restore, hüquqi retention və real istifadəçi testi ayrıca açıq qapılardır. Bunların adının sənəddə olması faktiki tamamlanma deyil. Cari vəziyyət [STATUS](../05-delivery/STATUS.md)-da saxlanılır.


## Yekun təkrar baxış — 2026-11-11

Müstəqil resume_contract_review root müqavilələrində əvvəlki P1 ziddiyyətlərinin bağlandığını təsdiqlədi. Əlavə schema şərtləri (unable səbəbi, missing faktiki say, realtor kontaktı, boş refund massivinin rəddi) müsbət/mənfi nümunələrə daxil edildi. Bu nəticə tətbiqin pentest və ya production təsdiqi deyil.
