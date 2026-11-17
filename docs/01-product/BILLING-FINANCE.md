# Abunə və pul uçotu

R05–06, R12. İki ayrı maliyyə domeni: **Eve xidmət haqqı** və **kirayə uçotu**. Cədvəllər, API və hesabatlar ayrıdır.

## SaaS abunə

Qiymətlər server kataloqundan: monthly=999 qəpik, yearly=9999 qəpik, AZN. Client məbləği müəyyən etmir. Bir payment bir neçə evin order line-ını ödəyə bilər; bütün line-lar eyni order currency və owner-a aiddir. İlk implementasiyada bir ev checkout-u, toplu checkout isə həmin təsdiqli model üzərində ayrıca task-dır.

Hər ev: draft / trialing / active / expired / archived. Arxiv istifadə vəziyyətidir, entitlement tarixini dəyişmir. İlk evi yaradan sahibin trial_claim qeydi unique(owner_id) ilə birdəfəlikdir. İlk evin silinməsi, ikinci tab, paralel request yeni sınaq vermir. Yeni email ilə sui-istifadəni tam aradan qaldırdığı iddia edilmir; rate limit və şübhəli istifadə monitorinqi tətbiq olunur.

### Vaxt hesabı

Sınaq server timestamp-dən 7×24 saatdır. Ödənişli dövr aylıqda bir calendar month, illikdə bir calendar year; ay sonu mövcud son günə clamp edilir. İstifadə olunan anchor saxlanılır ki, 31 yanvar → 28 fevral → 31 mart qaydası itirilməsin. Calendar period anchor Asia/Baku ilə hesablanır; nəticə UTC saxlanılır, UI Asia/Baku göstərir. Dövr [starts_at, ends_at).

Başlama = max(cari ödənilmiş bitmə, təsdiqli ödəniş vaxtı). Sınaq zamanı ilk alış sınağın bitmə vaxtından başlayır, qalan sınaq itmir. Uğursuz ödəniş müddəti dəyişmir. Payment entitlement atomik bir dəfə tətbiq olunur.

Aylıqdan illiyə və əksinə keçid alınan müddəti növbəyə əlavə edir; pro-rata və avtomatik credit yoxdur. UI ödənişdən əvvəl hansı evin nə vaxtadək aktiv olacağını göstərir. Müddət uzandıqda qonaq rezervasiyasının tarixləri dəyişmir.

### Checkout vəziyyətləri

created → pending → verified_paid → entitlement_applied. failed/cancelled/expired order ödənişsiz bağlanır. Gecikmiş provider paid cavabı ayrıca reconcile olunur; əvvəl applied hadisə geri alınmır. Provider transaction ID və tətbiq edilmiş order line unikal olur.

Success URL yalnız “Ödəniş yoxlanılır” göstərir. Aktivləşmə serverdə merchant, order, amount, currency və paid status uyğunlaşdırmasından sonra olur. Webhook API-si təsdiqlənməyibsə imza formatı uydurulmur; rəsmi provider status sorğusu ilə təsdiq tələb olunur.

Provider-dən gecikmiş paid hadisə gələndə əvvəlcə server inbox-da audit olunur. Order expired/closed-dursa və ya müddəti keçibsə, Eve avtomatik entitlement vermir; hadisə `manual_review_required` olur (D43). Əvvəl tətbiq olunmuş entitlement replay/reconcile zamanı geri çevrilmir.

Refund/chargeback review order-in ayrıca state-idir; səbəbli operator review marker-i ödənişin qaytarıldığı və ya abunə müddətinin dəyişdiyi demək deyil. İlkin buraxılışda manual operator review faktiki qaytarılan line, təsirlənən period və istifadə edilmiş xidməti araşdırır; əvvəlki başqa ödənişlərin müddəti silinmir. `refunded` state-i EXT05 provider və EXT07 hüquqi təsdiqədək rezervdir və ona keçid açılmır. Qismən refund və istehlak olunmuş müddətin qaytarılması siyasəti hüquqi/provider təsdiqi olmadan avtomatlaşdırılmır.

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

Realtor settlement-ləri müştəri ödənişi kimi ikinci dəfə gəlir yaratmır. Hər realtor üzrə collected, transferred, earned commission, paid commission və offset ayrıdır (D44). `C` realtor custodian rent receipt-lərindən həmin source refund/reversal çıxıldıqdan sonra hesablanır; `T` owner-a köçürülən pul, `E` təsdiqli saxlanılmış commission, `P` owner-dan realtor-a cash payment, `O` isə qeydə alınmış offset-dir. Held rent=`C−T−O`; unpaid commission=`E−P−O`; paid commission=`P+O`; owner due=`max(0, held−unpaid)`; realtor due=`max(0, unpaid−held)`. Due yalnız bir istiqamətdə göstərilir. Offset cash payment və rent receipt deyil: eyni məbləği realtorun saxladığı rent-dən və owner-un commission borcundan silir. Transfer held rent-i, owner payment earned commission unpaid hissəsini, offset isə hər iki qalıqdan kiçik olanı aşa bilməz; earned commission-dan artıq qabaqcadan payment qəbul edilmir. 10000 qəpik realtor receipt və 3000 commission əvvəlcə 7000 owner due verir; 7000 transfer + 3000 offset sıfır qalıq yaradır. 10000-i bütövlükdə owner-a köçürən alternativdə 3000 realtor due qalır.

Settlement yazısı `realtor_accounts.version` optimistic lock-u ilə qorunur. Balance GET bu versiyanı qaytarır; hər realtor rent receipt/refund/reversal, earned-commission review və settlement dəyişikliklərində versiya atomik artır. Idempotency eyni actor, key və eyni canonical payload üçün əvvəlki nəticəni qaytarır, stale version olsa belə; eyni key ilə dəyişmiş payload conflict-dir. Settlement event append-only qalır; API cavabındakı `balance_version` hesabın nəticə versiyasıdır (row version deyil).

Faiz komissiyası depozit və refund-dan deyil, razılaşdırılan rent basis-dən hesablanır; qəpiyə half-up yuvarlaqlaşdırılır. Ləğv komissiyanı avtomatik saxlamır, səlahiyyətli şəxs təsdiqləyir.

## Xərclər

Kateqoriyalar: kommunal, bina/xidmət, təmizlik, usta/təmir, alış, sərf materialı, digər. status=proposed/approved/rejected; payment_status=unpaid/paid/partial. Kateqoriya ilə payment status qarışmır.

Aylıq sabit xərc draft/xatırlatma yaradır; faktiki ödənişi təsdiqsiz gəlmiş saymır. Dəyişən kommunal üçün amount əvvəlcədən uydurulmur. Bir neçə evə xərc bölünürsə allocation cəmi xərc məbləğinə bərabər olmalıdır; rounding qalığı deterministik son paya düşür. Menecer yalnız tam səlahiyyəti olan evlərdə allocation təsdiqləyə bilər.

Hesabatda “alınan pul”, “rezervasiya gəliri” və “xərclərdən sonra nəticə” ayrı adlandırılır. Gündəlik menecer tenant üzrə mənfəət/export görmür. Müxtəlif sahiblərin maliyyə yekunları eyni mənfəət kimi birləşdirilmir.
