# Public səhifə, təlimatlar və paylaşım

R07, R09–11. Üç müxtəlif məlumat sərhədi var:

| Keçid | Məzmun | Giriş |
|---|---|---|
| /p/{opaque_slug} | Mənzilin təqdimatı və opt-in uyğun tarixlər | Hamıya açıq, noindex |
| /g/{stable_slug} | Dərc edilmiş ümumi və təhlükəsizlik təlimatları | Divara vurulan sabit QR |
| /s/{token} | Konkret qonaq təlimatı, tapşırıq və ya yoxlama | Məhdud səlahiyyətli müddətli keçid |

## Public təqdimat

Foto qalereyası, qısa ad/ərazi, otaq/yataq/qonaq sayı, imkanlar, təsvir, giriş/çıxış qaydası, qiymət və xəritə seçimləri. Sahibin public switch-i ilkin olaraq OFF; tarix/qiymət/xəritə switch-ləri də OFF. Menecer məzmunu dəyişə bilir; public switch və link rotation sahibindir.

Sahib, menecer, realtor və qonağın nömrəsi/emaili göstərilmir. İstifadəçinin yazdığı təsvir, video və şəkil daxilində nömrə ola bilər: dərcdən əvvəl “Əlaqə məlumatı olmayan görünüş” preview və xəbərdarlıq tələb olunur; avtomatik filtr/OCR ilə tam zəmanət verilmir. Fayl adları və EXIF public cavaba daşınmır. Dəqiq ünvan ayrıca explicit seçimdir.

### Uyğun tarixlər

Daxili reservation DTO-su paylaşılmır. Public read model yalnız evin yayımlanmış sahələrini və seçilə bilən gecələri qaytarır. Dolu, blok, hold və təmir səbəbləri, guest ID və occupant məlumatı cavabda yoxdur. Əlçatmaz gecələr bir neytral görünüşdədir.

Availability limit: bu gündən 12 ayadək. Out-of-range tarix cavabda “yoxlanılmır”dır, “boş” deyil. Gecələr və mümkün çıxış sərhədi ayrı qaytarılır: [12,15) intervalında 15 çıxış kimi seçilə bilər, həmin gecə əlçatan olmasa da.

Seçim təsdiq, hold və sifariş yaratmır. Qiymət göstərilirsə server intervalı hesablayır; mövcud olmayan tarif üçün təxmin uydurmur. “Tarixləri kopyala” ev adı/keçid, tarix və gecə sayını verir. Qlobal telefon və booking payment düyməsi yoxdur.

Yeni booking/blok/ləğv public cache-i invalidate edir. Availability cavabı no-store; public statik məzmun cache-i property/published version üzrədir. Saytı açıq saxlayan istifadəçidə refresh/focus və interval seçimi zamanı yenidən yoxlama var. Yenə də real rezervasiya yalnız daxili təsdiqlə yaranır.

### Axtarış və paylaşım

HTML meta robots=noindex,nofollow,noarchive və X-Robots-Tag uyğun verilir; sitemap-a daxil deyil. Robots.txt həmin səhifəni tam bloklayıb noindex-in görünməsini əngəlləməsin. Axtarışdan tam və dərhal yoxolma vədi verilmir. OG yalnız dərc olunmuş ad, cover və qısa təsvir. Məxfi keçidlərdə OG preview şəxsi məlumat göstərmir.

Sahib söndürə/rotate edə bilir. noindex giriş nəzarəti deyil.

## Təlimat redaktoru

Hazır bloklar: mətn, şəkil, video, vacib qeyd. Arbitrary HTML/JS/embed yoxdur; video linkləri allowlist və safe embed qaydasına tabedir. Public safety/general və guest-private təsnifatı məcburidir. Sauna/elektrik/qaz qaydaları avadanlıq istehsalçısına uyğun sahib tərəfindən hazırlanır; Eve universal təhlükəsizlik məsləhəti uydurmur.

AZ/RU/EN məzmun versiyaları, əsas dil + əlavə dil. Dil switch-i yalnız dərc olunmuş dil üçün görünür; telefon dili uyğun deyilsə əsas dil. Panelin dili və məzmunun dilləri ayrı modeldir. Tərcümə insan tərəfindən daxil edilir, avtomatik AI yoxdur.

QR sabit slug-a bağlanır; content versiyası dəyişəndə QR dəyişmir. Ev üzrə ümumi indeks və hər təlimata deep link var. QR PNG/SVG/PDF export-u kontrast, quiet zone və çapdan telefonla skan testi ilə yoxlanır. Tam özbaşına QR dizaynı verilmir.

Wi-Fi şifrəsi, qapı kodu və qonağa aid giriş məlumatı yalnız guest-private scope-dadır. Abunə bitəndə əvvəl dərc olunmuş safety mətn və şəkillər yeni redaktəsiz oxunur. Video arxiv siyasəti safety mətnini əvəz etmir. “Əbədi pulsuz hostinq” vədi verilmir; hesab silinməsi/service closure zamanı məlumat və keçidlərin taleyi hüquqi retention qaydasında açıqlanmalıdır.

## Müddətli keçidlər

Token ən az 256 bit random, DB-də hash; raw token log/audit/analytics-ə düşmür. Token task, event-side və ya guest guide scope-una bağlıdır. Token GET-i vəziyyət dəyişmir. Yazılar scoped endpoint-dən idempotent POST olur. Expiry/revoke media erişimini də dayandırır; private media üçün hər sorğuda scope/expiry/revoke yoxlayan proxy URL istifadə olunur; əvvəl endirilmiş baytlar geri alınmır.

Task/inventory write window due_at +48 saat; gələcək işlərdə token müddəti max 30 gün, lazım olsa yenilənir. Tamamlanmış yoxlama write-locked olur. Guest guide plan checkout+24 saat; checkout uzadıldıqda səlahiyyətli server update edir. Bir linkin başqa şəxsə ötürülməsi mümkündür: bu bearer access-dir, hüquqi şəxsiyyət sübutu deyil.

WhatsApp-da task linki preview oluna bilər, buna görə qəbul/completion GET-dən heç vaxt dəyişmir. “Paylaş” actual delivered/read telemetriyası kimi qeyd edilmir.

Guest-private oxuma predicate-i reservation cancelled/no_show olmamasını və link placement-in cari placement olmasını tələb edir. Move/cancel/no_show köhnə linkləri atomik revoke edir. Çıxışdan sonrakı 24 saat yalnız qanuni completed qonaq keçidinə aiddir.
