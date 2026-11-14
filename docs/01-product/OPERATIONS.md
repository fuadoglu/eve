# Gündəlik əməliyyatlar

Əlaqəli tələblər: R04–09, R15–16. Məqsəd istifadəçinin məlumatı təkrar yazmamasıdır.

## Ev və ilkin quraşdırma

Email girişindən sonra yalnız evin adı və ərazi tələb olunur. Digər profil məlumatları məcburi deyil. Birinci evin yaradılması tranzaksiyası sınaq hüququnu atomik istifadə edir. Sonrakı evlər draft olaraq hazırlanır, abunə aktivləşmədən əməliyyat qeydi yaradıla bilmir. Sınaqda bütün məhsul funksiyaları açıqdır.

Standart inventar şablonu və “Başqa evdən kopyala” mövcuddur. Kopyalama yalnız istifadəçinin oxuma hüququ olan mənbədən və hədəfdə yazma hüququ ilə işləyir; qonaq, pul, məxfi kod və icazələr kopyalanmır.

## Rezervasiya

Vəziyyətlər: hold → confirmed → checked_in → completed; hold/confirmed → cancelled; confirmed → no_show. No-show və ləğv maliyyəni avtomatik sıfırlamır. Faktiki giriş/çıxış ayrıca timestamp saxlayır, planlaşdırılan gecələmə intervalı ayrıca qalır.

Məcburi: giriş, çıxış, qonağın adı və ümumi qiymət (sıfır qiymət xüsusi təsdiq ilə mümkündür). Telefon və beh opsionaldır. Qonaq sayı ev limitini aşarsa xəbərdarlıq və səlahiyyətli təsdiq tələb olunur. Giriş və çıxış saatları ev ayarından hazır gəlir.

- Gecələmə intervalı [giriş, çıxış); ən az bir gecə. Saatlıq kirayə scope-dan kənardır.
- Hold müddətləri: 1 saat / 3 saat / növbəti gün 12:00 Bakı. UI dəqiq bitmə vaxtını göstərir.
- Hold/confirmed/checked_in və manual blok eyni occupancy qorumasına daxildir.
- Vaxtı bitmiş hold cron geciksə belə yeni rezervasiyanı saxlamır: server tranzaksiyası həmin evin expired hold-larını bağlayıb yenidən yoxlayır.
- Giriş günü erkən/çıxış gec vaxtı eyni gündə hazırlığa mane olursa xəbərdarlıq verilir; gecələmə constraint-i ilə qarışdırılmır.
- Uzatma, qısaltma və ev dəyişmə yeni uyğunluq, qiymət, borc və təmizlik tarixini təsdiq ekranında göstərir.
- Qonaqdan pul alınmış rezervasiya başqa sahibin evinə köçürülmür. Eyni sahibdə ev dəyişməsi bir tranzaksiya və audit ilə edilir.
- Ləğv/no-show tarixləri azad edir; maliyyə qərarı ayrıca təsdiqlənir.
- Erkən faktiki çıxış plan tarixini səssiz dəyişmir; “Qalan günləri aç” ayrıca təsdiqlə planı və qiyməti yeniləyir.
- Qarşılıqlı dəyişikliklər version ilə yoxlanır; köhnə versiya 409 qaytarır.

## Hazırlıq və təmizlik

Gecələmə availability-si ilə hazır status ayrı saxlanır. Çıxış üçün bir cleaning task yaranır; unique(reservation_id, task_kind) təkrar yaradılmanı bloklayır. Tarix dəyişəndə gələcək iş yenilənir; tamamlanmış iş silinmir. Yoxlama tələb edilirsə cleaning task onun keçidini açır, ikinci forma yaradılmır.

Qəbul edən şəxs “Tamamladım” deyəndə iş reported_done olur. Sahib/təyinli menecer “Təsdiqlə” edir. Hazırlıq yalnız tələb olunan təmizlik və yoxlamalar tamamlandıqda hazır olur. Hazırlığı pozmayan xırda inventar problemi tarixləri avtomatik bloklamır.

## Əlaqələr və tapşırıq

Kontakt sahibə məxsusdur; lazım olan evlərə bağlanır. Eyni nömrə ayrı sahiblərin kontaktı ola bilər, qeydlər birləşdirilmir.

Tapşırıq sahələri: ev, işin adı, vaxt; icraçı/qeyd/media opsional. Tapşırığın ilkin təlimatı ayrıca qalır: icraçının “Tamamladım” qeydi və səlahiyyətli şəxsin “Yenidən baxılmalıdır” səbəbi keçid tarixçəsinə əlavə olunur, təlimatı overwrite etmir. Bildirilən ad doğrulanmış user kimliyi deyil. EVE-017.1 append-only typed task transition history, media association və idempotent DB write component-i yaradır; `report_done` transition-u owner notice üçün outbox event-i atomik yaradır; çatdırılma worker-i sonrakı paketdədir. Readiness-required task yalnız əlaqəli tamamlanmış inspection submission və bütün snapshot room cavabları olduqda report edilə bilər. `confirm` readiness recompute etmir, çünki alqoritm ayrıca müəyyən edilməlidir. HTTP/scoped-cookie route və full AT15–16 inteqrasiyası sonrakı paketlərdədir. Vəziyyətlər: open → accepted → reported_done → completed; cancelled ayrıca. Gecikmə derived göstəricidir. WhatsApp düyməsi yalnız linki açır; actual sent/read statusu yoxdur. Açılış GET-i vəziyyət dəyişmir.

İşçi öz tapşırığına xərc təklif edə bilir. Təklif təsdiqlənənədək faktiki təsdiqli expense deyil. “İş tamamlandı” ilə “Xərc ödənildi” ayrı hadisələrdir.

## İnventar və təhvil yoxlaması

Daimi siyahı: otaq, əşya, say, ölçü vahidi, vəziyyət; şəkil/model/zəmanət opsional. Sərf materialında qalıq və minimum hədd opsional; real istifadə izlənmirsə avtomatik saxta sərf hesablanmır.

### Gündəlik avtomatlaşdırma

Hər aktiv və ya sınaqda olan ev/Bakı günü üçün inspection_day konteksi idempotent job ilə yaranır. Scheduler bağlanmış günləri catch-up edə bilər. Bu kontekst özü gecikmiş tapşırıq deyil. Təhvil hadisəsi varsa inspection_event, tərəf üçün ayrı inspection_submission yaranır. Bir gündə iki təhvil və iki tərəfin cavabı qarışmır.

Günlük keçid həmin day's konteksti seçir; sabah köhnə keçid yeni günə səssiz keçmir. Hadisəyə scoped verən/alan linki yaradılır. Tərəf müəyyən deyilsə bir dəfə iki aydın seçim göstərilir; sistem rol uydurmur. Ümumi link eyni tərəfə ikinci müraciəti mövcud draft-a yönləndirir, tamamlanmış cavabı overwrite etmir.

### Mobil forma

1. Ev, tarix və əvvəlcədən müəyyən tərəf görünür.
2. Hesabla tanınır və ya bildirilən ad daxil edilir.
3. Otaq siyahısı və saylar görünür: “Hamısı qaydasındadır” / “Problem var”.
4. Problem: əşya, çatışmır və ya zədəlidir/işləmir; faktiki say və opsional foto/səs/qeyd.
5. “Yoxlamanı bitir”; server qəbulundan sonra uğur.

Heç bir otaq əvvəlcədən yoxlanmış deyil. Siyahı göstərilmədən toplu təsdiq yoxdur. Bütün otaqlar üçün cavab tələb olunur; “yoxlamaq mümkün olmadı” səbəbli seçim saxta təsdiqin qarşısını alır və sahibə görünür. Cavablar serverə autosave edilir; bağlantı yoxdursa “Saxlanılmayıb” göstərilir, məxfi draft device persistent storage-a səssiz yazılmır.

Başlanğıcda inventar versiyasının snapshot-u alınır. İcra zamanı baza dəyişsə cavabın siyahısı dəyişmir. Tamamlanma immutable; correction yeni revision-dur. Verən/alan cavabları ayrı qalır, biri digərinin tamamlanmasını bloklamır. Adını yazmaq şəxsiyyət təsdiqi deyil.

Problem sahibi/meneceri xəbərdar edir, avtomatik depozit tutulması və inventardan silinmə yaratmır.

## İdxal / ixrac

CSV və XLSX üçün hazır şablon: rezervasiya və inventar. Preview + sətir səhvləri + təsdiq; xətalı fayl səssiz qismən import edilmir. Batch ID və source row key ilə təkrar import dublikat yaratmır. Tarix formatı və ev uyğunluğu açıqdır; formula/csv injection export-da zərərsizləşdirilir. Import mövcud qeydləri overwrite etmir. Böyük fayl batch ilə işlənir, tenant kvotası var.
