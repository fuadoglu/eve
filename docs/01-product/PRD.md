# Məhsul tələbləri — Eve

## Problem və nəticə

Ev sahibi rezervasiya, beh, təmizlik, usta, inventar və təlimatları ayrı yerlərdə saxlayır. Eve bu məlumatları ev və rezervasiya ətrafında birləşdirir. İstifadəçi “bu gün nə etməliyəm, hansı tarix boşdur, kimə nə qədər borc var?” suallarına birbaşa cavab almalıdır.

## Normativ tələblər

| ID | Tələb | Qəbul sübutu |
|---|---|---|
| R01 | Şifrəsiz email girişi, davamlı sessiya, sonradan profil | AT01–03 |
| R02 | Çox ev və sahib tenant izolyasiyası | AT04–06 |
| R03 | Çoxsahibli menecer və ev üzrə icazələr | AT04–06 |
| R04 | Rezervasiya, hold, blok, giriş/çıxış, paralel toqquşma müdafiəsi | AT07–10 |
| R05 | Kirayə uçotu, depozit, refund, realtor qarşılıqlı hesabı | AT11–13 |
| R06 | Kateqoriyalı xərc, təkrarlanan xatırlatma, təsdiq | AT14 |
| R07 | Tapşırıq keçidi, WhatsApp paylaşımı, qəbul/tamamlama | AT15–16 |
| R08 | Hazırlıq statusu, çıxış təmizliyi, idempotent əlaqə | AT10, AT16 |
| R09 | Daimi inventar, tarixli/təhvil əsaslı yoxlama, ayrı tərəf cavabları | AT17–19 |
| R10 | Çoxdilli QR məzmunu, public/məxfi ayrılığı | AT20–21 |
| R11 | Nömrəsiz public təqdimat və opt-in yalnız boş tarixlər | AT22–24 |
| R12 | Ev başına Payriff abunə və birdəfəlik ilk sınaq | AT25–28 |
| R13 | Mobil sürət, əlçatanlıq, doğru xəta/loading vəziyyətləri | AT29–31 |
| R14 | Audit, export, backup, dəstək və minimal operator paneli | AT32–34 |
| R15 | İlk quraşdırma və təhlükəsiz toplu import | AT35 |
| R16 | Mühüm bildirişlər və dəqiq göndəriş statusları | AT15, AT36 |

## Scope sərhədi

Eve kirayə müqaviləsini təsdiqləmir, kirayə pulunu saxlamır, tərəflər arasında mübahisəyə hökm vermir. Yoxlama hüquqi şəxsiyyət təsdiqi və avtomatik zərər tutulması deyil. SaaS hüquqi mətnləri ayrıca yoxlanılmalıdır.

Bir hesab həm ev sahibi, həm menecerdir. Girişdə rol seçimi yoxdur. İşçiyə hesab açdırılmır. Public səhifədə rezervasiya təsdiqi və payment CTA yoxdur.

İlkin production daxilində: əsas modullar, AZ panel, AZ/RU/EN məzmun sahələri, email transactional bildiriş, opt-in push imkanına uyğun fallback, CSV/XLSX import/export, operator paneli. Kənarda: AI, avtomatik tərcümə, ictimai ev axtarışı, sövdələşmə komissiyası, native iOS/Android, iCal, mürəkkəb ERP, biometrik/e-imza inventar protokolu.

## Keyfiyyət hədəfləri

- Əsas mobil axın 360 px-də üfüqi səhifə sürüşməsi olmadan tamamlanır.
- İlk dəfə istifadə edən 5 nəfərdən ən az 4-ü rezervasiya və təhvil yoxlamasını köməksiz tamamlayır; nəticələr protokollaşdırılır.
- Bir evdə tarix və qiymət hazırdırsa rezervasiya yaratmaq üçün median hədəf 45 saniyə; problemin olmadığı 4 otaqlı inventar yoxlaması 90 saniyə.
- Public səhifə üçün mobil p75 LCP ≤ 2,5 s, INP ≤ 200 ms, CLS ≤ 0,1 hədəfdir; real trafik yoxdursa lab nəticəsi ayrıca işarələnir.
- Adi server oxuması p95 ≤ 500 ms, yazı ≤ 800 ms hədəfi; provider və media transferi ayrıca ölçülür.
- Tenant sızması, üst-üstə təsdiqlənən rezervasiya, ikiqat abunə uzatması sıfır tolerantlıqdır.

## Təhvilin mənası

Spec yazılıb = implementasiya hazır deyil. Mərhələ yalnız qəbul sınaqları, commit, test nəticəsi və review sübutu ilə tamamlanır. UX hədəfləri ölçülməyibsə “ideal UX” iddiası yazılmır.
