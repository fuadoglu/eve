# Qərar reyestri

Statuslar: **Təsbit** — istifadəçinin açıq tələbi; **İcra qərarı** — sadəlik üçün seçilmiş texniki/məhsul həlli; **Xarici təsdiq** — təminatçı və ya hüquqi qərar tələb edir. İcra qərarı dəyişərsə bu reyestr və testlər eyni PR-də dəyişir.

| ID | Qərar | Status |
|---|---|---|
| D01 | Ad Eve; ilkin bazar Azərbaycan; AZ panel | Təsbit |
| D02 | Bir sahib çox ev; menecer bir neçə sahibdən ev idarə edir | Təsbit |
| D03 | Yalnız email magic link; şifrə və məcburi profil yoxdur | Təsbit |
| D04 | Uzunmüddətli yenilənən sessiya; sonsuz sessiya vədi yoxdur | Təsbit / icra |
| D05 | 999 qəpik/ay və 9999 qəpik/il; yalnız ilk evə 7 gün sınaq | Təsbit |
| D06 | “Yalnız aylıq abunə alırıq” gəlir modelinə aiddir; illik plan saxlanılır | Əvvəl açıqlanmış icra şərhi; gizli plan dəyişikliyi edilmir |
| D07 | Payriff yalnız SaaS üçün; kirayə marketplace/payment flow yoxdur | Təsbit |
| D08 | Public səhifə noindex; əlaqə nömrələri yoxdur; təqvim sahibin seçimi ilə yalnız boşluq göstərir | Təsbit |
| D09 | Çoxdilli mətn, şəkil, video QR təlimatları və sabit keçid | Təsbit |
| D10 | Gündəlik inventar konteksti avtomatik; təhvil başına ayrıca cavab; təhvil verən və alan doldura bilər | Təsbit |
| D11 | WhatsApp keçidi paylaşılır; avtomatik göndərildi/oxundu iddiası yoxdur | Təsbit / icra |
| D12 | Next.js + TypeScript + Supabase; mobil PWA; bir repo və bir tətbiq | İcra qərarı |
| D13 | Gündəlik və tam idarəetmə; icazə hər ev üzrə | İcra qərarı |
| D14 | Avtomatik təkrarlanan ödəniş opt-in; illik provider dəstəyi təsdiqlənməyib; ilkin manual hosted checkout tam işləməlidir | Xarici təsdiq |
| D15 | Subscription expiry zamanı yeni əməliyyatlar bağlanır; oxuma/export qalır | İcra qərarı |
| D16 | Əvvəl yayımlanmış ümumi təhlükəsizlik QR-ləri abunə bitdiyi üçün bağlanmır | Son red-team qərarı; əvvəlki 7 günlük QR bağlanması ləğv olunur |
| D17 | Məxfi qonaq keçidi çıxış + 24 saatadək, tapşırıq keçidi son vaxt + 48 saatadək; 30 gündən uzun keçid ayrıca yenilənir | İcra qərarı |
| D18 | İllik/aylıq plan dəyişmə cari ödənilmiş müddətin sonuna əlavə edilir; ilkin buraxılışda pro-rata yoxdur | İcra qərarı |
| D19 | Arxiv abunəni dondurmur, hesablanan sınağı yenidən vermir; aktiv müddətdə səhv arxiv geri açılır | İcra qərarı |
| D20 | Offline yalnız məxfi olmayan statik tətbiq qabığı; private data və token səhifələri service worker cache-ə düşmür | İcra qərarı |
| D21 | QR təhlükəsizlik mətn/şəkil dərc edilibsə, ev arxivdə olsa da xidmət fəaliyyət göstərdikcə read-only qalır; məxfi kodlar bu məzmuna daxil deyil | İcra qərarı; retention hüquqi nəzərdən keçirilir |
| D22 | Video max 100 MiB/5 dəq; foto max 15 MiB giriş; ev üzrə 1024 MiB ilkin media kvotası; genişləndirmə ödənişi hələ yoxdur | İcra qərarı, istifadə ölçülərinə görə dəyişilə bilər |
| D23 | Avtomatik tərcümə, iCal/channel manager, marketplace, native app ilkin scope-da deyil | İcra qərarı |
| D24 | Sahiblik transferi ilkin buraxılışda self-service deyil; başqa evə/sahibə məlumat daşıma səssiz edilmir | İcra qərarı |

## Dəyişiklik qaydası

Hər yeni qərarda səbəb, təsirlənən tələb/test ID-ləri, keçid/data migration ehtiyacı qeyd edilir. Xarici asılılığın həlli implementasiya təxminindən deyil, sandbox və hesab konfiqurasiyası sübutundan gəlir. Məhsul spesifikasiyasının mövcudluğu hüquqi mətn, provayder təsdiqi və ya işləyən proqram sübutu deyil.


## Dəqiqləşdirmə əlavəsi — v2

| ID | Qərar | Status |
|---|---|---|
| D25 | API/DB/UI ad və enum-ları field-bindings müqaviləsi ilə yoxlanır; name120, area160; hazır vəziyyət ready/cleaning_pending/attention_required | İcra qərarı |
| D26 | Private scoped media hər fetch-də link/expiry/revoke yoxlayan proxy-dən verilir; əvvəl yüklənən baytları geri silmək vədi yoxdur | Red-team düzəlişi |
| D27 | Move/cancel/no_show köhnə placement guest-private keçidlərini atomik bağlayır | Red-team düzəlişi |
| D28 | Base data app_private; api allowlist RPC; authenticated/anon base-table grant yoxdur | Giriş sərhədinin dəqiqləşdirilməsi |
| D29 | Provider credential gate-i local domain/schema/UI işini bloklamır; sandbox sınağı ayrıca Done/release şərtidir | İcra ardıcıllığının düzəlişi |
| D30 | Reversal və depozit allocation yalnız sahib/full; daily managerin rent receipt qeydi ilə qarışmır | İcazə dəqiqləşdirilməsi |
| D31 | R05 qəbul əlaqəsi AT11–13, R06 qəbul əlaqəsi AT14-dür. AT13 realtor settlement və ikinci receipt-in qarşısını, AT14 expense approval/allocation-u yoxlayır; ssenarilərdə müvafiq olaraq yalnız R05 və R06 göstərilir. PRD-dəki əlavə əlaqələr buna görə düzəldilir. Hər iki ssenari və M7-də AT01–36 tələbi saxlanılır; məhsul davranışı, data və migration dəyişmir. | Sənəd və traceability uyğunluğu; R05/R06, AT13/AT14 |
| D32 | `billing_order` state siyahısı DB/API `order_state` enum-u ilə eynidir. `reviewOperatorOrder` üçün `review_refund`/`review_chargeback` yalnız allowlisted operatorun səbəb və versiya yoxlamasından sonra `entitlement_applied` order-ini müvafiq review state-inə keçirir; audit yazılır, ödəniş faktı və abunə müddəti dəyişmir. `refunded` enum-da rezervdir, EXT05 provider və EXT07 hüquqi qayda təsdiq olunmadan ona keçid, avtomatik refund və müddət silinməsi yoxdur. Səbəb: state/enum ziddiyyətini provider davranışı uydurmadan bağlamaq. R12/R14, AT32 təsirlənir; mövcud tətbiq və migration yoxdur. | İcra qərarı və xarici gate sərhədi |
| D33 | Altı media classification üçün ayrı bucket ID-ləri: `public_property`→`eve-public-property`, `public_guide`→`eve-public-guide`, `private_guest`→`eve-private-guest`, `private_receipt`→`eve-private-receipt`, `private_inspection`→`eve-private-inspection`, `private_task`→`eve-private-task`. Hamısı Storage səviyyəsində private qalır; dərc olunmuş təhlükəsiz public media yalnız serverin safe projection-u ilə, scoped private media hər sorğuda yoxlanan proxy ilə verilir. Səbəb: draft/publication vaxtı Storage public bucket-in birbaşa download-u sızma yaratmasın. R09/R10/R11/R14 və AT06/AT21/AT25/AT32 təsirlənir; `media_assets` bucket CHECK-i və yeni storage migration tələb olunur. Real Supabase bucket/signed-upload davranışı sandbox-da ayrıca təsdiqlənir. | İcra qərarı; provider sübutu açıq |
| D34 | Daimi inventara qoşulan media ayrıca `private_inventory` classification və `eve-private-inventory` bucket istifadə edir; `media_bindings.inventory_item_id` yalnız eyni property/owner üzrə validated, silinməmiş media-ya bağlanır. Bucket private qalır, birbaşa Storage access deny-dir, media URL-i DTO-da verilməyib. Səbəb: inventar fotosu task/inspection semantikasına aid deyil və fərqli classification-a qarışdırılmamalıdır. R07/R09/R11, AT05/AT06/AT35; enum forward migration, DB CHECK, storage policy/config və API DTO dəyişir. | EVE-019.1 üçün məhsul/security qərarı; real upload/finalize/proxy sandbox ayrıca açıqdır |
| D35 | Menecer dəvət bearer linki serverdə SHA-256 hash kimi saxlanır, birdəfəlikdir, yalnız authenticated istifadəçinin normalized email-i ilə uyğun gələndə və yaradılmasından 24 saat keçmədən qəbul edilir; müddəti bitmiş dəvət üzvlük yaratmır, təzə dəvət istənir. 24 saat seçimi gecikmiş emailə vaxt verib link sızması/replay pəncərəsini məhdudlaşdırır; NIST SP 800-63-4 email confirmation üçün 24 saat yuxarı hədd göstərir, amma dəvət emaili authentication deyil və Eve-nin email-match şərtini əvəz etmir. R03/R13, AT04/AT05; config `access.manager_invite_ttl_hours=24`, expired/replay/mismatched email mənfi sınaqları. | İnteqratorun risk əsaslı texniki qərarı; resending/SMTP sandbox ayrıca |
| D36 | Scoped task transition DB command yalnız `authenticated` sahib/menecer və server-only `service_role` vasitəsilə çağırılır; anon birbaşa RPC əldə etmir. Link hər request-də token hash, task/property scope, exact `task.accept`/`task.report_done`, revoke və expiry ilə DB-də yoxlanır; server secret brauzerə verilmir. Idempotency key actor/link və action üzrə scope olunur; eyni key+payload əvvəlki nəticəni qaytarır, fərqli payload mismatch-dir. R07/R08, AT15/AT16; service role yalnız backend client-də, hosted Data API və tam revoke/prefetch sınağı EVE-017.3-də. | Təhlükəsizlik icra qərarı; route/provider sübutu sonrakı paketlərdə |
| D37 | Upload intent 15 dəqiqəlik versiyalanmış rezervasiya pəncərəsi alır; yarımçıq `pending` rezerv bu vaxtdan sonra kvota cəmindən çıxır. Saxlanmış `size_bytes` pending halda tələb edilən rezerv ölçüsüdür, finalize zamanı yalnız rezervdən böyük olmayan faktiki ölçü ilə əvəzlənir və `upload_expires_at` təmizlənir; rezervdən böyük obyekt finalize-də rədd edilir ki, faktiki istifadənin əvvəlcədən seriyalaşdırılmış kvotanı artırması mümkün olmasın. Intent yaradılması Storage upload-un və ya MIME/magic-byte yoxlamasının sübutu deyil. Eyni actor/idempotency key + eyni payload eyni media ID-ni qaytarır, fərqli payload konflikt verir. R09/R10/R11, AT06/AT21/AT32; versiyalanmış server default-u, atomik quota smoke, over-reservation rəddi və replay/mismatch mənfi sınaqları. | İnteqratorun risk əsaslı texniki qərarı; real signed-upload provider davranışı sonrakı paketdə |
| D38 | Upload rezervasiya DB primitive-i yalnız `app_executor` üçün daxili qalır; authenticated/anon birbaşa çağırışı və Data API exposure yoxdur. Server adapter OpenAPI body `classification`-ı capability/resurs scope-dan derive edib ötürməlidir; `.1` adapter və Storage URL vermir. Guest/task/inspection media-nı property-only sorğudan scope etmək mümkün olmadığından bu sərhəd saxlanır. R07/R09/R10/R11/R13, AT06/AT21/AT32; role/grant negative test, server adapter və real signed upload sonrakı paketlərdə açıqdır. | Təhlükəsizlik sərhədi; server adapter sonrakı inteqrasiya işidir |
| D39 | Media finalize mutation `app_private` daxilində qalır və `authenticated`/`anon` üçün bağlıdır. Yalnız server credential ilə çağırılan dar `api` bridge, artıq yoxlanmış server session actor ID-sini cari request transaction-u daxilində private primitive-ə ötürə bilər; server istifadəçi session-ını ayrıca doğrulamadan bridge çağırıla bilməz. Ayrı server-only read bridge yalnız actor-un cari icazəsi olan pending media üçün classification/bucket/object key/rezerv limitini qaytarır; browser bu internal lokasiyanı almır. Bridge-lər raw token/credential saxlamır və signed Storage read URL qaytarmır. EVE-022.2, AT06/AT21; grant, actor scope və Storage lokasiyasının client denial SQL smoke tələb olunur. | İcra qərarı; route/session inteqrasiyası və hosted provider sübutu ayrıca |
