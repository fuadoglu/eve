# Abunə və pul uçotu

R05–06, R12. İki ayrı maliyyə domeni: **Eve xidmət haqqı** və **kirayə uçotu**. Cədvəllər, API və hesabatlar ayrıdır.

## SaaS abunə

Qiymətlər server kataloqundan: monthly=999 qəpik, yearly=9999 qəpik, AZN. Client məbləği müəyyən etmir. Bir payment bir neçə evin order line-ını ödəyə bilər; bütün line-lar eyni order currency və owner-a aiddir. İlk implementasiyada bir ev checkout-u, toplu checkout isə həmin təsdiqli model üzərində ayrıca task-dır.

Hər ev: draft / trialing / active / expired / archived. Arxiv istifadə vəziyyətidir, entitlement tarixini dəyişmir. İlk evi yaradan sahibin trial_claim qeydi unique(owner_id) ilə birdəfəlikdir. İlk evin silinməsi, ikinci tab, paralel request yeni sınaq vermir. Yeni email ilə sui-istifadəni tam aradan qaldırdığı iddia edilmir; rate limit və şübhəli istifadə monitorinqi tətbiq olunur.

### Vaxt hesabı

Sınaq server timestamp-dən 7×24 saatdır. Ödənişli dövr aylıqda bir calendar month, illikdə bir calendar year; ay sonu mövcud son günə clamp edilir. İstifadə olunan anchor saxlanılır ki, 31 yanvar → 28 fevral → 31 mart qaydası itirilməsin. Vaxt UTC, UI Asia/Baku. Dövr [starts_at, ends_at).

Başlama = max(cari ödənilmiş bitmə, təsdiqli ödəniş vaxtı). Sınaq zamanı ilk alış sınağın bitmə vaxtından başlayır, qalan sınaq itmir. Uğursuz ödəniş müddəti dəyişmir. Payment entitlement atomik bir dəfə tətbiq olunur.

Aylıqdan illiyə və əksinə keçid alınan müddəti növbəyə əlavə edir; pro-rata və avtomatik credit yoxdur. UI ödənişdən əvvəl hansı evin nə vaxtadək aktiv olacağını göstərir. Müddət uzandıqda qonaq rezervasiyasının tarixləri dəyişmir.

### Checkout vəziyyətləri

created → pending → verified_paid → entitlement_applied. failed/cancelled/expired order ödənişsiz bağlanır. Gecikmiş provider paid cavabı ayrıca reconcile olunur; əvvəl applied hadisə geri alınmır. Provider transaction ID və tətbiq edilmiş order line unikal olur.

Success URL yalnız “Ödəniş yoxlanılır” göstərir. Aktivləşmə serverdə merchant, order, amount, currency və paid status uyğunlaşdırmasından sonra olur. Webhook API-si təsdiqlənməyibsə imza formatı uydurulmur; rəsmi provider status sorğusu ilə təsdiq tələb olunur.

Refund/chargeback ayrıca state-dir. İlkin buraxılışda manual operator review: faktiki qaytarılan line, təsirlənən period və istifadə edilmiş xidmət yoxlanır; əvvəlki başqa ödənişlərin müddəti silinmir. Qismən refund və istehlak olunmuş müddətin qaytarılması siyasəti hüquqi/provider təsdiqi olmadan avtomatlaşdırılmır.

### Müddət bitdikdə

Sahib: read-only, export və yeniləmə. Menecer: əvvəlki icazə sərhədində read-only. Public təqdimat dayandırılır. Yeni task/reservation/content edit yoxdur. Artıq verilmiş tapşırıq/yoxlama keçidləri öz write window-u bitənədək tamamlanır; məlumat daxilində yeni ev əməliyyatı yarada bilməz.

Mövcud məxfi qonaq keçidi plan çıxış +24 saatadək oxunur; sahib dərhal revoke edə bilər. Təhlükəsizlik QR məzmunu read-only açıq qalır, private guest content onunla qarışmır. Evin yeni public paylaşımını aktivləşdirmək üçün abunə lazımdır.

İlkin etibarlı model manual renewal-dır. Avtomatik recurring yalnız explicit opt-in, ləğv axını və provider sandbox sübutundan sonra ayrıca açılır. Kart PAN/CVV saxlanılmır.

## Kirayə uçotu

Pul vahidi AZN, bütün hesab integer qəpik. Gəlir və pul axını ayrı ölçülür:

- **Rezervasiya dəyəri** = razılaşdırılmış cari kirayə məbləği.
- **Alınıb** = icarəyə aid receipt cəmi − rent refund cəmi; realtorun topladığı rent də daxil.
- **Qalıb** = max(0, rezervasiya dəyəri − alınıb).
- **Artıq ödəniş** = max(0, alınıb − rezervasiya dəyəri); gizlədilmir.
- **Saxlanılan depozit** = deposit receipt − deposit return − əsaslandırılmış deposit allocation.
- Depozit gəlir deyil. Allocation sahib/tam menecer təsdiqi ilə zərər və ya razılaşdırılmış borca yönəldilir; avtomatik tutulmur.

Reversal orijinal qeydə bağlanır, məbləğ mənfi entry hiyləsi ilə yox, type ilə verilir. Refund aid receipt net məbləğini aşmır. Hər hadisədə daxil edən actor, pulun kimdə olduğu və zaman saxlanılır.

### Realtor hesabı nümunəsi

Kirayə 300 AZN, komissiya 30 AZN. Realtor müştəridən 100 AZN alıb. Müştərinin borcu 200 AZN-dir. Realtor komissiyanı bu məbləğdən saxlayırsa sahibə 70 AZN verməlidir. 100 AZN-in hamısını sahibə veribsə sahib realtora 30 AZN ödəməlidir.

Realtor settlement-ləri müştəri ödənişi kimi ikinci dəfə gəlir yaratmır. Hər realtor üzrə collected, transferred, earned commission, paid commission və offset ayrıdır. UI net istiqaməti göstərir; “sahibə çatmalıdır” və “realtora ödənməlidir” eyni vaxtda ikiqat hesablanmır.

Faiz komissiyası depozit və refund-dan deyil, razılaşdırılan rent basis-dən hesablanır; qəpiyə half-up yuvarlaqlaşdırılır. Ləğv komissiyanı avtomatik saxlamır, səlahiyyətli şəxs təsdiqləyir.

## Xərclər

Kateqoriyalar: kommunal, bina/xidmət, təmizlik, usta/təmir, alış, sərf materialı, digər. status=proposed/approved/rejected; payment_status=unpaid/paid/partial. Kateqoriya ilə payment status qarışmır.

Aylıq sabit xərc draft/xatırlatma yaradır; faktiki ödənişi təsdiqsiz gəlmiş saymır. Dəyişən kommunal üçün amount əvvəlcədən uydurulmur. Bir neçə evə xərc bölünürsə allocation cəmi xərc məbləğinə bərabər olmalıdır; rounding qalığı deterministik son paya düşür. Menecer yalnız tam səlahiyyəti olan evlərdə allocation təsdiqləyə bilər.

Hesabatda “alınan pul”, “rezervasiya gəliri” və “xərclərdən sonra nəticə” ayrı adlandırılır. Gündəlik menecer tenant üzrə mənfəət/export görmür. Müxtəlif sahiblərin maliyyə yekunları eyni mənfəət kimi birləşdirilmir.
