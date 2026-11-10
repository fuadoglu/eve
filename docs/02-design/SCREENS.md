# Ekran müqavilələri

Hər ekran loading, empty, error, permission-denied və offline vəziyyətinə malikdir. Bu prototip deyil, implementasiya kontraktıdır.

| ID / Yol | Məzmun | Əsas əməliyyat |
|---|---|---|
| UI01 /login | Email, qısa izah, şərt/məxfilik | Email ilə davam et |
| UI02 /login/check-email | Email, düzəliş, resend sayğacı | Yenidən göndər |
| UI03 /auth/confirm | Tokensiz görünən təsdiq landing-i | Eve-yə daxil ol |
| UI04 /today | Giriş/çıxış, hazırlıq, gecikən iş, pul və abunə | Kartın növbəti əməliyyatı |
| UI05 /calendar | Ev/sahib filtri, agenda, bir ev üçün ay | Tarix seç |
| UI06 /properties | Cover, ad/ərazi/sahib, hazırlıq, abunə | Ev əlavə et |
| UI07 /properties/{id} | Təqvim/pul/inventar/təlimat alt hissələri | Kontekstli + |
| UI08 /reservations/{id} | Tarix, qonaq, qiymət/alınıb/qalıb, depozit/realtor | Giriş etdi / Çıxış etdi |
| UI09 /tasks/{id} | İş, vaxt, icraçı, nəticə, xərc təklifi | WhatsApp-da paylaş / təsdiqlə |
| UI10 /properties/{id}/inventory | Otaq/say/vəziyyət, şablon/import | Əşya əlavə et |
| UI11 /s/{token} inspection | Ev/tarix/tərəf/ad və otaqlar | Yoxlamanı bitir |
| UI12 /s/{token} task | İş, lazım olan ünvan, təlimat/foto | Qəbul etdim / Tamamladım |
| UI13 /properties/{id}/guides | Blok, dil, draft/publish, QR | Önizlə / dərc et |
| UI14 /p/{slug} | Qalereya, imkan, qayda, opt-in tarix/qiymət/xəritə | Tarixləri kopyala |
| UI15 /g/{slug} | Dil, qısa addım, şəkil, toxunaraq video | Dil dəyiş |
| UI16 /settings/managers | Email, evlər, iki icazə səviyyəsi | Dəvət et |
| UI17 /billing | Sahibin evləri, plan/bitmə/renewal | Payriff ilə ödə |
| UI18 /settings | Profil, sessiya, bildiriş, export, kömək | Aid əməliyyat |
| UI19 /operator | Hesab/abunə/failed payment/support/audit | Səbəbli müdaxilə |

## Formlar

### Rezervasiya sheet

Ev kontekstdə göstərilir; tarix, ad, opsional telefon, ümumi qiymət, opsional alınan pul. “Əlavə məlumat”: gecəlik hesab, saat, qonaq sayı, realtor/komissiya, depozit, qeyd. Hold/confirm aydın seçimdir. Aktiv olmayan ikinci evdə abunə axını açılır, mövcud draft itmir.

### Pul sheet

Məbləğ, növ (kirayə/depozit), pulu alan, tarix. Refund original receipt-ə bağlanır. Başqa evdəki köhnə pulu-alan seçimi səssiz daşınmır. Balance serverdən gəlir.

### Xərc sheet

Ev hazır, məbləğ/kateqoriya əsas; qeyd/çek/usta/ödənilib aşağıda. İşçidə “Xərc təqdim et”, təsdiqli xərc iddiası yoxdur.

### Təsdiqlər

Arxiv, manager revoke, link rotation, refund, deposit allocation nəticəni göstərən təsdiq istəyir. Adi qeydə əlavə modal yoxdur. “Geri al” yalnız reversibl işdə. Maliyyə silmək əvəzinə reversal izah edilir.

## Sadə mətnlər

Public: “Tarix seçimi rezervasiya yaratmır. Razılaşmanı keçidi sizə göndərən şəxslə tamamlayın.”
Yoxlama: “Bu qeyd evin vəziyyətini bildirir. Məbləğ avtomatik tutulmur.”
Expired link: “Bu keçid artıq aktiv deyil.”
Offline: “Bağlantı yoxdur. Son dəyişiklik hələ saxlanılmayıb.”

Desktop eyni capability və axını saxlayır. Genişlik əlavə sütun verir, mobil funksiyanı gizlətmir.
