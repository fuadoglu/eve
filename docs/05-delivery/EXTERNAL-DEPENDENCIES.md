# Xarici asılılıqlar və production qapıları

Bunlar yeni funksiya istəyi deyil; real sistemi işə salmaq üçün tələb olunan məlumat və təsdiqlərdir. Secret qiymətləri bu sənəddə yazılmır.

| ID | Ehtiyac | Məsul | Hazırkı vəziyyət / təsir |
|---|---|---|---|
| EXT01 | Production domeni və DNS | Məhsul sahibi | Verilməyib; sabit QR/domain, SMTP və callback üçün lazımdır |
| EXT02 | Supabase staging/production hesabı və region | Sahib + texniki komanda | Qoşulmayıb; local schema işi davam edə bilər |
| EXT03 | SMTP sender/domain və provider | Sahib + texniki komanda | Təsdiqlənməyib; real login email gate |
| EXT04 | Payriff merchant, sandbox, production aktivliyi | Sahib + inteqrasiya | Təmin edilməyib; real checkout gate |
| EXT05 | Payriff API version/status/webhook doğrulama və recurring/illik dəstək | İnteqrasiya + provider | Təsdiqlənməyib; format uydurulmur |
| EXT06 | Vercel Pro və env separation | Sahib + texniki komanda | Qoşulmayıb; canlı deploy gate |
| EXT07 | Xidmət şərtləri, məxfilik, saxlama/silinmə, refund və qəbz/vergi qaydaları | Sahib + hüquqi/maliyyə mütəxəssisi | Hüquqi təsdiq yoxdur; sənədlər rəy deyil |
| EXT08 | Dəstək emaili və xidmət vaxtı | Sahib | Verilməyib; UI dummy şəxsi nömrə qoymur |
| EXT09 | 5 real UX test iştirakçısı | Məhsul/UX | Təyin edilməyib; prototype usability gate |
| EXT10 | GitHub native milestones, branch protection/ruleset və required checks | Repo admin | M0–M7 native milestones yaradılıb; `main` üçün branch protection, PR tələbi, `docs` required check və admin enforcement aktivdir. Ruleset ayrıca qurulmayıb. GitHub approval sayı 0-dır; müstəqil agent review PR-də qeyd olunur. Secret scanning və push protection aktivdir. |

## Seçilmiş ilkin konfiqurasiya

Monthly/yearly qiymətlər, 7 günlük trial, AZ panel, AZ/RU/EN content, media kvotası və link müddətləri DECISIONS-dədir. Bunlar hər dəfə istifadəçidən yenidən soruşulmur; dəyişiklik ehtiyacı ölçü və səbəblə əsaslandırılır.

Provider credential olmadan schema, UI, local integration və fake provider contract test edilə bilər. Lakin SMTP delivery, Payriff sandbox və production çıxışı tamamlanmış sayılmır.

## Secret handling

Açarlar .env və ya hosting secret store-a təhlükəsiz daxil edilir. Repo issue, PR, screenshot, log və agent mesajına raw key göndərilmir. Leak olarsa əvvəl revoke/rotate, sonra redacted incident. .env.example yalnız ad/placeholder saxlayır.
