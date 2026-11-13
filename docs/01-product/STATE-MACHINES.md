# Vəziyyət keçidləri və yan təsirlər

Bu sənəd hər düymənin serverdə nə etdiyini dəqiqləşdirir. Maşınla yoxlanan mənbə: [state-machines.json](state-machines.json). Cari istifadəçi tələbi ilə ziddiyyət yoxdursa aşağıdakı keçidlər normativdir. Siyahıda olmayan keçid rədd edilir; UI düyməsi gizlənsə də server eyni qaydanı tətbiq edir.

## Ümumi yazı qaydası

Hər əməliyyat cari capability, evin abunə hüququ, versiya və idempotency yoxlamasından keçir. Pul, occupancy, snapshot və outbox dəyişiklikləri bir tranzaksiyada commit edilir. Bildirişin faktiki çatması biznes tranzaksiyasının şərti deyil. Eyni əməliyyat təkrarı yeni pul və tapşırıq yaratmır. GET keçid və ya təsdiq əməliyyatı deyil.

## Menecer dəvəti

| Hazırkı vəziyyət | Hadisə | Yeni vəziyyət | Yoxlama və atomik nəticə |
|---|---|---|---|
| Yoxdur | Sahib email dəvəti yaradır | pending | Path ev seçilmiş siyahıdadır; bütün evlər eyni sahibindir və active/trialing entitlement var; permission eynidir; email normalized edilir; expiry maksimum 24 saatdır |
| pending | Dəvət emaili uyğun sessiya ilə qəbul olunur | accepted | Raw token serverdə hash edilir; recipient email tam uyğunluğu, expiry və bütün evlərin cari entitlement-i yoxlanır; seçilmiş evlər üzrə membership-lər bir tranzaksiyada yazılır |
| pending | Uyğun recipient expiry-dən sonra qəbul edir | expired | Dəvət expired olur, heç bir membership yaranmır; API 410 qaytarır |
| pending | Sahib eyni emailə yeni dəvət yaradır | revoked | Əvvəlki bearer token etibarsız olur; yeni dəvət və property seçimləri ayrıca yazılır |

accepted, revoked və expired terminaldır. Yanlış email/token neytral 404-dür, replay və mövcud aktiv membership-i permission dəyişmək üçün işlətmək rədd edilir. SMTP göndərişi təsdiqlənməyibsə UI/API emaili göndərildi kimi göstərmir.

## Rezervasiya

| Hazırkı vəziyyət | Düymə / hadisə | Yeni vəziyyət | Yoxlama və atomik nəticə |
|---|---|---|---|
| Yoxdur | Müvəqqəti saxla | hold | Aktiv ev, düzgün interval, toqquşma yoxdur; hold occupancy və son vaxt yaranır |
| Yoxdur | Təsdiqlə | confirmed | Eyni yoxlamalar; reservation, placement, occupancy və varsa ilkin pul qeydi birlikdə yaranır |
| hold | Təsdiqlə | confirmed | Müddət bitməyib, qiymət və tarix təsdiqlənib; occupancy saxlanır, hold expiry təmizlənir |
| hold | Müddət bitdi | cancelled | reason=hold_expired; cron və ya növbəti booking yazısı eyni lock altında occupancy-ni azad edir |
| hold / confirmed | Ləğv et | cancelled | Alınan pul varsa saxlanılan/qaytarılacaq məbləğ açıq təsdiq edilir; refund fiziki baş verməyibsə qaytarılıb yazılmır |
| confirmed | Giriş etdi | checked_in | Aktiv hüquq, cari versiya; faktiki giriş vaxtı və audit |
| confirmed | Qonaq gəlmədi | no_show | Plan giriş vaxtı keçib; pul qərarı ayrıca, occupancy azad edilir |
| checked_in | Çıxış etdi | completed | Faktiki çıxış, təmizlik/yoxlama işi idempotent yenilənir; gələcək günlər yalnız ayrıca təsdiqlə açılır |
| hold / confirmed / checked_in | Tarixi dəyiş | Eyni | Yeni interval və qiymət razılaşması, qalıq, gələcək task və occupancy birlikdə yenilənir |
| hold / confirmed / checked_in | Evi dəyiş | Eyni | Yalnız eyni sahib, hər iki evdə icazə/aktivlik və toqquşma yoxlaması; yeni immutable placement, qeyri-pul attribution transfer, köhnə tamamlanmış tarixçə dəyişmir |

Completed-dən yalnız `release_remaining_days` əməliyyatı mümkündür: faktiki erkən çıxış qeydi, yeni plan çıxış tarixi və qiymət açıq təsdiqlənir; state completed qalır, gecələmə hüququ yenidən açılmır. Cancelled və no_show avtomatik geri açılmır. Yeni rezervasiya yaradıla bilər; köhnə pul tarixçəsi onun üzərinə kopyalanmır. Yanlış maliyyə əməliyyatı reversal ilə düzəlir. Cross-owner move ilkin buraxılışda qadağandır.

## Tapşırıq

| Vəziyyət | Əməliyyat | Nəticə | Qayda |
|---|---|---|---|
| Yoxdur | Yarat | open | Ev, iş adı, vaxt; təmizlikdə reservation+kind dedupe |
| open | Qəbul etdim | accepted | Keçid və ya səlahiyyətli hesab; GET qəbul etmir |
| open / accepted | Tamamladım | reported_done | İcraçı acceptance addımını unutsa da işi bildirə bilir; tələb olunan yoxlama otaqları cavablandırılıb |
| reported_done | Təsdiqlə | completed | Sahib və ya həmin evin meneceri; readiness yalnız bütün tələb olunan işlər hazır olduqda dəyişir |
| reported_done | Yenidən baxılmalıdır | accepted | Qısa səbəb, əvvəlki nəticə tarixçədə qalır; icraçıya bir bildiriş |
| open / accepted / reported_done | Ləğv et | cancelled | Səlahiyyətli şəxs; keçid yazmaq üçün bağlanır, tarixçə saxlanır |

İşin tamamlanması xərcin təsdiqi və ya ödənilməsi demək deyil. Expired abunədə əvvəl verilmiş iş yalnız mövcud keçidin yazı müddətində nəticə qəbul edə bilər; yeni iş yaradıla bilməz.

## İnventar yoxlaması

| Vəziyyət | Əməliyyat | Nəticə |
|---|---|---|
| Yoxdur | Yoxlama başla | draft; snapshot bir dəfə bağlanır, tərəf və bildirilən/hesab adı müəyyən edilir |
| draft | Otağı yoxla / problem yaz | draft; server autosave ack, hər otaq explicit cavablanır |
| draft | Yoxlamanı bitir | completed; bütün otaqlar cavablıdır, immutable nəticə |
| completed | Düzəliş yarat | Əvvəlki completed qalır, ayrıca yeni draft revision açılır |
| draft | Keçid vaxtı bitdi / ləğv edildi | Draft saxlanır, yeni yazı rədd edilir; saxta completed yaradılmır |

Təhvil verən və alan eyni event-in ayrı submission-larıdır. Birinin işi digərindən asılı deyil. “Yoxlamaq mümkün olmadı” səbəbi qəbul edilən cavabdır, “hamısı yaxşıdır” sayılmır. İki tərəfin ziddiyyətli cavabı owner/manager üçün fərq kimi göstərilir; hüquqi qərar və pul tutulması yaratmır.

## Xərc

proposed → approved / rejected. Rejected əvvəlki qeyd üzərinə approved olmur; düzəldilmiş yeni təklif yaradıla bilər. Approved xərcin ödənişi ayrıca unpaid / partial / paid projection-dır. Ödəniş cəmi təsdiqli məbləği aşmır. Approved məbləğ düzəlişi reversal/replacement və auditlə edilir, tarixi silmir. Təkrarlanan kommunal xatırlatma özü paid expense yaratmır.

## Abunə order-i və hüquq

created → pending → verified_paid → entitlement_applied. failed/cancelled/expired halları providerin son doğrulanmış statusuna görədir. Gecikmiş həqiqi paid status server verification-dan sonra verified_paid-ə keçə bilər; eyni order line yalnız bir dəfə tətbiq edilir. entitlement_applied-dən köhnə pending/failed hadisə geriyə qaytarmır. Səbəbli və versiyalı operator `review_refund`/`review_chargeback` əməliyyatı yalnız `entitlement_applied`-dən müvafiq review state-inə keçir, audit yazır; ödəniş faktını və abunə müddətini dəyişmir. `refunded` enum-da rezervdir: EXT05/EXT07 təsdiqinə qədər bu state-ə keçid açılmır. Ətraflı [D32](DECISIONS.md).

Evin effective entitlement-i: trialing / active / expired; draft evdə entitlement yoxdur. archived evin istifadə vəziyyətidir, ödənilmiş müddəti dondurmur. read-only hüququ mütləq tam hüquqsuzluq deyil: owner export və təhlükəsizlik QR istisnaları saxlanır. Ətraflı [abunə qaydası](BILLING-FINANCE.md).

## Səhv davranışı

Yanlış state: 409 INVALID_TRANSITION. Köhnə versiya: 409 VERSION_CONFLICT. Toqquşma: 409 DATE_CONFLICT. Yetərsiz capability: resursu açıqlamayan 404 və ya mövcud səlahiyyətli kontekstdə 403. Müddəti bitmiş keçid: 410 LINK_EXPIRED. UI baş verən nəticəni sadə AZ mətnlə izah edir və daxil edilmiş qeydi itirmir.

Move, cancel və no_show tranzaksiyası köhnə placement-in məxfi qonaq keçidlərini də ləğv edir. Private media proxy-si hər yeni sorğuda linkin cari vəziyyətini yoxlayır; əvvəl endirilmiş fayl istifadəçinin cihazından geri silinə bilməz.
