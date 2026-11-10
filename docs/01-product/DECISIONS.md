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
