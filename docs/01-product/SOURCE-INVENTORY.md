# Mənbə və tələb inventarı

Tarix: 2026-11-11. Əhatə: EVE-001.1. Bu inventar mənbələrin rolunu və R01–R16 tələblərinin əsas məhsul sənədləri ilə əlaqəsini göstərir. O, ziddiyyət auditini və ya implementasiya sübutunu əvəz etmir; həmin yoxlamalar EVE-001.2/.3 və aid qəbul sınaqlarındadır.

## Mənbə səlahiyyəti və sərhəd

| Mənbə | Əhatə | İstifadə qaydası |
|---|---|---|
| [Codex müqaviləsi](../../AGENTS.md) | Repository workflow, fayl ownership, review, təhlükəsizlik və Done | İcra prosesi üçün normativdir; məhsul davranışı PRD və aid modul sənədlərindən götürülür. |
| [Sənədlər indeksi](../INDEX.md) | Sənəd xəritəsi və ziddiyyət prioriteti | Cari istifadəçi göstərişi → qərar reyestri → modul sənədi. |
| [Qərar reyestri](DECISIONS.md) | Təsbit olunmuş qərar, icra seçimi, xarici təsdiq | Status sütunu qərarın növünü göstərir; xarici təsdiq tələb edən qərar təsdiqlənmiş kimi təqdim edilmir. |
| [Məhsul tələbləri](PRD.md) | R01–R16 canonical tələb başlıqları və qəbul ID-ləri | Tələb ID-si və qısa normativ mətnin mənbəyidir. |
| Modul spesifikasiyaları | [Əməliyyatlar](OPERATIONS.md), [Pul və abunə](BILLING-FINANCE.md), [Paylaşım](SHARING-GUIDES.md), [Mobil UX](../02-design/MOBILE-UX.md), [axınlar](../02-design/FLOW-SPEC.md) | Tələbin istifadəçi davranışını öz modul sərhədində dəqiqləşdirir. |
| Texniki müqavilələr | [API](../03-engineering/API-CONTRACT.md), [data](../03-engineering/DATA-MODEL.md), [giriş](../03-engineering/ACCESS-BOUNDARY.md), [təhlükəsizlik](../03-engineering/SECURITY.md), [state](STATE-MACHINES.md) | Məhsul tələblərini texniki sərhəd, icazə, məlumat və keçid qaydasına çevirir. Maşın müqavilələri ayrıca JSON fayllarıdır. |
| Test və izləmə | [Traceability](../04-quality/TRACEABILITY.md), [Acceptance](../04-quality/ACCEPTANCE.md), [sınaq protokolu](../04-quality/TEST-PROTOCOL.md), [traceability.json](../04-quality/traceability.json) | R → UI/API/data/task/AT əlaqəsi və qəbul sübutu. JSON trace machine source-dur; insan tərəfindən review biznes mənası üçün də lazımdır. |
| [Rəsmi texniki istinadlar](../REFERENCES.md) | Framework, auth, database, provider, accessibility və hosting üçün public docs | Texniki məlumatın ilkin mənbələri; bu URL-lər Eve inteqrasiyasının faktiki işlədiyinə sübut deyil. Provider/sandbox gate ayrıca qalır. |

İndeksdəki yerli normativ mənbələr repository daxilindəki fayllardır. `docs/REFERENCES.md` xarici vendor sənədlərini texniki məlumat mənbəyi kimi göstərir; qiymət/feature zəmanəti və ya production inteqrasiya sübutu kimi qəbul edilmir. Tələb, field, enum və ya test mənası ziddiyyət təşkil edərsə, səssiz fərziyyə edilmir: qərar, modul/machine kontraktı, trace və test EVE-001.2/.3 çərçivəsində birlikdə düzəldilir.

## R01–R16 tələb mənbələrinin xəritəsi

Rəsmi ID və AT mapping [PRD](PRD.md)-dədir; ekran/API/data/task üzrə geniş əlaqələr [traceability cədvəli](../04-quality/TRACEABILITY.md) və [machine trace](../04-quality/traceability.json)-də saxlanılır.

| ID | Tələb | Əsas davranış mənbəyi | Qəbul |
|---|---|---|---|
| R01 | Şifrəsiz email girişi və davamlı sessiya | [İnteqrasiyalar](../03-engineering/INTEGRATIONS.md), [giriş sərhədi](../03-engineering/ACCESS-BOUNDARY.md) | AT01–03 |
| R02 | Çox ev və sahib tenant izolyasiyası | [Əməliyyatlar](OPERATIONS.md), [giriş sərhədi](../03-engineering/ACCESS-BOUNDARY.md) | AT04–06 |
| R03 | Çoxsahibli menecer və ev üzrə icazələr | [Əməliyyatlar](OPERATIONS.md), [giriş sərhədi](../03-engineering/ACCESS-BOUNDARY.md) | AT04–06 |
| R04 | Rezervasiya, hold, blok, giriş/çıxış və toqquşma müdafiəsi | [Əməliyyatlar](OPERATIONS.md), [state maşınları](STATE-MACHINES.md), [data modeli](../03-engineering/DATA-MODEL.md) | AT07–10 |
| R05 | Kirayə uçotu, depozit, refund və realtor hesabı | [Pul və abunə](BILLING-FINANCE.md), [əməliyyatlar](OPERATIONS.md) | AT11–14 |
| R06 | Xərc, təkrarlanan xatırlatma və təsdiq | [Pul və abunə](BILLING-FINANCE.md), [əməliyyatlar](OPERATIONS.md) | AT13–14 |
| R07 | Tapşırıq keçidi və WhatsApp paylaşımı | [Əməliyyatlar](OPERATIONS.md), [paylaşım](SHARING-GUIDES.md), [state maşınları](STATE-MACHINES.md) | AT15–16 |
| R08 | Hazırlıq statusu və təmizlik | [Əməliyyatlar](OPERATIONS.md), [state maşınları](STATE-MACHINES.md) | AT10, AT16 |
| R09 | Daimi inventar və tarixli/təhvil yoxlaması | [Əməliyyatlar](OPERATIONS.md), [data modeli](../03-engineering/DATA-MODEL.md) | AT12, AT17–19 |
| R10 | Çoxdilli QR təlimatı və public/məxfi ayrılığı | [Paylaşım](SHARING-GUIDES.md), [təhlükəsizlik](../03-engineering/SECURITY.md) | AT20–21 |
| R11 | Nömrəsiz public təqdimat və boş tarixlər | [Paylaşım](SHARING-GUIDES.md), [təhlükəsizlik](../03-engineering/SECURITY.md) | AT08, AT22–24 |
| R12 | Ev başına Payriff abunəsi | [Pul və abunə](BILLING-FINANCE.md), [qərarlar](DECISIONS.md), [state maşınları](STATE-MACHINES.md) | AT25–28 |
| R13 | Mobil sürət, əlçatanlıq və vəziyyətlər | [Mobil UX](../02-design/MOBILE-UX.md), [ekranlar](../02-design/SCREENS.md), [axınlar](../02-design/FLOW-SPEC.md) | AT29–31 |
| R14 | Audit, export, backup və dəstək | [Təhlükəsizlik](../03-engineering/SECURITY.md), [istismar runbook-u](../05-delivery/RUNBOOK.md) | AT32–34 |
| R15 | İlk quraşdırma və təhlükəsiz import | [Əməliyyatlar](OPERATIONS.md), [axınlar](../02-design/FLOW-SPEC.md) | AT35 |
| R16 | Bildirişlər və göndəriş statusu | [Əməliyyatlar](OPERATIONS.md), [state maşınları](STATE-MACHINES.md), [inteqrasiyalar](../03-engineering/INTEGRATIONS.md) | AT15, AT36 |

## EVE-001.2 üçün tutuşdurma qeydləri

PRD-dəki qəbul siyahısı ilə machine trace-dəki əlavə və çatışmayan AT əlaqələri inventar zamanı göründü. Bu, hələ ziddiyyət hökmü deyil: eyni test bir neçə tələbi dəstəkləyə bilər. EVE-001.2 hər fərqin məqsədli cross-coverage, yoxsa köhnəlmiş xəritə olduğunu müəyyən etməlidir. Bu paket heç bir ID-ni səssiz dəyişmir.

| Tələb | PRD | traceability.json / TRACEABILITY.md | EVE-001.2-də veriləcək qərar |
|---|---|---|---|
| R05 | AT11–14 | AT11–13 | AT14 R05 üçün qəbul meyarıdır, yoxsa yalnız xərc xəritəsində qalmalıdır? |
| R06 | AT13–14 | AT14 | AT13 realtor hesabı R06 xərc tələbinə məqsədli cross-coverage-dirmi? |
| R09 | AT17–19 | AT12, AT17–19 | AT12 inventory acceptance-inə aiddir, yoxsa yalnız cross-coverage-dir? |
| R10 | AT20–21 | AT20–21, AT28 | AT28 QR expiry davranışını R10 üçün də dəstəkləyirmi? |
| R11 | AT22–24 | AT08, AT22–24 | AT08 departure davranışını R11 üçün də dəstəkləyirmi? |

PRD, traceability Markdown və machine JSON-dakı acceptance əlaqələrinin uyğunluğunu EVE-001.2 təsdiqləməlidir. JSON checker-in PASS nəticəsi yalnız strukturu və istinadları yoxlayır, biznes mənasını yox.

## Xarici mənbələrin əhatəsi

Provider, framework və platforma mənbələrinin canonical siyahısı [REFERENCES](../REFERENCES.md)-dədir. Orada Supabase passwordless/session/RLS/Storage, Payriff checkout/recurring, Next.js App Router/PWA, PostgreSQL range constraint, Google noindex, Vercel planı və WCAG 2.2 istifadə məqsədi ilə verilib. `Yoxlama tarixi` linkin mənbə kimi qeydə alındığı vaxtdır, Eve layihəsinin sandbox yoxlamasının tarixi deyil. Provider-in faktiki schema, webhook, çatdırılma və hesab konfiqurasiyası EVE-003.3 və aid release gate-də sübut olunmalıdır.
