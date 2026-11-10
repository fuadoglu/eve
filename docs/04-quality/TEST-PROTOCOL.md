# Qəbul sınağının icra protokolu

Ssenari mənbəyi [ACCEPTANCE](ACCEPTANCE.md), ətraflı Given/When/Then dataset-i [acceptance-scenarios.json](acceptance-scenarios.json)-dır. Dataset tətbiq testinin keçdiyi anlamına gəlmir.

## Sabit fixture

- Sahib A: A1/A2; sahib B: B1/B2.
- Menecer M: A1 daily, B1 full; A2/B2 icazəsiz.
- Başqa ssenaridə A özü B2-də menecer olur; owner və manager kimliyi bir user-də işləyir.
- A1 trial/active, A2 draft/expired variantları; bir booking 12–15 noyabr, başqa 15–17 noyabr.
- Hər run təcrid olunmuş data yaradır. Fixture real qonaq/email/telefon daşımır.

## Hər nəticə faylı

Ssenari ID, commit SHA, mühit, test qatının adı, seed, Given/When/Then, faktiki nəticə, exit code, log/ekran sübutu, reviewer, tarix və məhdudiyyət. Nəticələr docs/04-quality/evidence altında saxlanır; production secret və PII redaktə edilir.

## Mənfi sınaq nümunəsi

AT05: M sessiyası ilə A1 rezervasiyası oxunur. A sahibi A1 membership-i ləğv edir. M-nin eyni köhnə tabından növbəti read/write rədd edilir; B1 işləyir. API üçün birbaşa sorğu, storage üçün private fayl sorğusu ayrıca yoxlanır. UI-da kartın yox olması tək sübut deyil.

## Provider sübutu

Mock test adapter davranışını, sandbox provider uyğunluğunu yoxlayır. Eyni nəticə kimi təqdim olunmur. Payriff amount/order/currency/merchant, duplicate və reconcile real sandbox qaydası ilə sübut olunmalıdır. Provider imza formatı məlum deyilsə sintetik düzgün imza hazırlayıb inteqrasiyanı tamamlanmış saymaq olmaz.

## Mobil istifadə sınağı

İştirakçıya məqsəd deyilir, düymələrin yeri izah edilmir. Hər biri giriş, rezervasiya/beh, task paylaşma və evi yoxlama axınından roluna aid olanı icra edir. Vaxt, kömək sayı və səhv qeyd olunur. Prototype scripted smoke real istifadəçi testinin əvəzi deyil.

## Release qərarı

P0/P1=0; required acceptance-lər sübutludur; skip səbəbi açıqdır; backup+media restore və rollback yoxlanıb; xarici hüquqi/provider gate-lər bağlanıb. Documentation validator yalnız müqavilə bütövlüyünü sübut edir, bu release şərtlərini əvəz etmir.
