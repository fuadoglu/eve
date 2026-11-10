# İnteqrasiyalar və doğrulama

## Supabase Auth / email

Rəsmi passwordless və session sənədləri REFERENCES-dədir. M1 spike: magic link template, custom SMTP, rate limit, scanner/prefetch, eyni və fərqli cihaz axını, SSR cookie refresh, logout-all. Email input-u trim edilir, email normallaşdırılması provider kimliyini uydurmur. SMTP delivery təsdiqlənmədən “email uğurla çatdı” deyil, “keçid göndərilməsi istənildi” davranışı.

Giriş linki üçün ilkin 15 dəqiqə TTL, resend 60 saniyə; IP+email limit serverdədir və staging load ilə tənzimlənir. Linki təsadüfən consume edən scanner varsa ara confirm page məcburidir. Cross-device token_hash verify axını providerin cari təhlükəsizlik sənədi ilə seçilir; PKCE verifier-in yoxluğu xəta kimi istifadəçiyə aydın göstərilir.

Custom SMTP, SPF/DKIM/DMARC və sender domain production asılılığıdır. Telefon yalnız opsional kontakt/WhatsApp üçündür, login vasitəsi deyil.

## Payriff

Yalnız Eve SaaS. Hosted checkout serverdən yaradılır; kart data tətbiqə daxil olmur. Dəqiq API versiyası, auth header, event key, webhook verification formatı və status enum-u sandbox zamanı provider sənədi ilə yazılır. Bu spec təsdiqlənməmiş signature field uydurmur.

Adapter kontraktı: createOrder(order,returnUrl), getOrderStatus(providerId), normalizeVerifiedEvent(payload), reconcile(order). İnternal billing state provider label-dan ayrıdır. Məbləğ/currency/merchant/order yoxlanmayan cavab paid sayılmır.

Axın: server order+line yaradır → provider checkout URL → istifadəçi checkout → return page pending → webhook inbox və ya reconcile → server status verify → idempotent transaction entitlement → UI status polling dayanır.

Webhook üçün:
- Raw body yalnız verification ehtiyacı qədər saxlanır, PII redacted audit ayrıdır.
- Rəsmi signature varsa constant-time verification; yoxdursa provider status lookup mandatory.
- Duplicate, out-of-order, delayed event və forged success sandbox/contract test edilir.
- Retry safe; entitlement transaction və order_line unique.
- Browser return və user POST “paid” edə bilməz.
- Reconcile pending order-ları schedule ilə yoxlayır; limitsiz polling yoxdur.
- Provider outage zamanı pending göstərilir; ikiqat checkout təşviq edilmir.

Recurring aylıq/illik intervalı və merchant hesabında aktivləşməsi xarici gate-dir. İlkin manual monthly/yearly checkout işlək qalmalıdır. Provider dəstəyi yoxdursa recurring disabled flag altında qalır, abunə müddəti sistemi işləyir. Refund və invoice/tax mətnləri provayder/hüquqi təsdiqlə bağlanır.

## WhatsApp

Dərin keçid və ya platform share istifadə edilir. Nömrə E.164 formatına normallaşdırılır; mətn URL encode edilir. Mesaj: evin paylaşılması təhlükəsiz adı, iş, vaxt, qısa qeyd və scoped keçid. Guest telefon/giriş kodu ehtiyac yoxdursa daxil deyil.

WhatsApp quraşdırılmayıbsa “Mətni və keçidi kopyala” fallback. Kopyalama yalnız clipboard uğur cavabından sonra bildirilir. Automatic outbound Business API scope xaricidir; delivered/read event yoxdur.

## Media və QR

Şəkil client compression + server validation; original EXIF təhlükəsizliyi yoxlanır. Video max 100 MiB/5 dəqiqə, unsupported format üçün aydın xəta; universal transcoding provider olmadan vəd edilmir. Browser-compatible MP4 tövsiyə; arbitrary iframe deyil. Ev kvotası 1024 MiB, upload intent-də reserve/finalize; orphan cleanup job var.

Səsli qeyd max 60 saniyə, mikrofon icazəsi könüllü; format unsupported olduqda foto/mətn fallback. Private audio və inspection foto public bucket-də deyil.

QR generated URL sabitdir, PNG/SVG/PDF export; çap nümunəsi 25 mm və 35 mm ölçülərdə normal telefonla yoxlanır. Domain dəyişməsi köhnə QR-lər üçün redirect planı tələb edir; production domen seçimi buna görə release dependency-dir.

## Bildiriş

Email transactional fallback; Web Push istifadəçi icazəsi və cihaz dəstəyi ilə. Permission ilk ekranda soruşulmur, fayda izahından sonra istifadəçi seçir. Push uğursuzluqda kritik məlumat “Bu gün”də qalır.

Outbox dedupe: recipient+kind+resource+scheduled_time. Quiet hours default 22:00–08:00 Asia/Baku; sabahkı plan səhər xülasəsində. Eyni hadisə təkrar bildiriş yaratmır. Sahib/menecer öz notification seçimlərini idarə edir, hər sahiblə bağlı data paylaşılmır.

## Provider dəyişmə sərhədi

Domain modulları Payriff/Supabase label-larını UI-a daşımır. Adapter müqaviləsi və sandbox fixture-ləri var. Real provider hesabı yoxdur deyə saxta production uğuru göstərmək olmaz; mock yalnız test mühitində açıq işarə ilə işləyir.


Private scoped media direct signed Storage URL deyil, hər fetch-də linkin cari scope/expiry/revoke/cari placement vəziyyətini yoxlayan proxy vasitəsilə verilir. Upload üçün qısaömürlü signed upload URL başqa məqsəddir; read revoke zəmanəti kimi təqdim edilmir.
