# Eve — konkret mobil axın müqavilələri

Bu sənəd R01–16 və UI01–19 üçün formaların sırasını, default-ları, düymələri və xəta davranışlarını təsbit edir. [Prototip](PROTOTYPE.md) həmin davranışın bir hissəsinin vizual nümayişidir; server müqaviləsini əvəz etmir.

## Ümumi UI müqaviləsi

Bir ekranda bir əsas iş və əsas CTA. Kontekstdən məlum ev/rezervasiya yenidən soruşulmur, başlıqda göstərilir. Form sahibi olmadıqda əvvəl **“Hansı ev?”** seçimi açılır; keçmiş ev səssiz seçilmir. `+` menyusunda dörd əməliyyat var; “Pul qeydi” seçilib aktiv rezervasiya məlum deyilsə evdən sonra rezervasiya seçilir.

Əsas input-lar 16 px, düymə hədəfi ən az 44×44 px. Məcburi sahə label-də aydındır; opsional sahədə “istəyə bağlı” yazılır. Placeholder label-i əvəz etmir. Məbləğ decimal klaviatura ilə daxil edilir, UI lokal vergülü qəbul edib serverə qəpik integer göndərir. 0,001 kimi üçüncü qəpik rəqəmi yuvarlaqlaşdırılıb gizlədilmir: “Məbləği ən çox 2 onluq rəqəmlə yazın.”

Server təsdiqinə qədər submit disabled + “Yoxlanılır…”; ikiqat toxunuş eyni idempotency key ilədir. Şəbəkə xəta verəndə daxil edilmiş dəyərlər açıq formanın yaddaşında qalır. Offline: “Bağlantı yoxdur. Son dəyişiklik hələ saxlanılmayıb.” Dəyişiklikləri saxlamaq üçün internet lazımdır; private draft səssiz persistent storage-a yazılmır.

## F01 — Email ilə daxil ol

| Sıra | Sahə / davranış |
|---|---|
| 1 | Email, autocomplete=email, trim; rol və şifrə yoxdur |
| 2 | **Email ilə davam et** |
| 3 | Neytral nəticə: “Emailinizi yoxlayın”; yazılan ünvan görünür |
| 4 | **Emaili dəyiş** və 60 saniyədən sonra **Yenidən göndər** |
| 5 | Email keçidi → aydın **Eve-yə daxil ol** təsdiqi → panel |

Xətalar: boş/yanlış email “Email ünvanını düzgün yazın.”; rate limit “Bir az gözləyib yenidən sınayın.”; expired link “Bu giriş keçidinin müddəti bitib. Yeni keçid alın.” Hesabın mövcudluğu açıqlanmır. Link hansı cihazda açılırsa həmin cihaz üçün sessiya yaradılır; cross-device provider imkanları sınaqla təsdiqlənir. Girişdən sonra profil tamamlama modalı ilə iş bloklanmır.

## F02 — İlk ev və sonrakı evlər

İlk ekranda **Ev əlavə et**. Məcburi ev adı (1–120 simvol) və ərazi (1–160); əmlak tipi seçimi mənzil/bağ evi/digər, default mənzil. Dəqiq ünvan, şəkil, qonaq sayı və inventar sonradan. İlk ev təsdiqlənəndə server bir dəfə 7 günlük sınaq yaradır. Nəticə: evin təqvimi və “Sınaq: … tarixədək”. İkinci ev draft kimi hazırlana bilər; əməliyyat başlamazdan əvvəl həmin ev üçün abunə seçimi görünür. Sınaq haqqını client müəyyən etmir.

## F03 — Rezervasiya yarat

| Sıra | Sahə | Default / yoxlama |
|---|---|---|
| 1 | Ev | Kontekstdən hazır, başlıqda görünür |
| 2 | Giriş–çıxış | Təqvim seçimi; çıxış girişdən sonradır, ≥1 gecə |
| 3 | Qonağın adı | Məcburi 1–150 simvol (OpenAPI/data model ilə eyni limit) |
| 4 | Telefon | Opsional; beynəlxalq `+` formatı tələb olunur, boşluq/mötərizə/defis silinərək normallaşdırılır; ölkə kodu təxmin edilmir |
| 5 | Ümumi qiymət | Məcburi AZN; gecəlik tarif varsa server hesabı hazır gəlir |
| 6 | Alınan pul | Opsional, default boş=0; pulu alan default sahib/menecer |
| 7 | Əlavə məlumat | Saatlar, qonaq sayı, realtor/komissiya, depozit, qeyd |
| 8 | Tarix seçimi | **Təsdiqlə** və **Müvəqqəti saxla** |

Sıfır qiymət yalnız ayrıca “Ödənişsiz qalma” seçimi ilə təsdiq olunur; təsadüfi boş input=0 deyil. Alınan pul qiyməti aşarsa “Artıq ödəniş … AZN olacaq” görünür, ayrıca hesabda saxlanır. Depozit rent receipt ilə qarışdırılmır.

Hold seçiləndə 1 saat / 3 saat / sabah 12:00 hazır seçimləri və dəqiq Bakı bitmə vaxtı görünür. Ən azı bir gecə uyğun deyilsə “Bu tarixlər artıq uyğun deyil. Təqvimi yeniləyin.”; forma məlumatı qalır. Versiya konflikti: “Bu rezervasiya yenilənib. Son məlumatı yoxlayın.” Məcburi merge/overwrite düyməsi yoxdur.

Uğurdan sonra reservation detail: **Ümumi / Alınıb / Qalıb**, tarixlər və vəziyyətə uyğun CTA. Hold və təsdiq rezervasiya+occupancy+ilkin receipt ilə atomikdir; ilkin ödəniş yazısı uğursuzdursa rezervasiya yarımçıq uğur kimi göstərilmir.

## F04 — Rezervasiyanı dəyiş / ləğv et

**Dəyiş** içində tarix və eyni sahibin başqa evi seçilir. Təsdiqdən əvvəl köhnə/yeni tarix, yeni qiymət, qalıq və təmizlik vaxtı göstərilir. Qonaqdan pul alınmış rezervasiya başqa sahibin evinə köçürülmür. Eyni sahibdə maliyyə tarixçəsinin saxlanması data müqaviləsinə uyğun serverdə edilir.

**Giriş etdi** planlaşdırılan intervalı deyil, faktiki vaxtı qeyd edir. **Çıxış etdi** təmizlik işini göstərir. Erkən çıxışda “Qalan günləri aç” ayrıca seçimdir; qiymət səssiz dəyişmir.

Ləğvdə “Tarixlər açılacaq. Alınan pul avtomatik qaytarılmayacaq.” yazılır. Saxlanılan kirayə məbləği, refund qərarı və varsa komissiya nəticəsi göstərilir. **Ləğvi təsdiqlə** bir əməliyyatdır; pul qaytarma faktiki köçürmə deyil və orijinal receipt-ə bağlanır.

## F05 — Pul al / qaytar / depozit

Kontekst rezervasiyadır. Sıra: məbləğ → rent/depozit → pulu alan → tarix (bu gün) → opsional qeyd. Realtor varsa custodian seçimi açıqdır. Refund: orijinal receipt seçilir, qaytarıla bilən limit görünür; artıq refund bloklanır. Yekun preview qalıq və artıq ödənişi göstərir. **Qeydə al** bank əməliyyatı deyil.

Depozit detail ayrıca **Alınıb / Qaytarılıb / Saxlanılır**. Zərərə yönəltmək üçün səbəb, məbləğ və səlahiyyətli təsdiq tələb olunur. İnventar problemi bu əməliyyatı özü yaratmır.

## F06 — Xərc və təsdiq

Ev → məbləğ → kateqoriya əsas sahələrdir. Tarix default bu gün. “Əlavə məlumat”: qeyd, çek, usta, ödənilib, son ödəniş tarixi. Bir neçə evə bölüşdürmə adi formanın altında ayrıca **Bölüşdür** seçimi ilə açılır; cəm əsas məbləğə bərabər olmalıdır və seçilən evlər eyni sahibindir.

Daily menecer/işçi CTA-sı **Xərc təqdim et**, nəticə “Təsdiq gözləyir”. Sahib/full menecer **Xərci qeydə al** ilə təsdiqli xərc yaza bilər. Təsdiq və faktiki ödəniş ayrı vəziyyətlərdir. Təkrarlanan kommunal seçimi avtomatik ödəniş deyil, aylıq draft/xatırlatma yaradır.

## F07 — Tapşırıq yarat və paylaş

Sıra: ev → işin adı (1–160) → vaxt → opsional icraçı → opsional qeyd/şəkil. Kontakt siyahısı yalnız həmin evə uyğun sahib kontaktlarıdır. **Tapşırığı yarat** sonra detail açır; ayrıca **WhatsApp-da paylaş** düyməsi hazır mətn və scoped linklə WhatsApp açır. App yoxdursa **Mətni və keçidi kopyala**.

“Göndərildi”/“Oxundu” statusu göstərilmir. İcraçının səhifəsi yalnız iş, lazım olan ünvan/təlimat və vaxt göstərir. **Qəbul etdim** → **Tamamladım**; owner/full/daily task.manage sahibi **Təsdiqlə** edir. Reported done-dan əvvəl təsdiq tələb olunarsa aydın xəbərdarlıq var. GET/preview qəbul və tamamlanma deyil. Expired: “Bu keçid artıq aktiv deyil.”

## F08 — İnventar və təhvil

Sahib otaq/əşya/say siyahısını hazır şablondan və ya icazəli evdən kopyalayır. Kopyalama qonaq, maliyyə, giriş kodu və icazə daşımır. Daimi siyahı dəyişiklikləri əvvəlki yoxlamaları dəyişmir.

Yoxlama açılarkən ev, Bakı tarixi və təhvil tərəfi başlıqda hazır görünür. Tərəf məlum deyilsə yalnız bir dəfə “Təhvil verirəm / Təhvil alıram” seçilir. Hesabla tanınan actor hazırdır; digəri ad yazır. Ad şəxsiyyət təsdiqi sayılmır.

Hər otaq siyahısı saylarla açıqdır. İki əsas düymə **Hamısı qaydasındadır / Problem var**. Kiçik alternativ **Yoxlamaq mümkün olmadı** səbəb tələb edir. Heç nə əvvəlcədən təsdiqlənmir.

Problem: əşya → çatışmır və ya işləmir/zədəlidir → faktiki say → opsional foto/səs/qeyd. Say 0 və daha böyük tam ədəddir; zədədə sayın izahı ehtiyac yoxdursa gizlədilə bilər. Mikrofon icazəsi rədd olunsa yazı/foto axını davam edir. Məcburi uzun izah yoxdur.

**Yoxlamanı bitir** yalnız hər otaqda cavab və tələb olunan səbəblər varsa aktiv tamamlanır. Yekun otaq/problem sayını göstərir; server acknowledgement-dan sonra “Yoxlama göndərildi. Səhifəni bağlaya bilərsiniz.” Hər tərəfin cavabı ayrı snapshot/revision-a bağlıdır. İkinci tərəfin iştirakı birincinin completion-ını bloklamır. Düzəliş əvvəlkini dəyişmir, yeni revision-dur.

Server autosave vəziyyətləri: “Yoxlanılır…” → “Saxlanıldı”; xəta “Son dəyişiklik saxlanılmayıb. Yenidən yoxla”. Real gündəlik kontekst avtomatik yaranır, qonaq dəyişikliyi olmayan gün avtomatik overdue iş deyil.

## F09 — Public mənzil və uyğun tarixlər

Sahib switch-ləri: public səhifə / qiymət / uyğun tarixlər / xəritə — ilkin OFF. Məzmun preview-si nömrə və məxfi məlumatın olmamasını yoxlamaq üçündür. Menecer məzmunu redaktə edə bilər, switch və link rotation sahibindir.

Public sıra: qalereya → qısa imkanlar → təsvir → opsional qiymət → opsional uyğun tarixlər → qaydalar → opsional xəritə. Owner avatarı, telefon, email, realtor, guest və panel naviqasiyası yoxdur. Dolu/blok/təmir statusları və rəngləri yoxdur.

Date picker iki anlayış saxlayır: gecələməyə uyğun günlər və çıxış sərhədləri. Seçilən aralıqdakı bütün gecələr uyğun olmalıdır. Gecələməyə bağlı olmayan gün əvvəlki uyğun gecələrdən sonra çıxış ola bilər. Seçimdə gecə sayı, varsa server quote və “Rezervasiya yaratmır” izahı görünür. **Tarixləri kopyala** actual clipboard uğurundan sonra təsdiq göstərir. CTA telefon və payment deyil.

## F10 — Təlimat və QR

Redaktor: başlıq → public-general/safety və ya guest-private təsnifat → əsas dil → mətn/şəkil/video/vacib qeyd blokları → önizləmə → dərc. Tərcümələr ayrıca insan tərəfindən daxil edilir; hazır olmayan dil switch-də yoxdur.

QR səhifəsi: başlıq, görünən dil switch-i, qısa addımlar, toxunaraq açılan video. Public QR-də Wi-Fi şifrəsi və qapı kodu yoxdur. Safety content abunə bitdiyinə görə bağlanmır; məxfi guest linki öz expiry qaydasındadır. QR export-da sabit ünvan, quiet zone və çap skanı tələb olunur. Prototype safety nümunəsi faktiki sauna istismar qaydası kimi istifadə edilməməlidir.

## F11 — Menecer və səlahiyyət

Email → ev checkbox-ları → gündəlik/tam səviyyə → **Dəvət et**. Eyni icazəni seçilmiş evlərə bir dəfə tətbiq etmək mümkündür. Ayrı evdə dəyişmə detail-də edilir. Gündəlik səviyyə rezervasiya qiyməti və onun pul qeydlərini görür, ümumi mənfəət/export görmür. Tam səviyyə yalnız həmin evlər üçündür. Abunə, üzvlük, arxiv və visibility owner-da qalır.

Revoke təsdiqi: “Bu menecer seçilmiş evə girişini itirəcək. Digər sahiblərin evlərinə girişi dəyişməyəcək.” Owner və manager terminləri UI-da hesab seçimi yaratmır.

## F12 — Eve abunəsi

Sahib evləri seçir → aylıq 9,99 / illik 99,99 AZN → hər ev üçün yeni bitmə tarixi və yekun → **Payriff ilə ödə**. Bir checkout yalnız eyni sahibin evlərini əhatə edir. Menecerin başqasının evi üçün billing CTA-sı yoxdur.

Return ekranı “Ödəniş yoxlanılır”. Server verification sonrası aktiv tarix görünür. Browser success, refresh və təkrar klik ikinci period yaratmır. Provider pending halında “Yenidən ödə” əsas CTA deyil, **Statusu yoxla** göstərilir. Uğursuzluqda mövcud aktiv müddət dəyişmir.

## F13 — Ayarlar, operator və sistem vəziyyətləri

Profil ad/telefon opsional; çıxış və bütün cihazlardan çıxış ayrı. Dəstək forması qısa mövzu/mətn və opsional screenshot-dur; secret/real qonaq məlumatı daxil edilməməsi bildirilir.

Operator ayrıca səlahiyyət və yalnız iş üçün lazım olan billing/support məlumatı ilədir. Müdaxilə səbəbi olmadan sensitive action aktiv deyil; real payment status serverdən təsdiqlənir. İstifadəçi kimi səssiz impersonation yoxdur.

| Vəziyyət | UI davranışı |
|---|---|
| Loading | Sabit skeleton; təkrar submit yoxdur |
| Empty | Bir növbəti əməliyyat, saxta zero summary deyil |
| Error | Konkret sadə mətn, daxil edilmiş form saxlanır, retry |
| No access | Neytral izah, icazəsiz resurs barədə PII yoxdur |
| Offline | Yadda saxlanmayan dəyişiklik görünür; pul/booking uğuru yoxdur |
| Subscription expired | Mövcud data read-only, sahibə yeniləmə; safety QR istisnası |
| Token expired/revoked | Neytral səhifə; owner telefon və alternativ məxfi məlumat yoxdur |

## Qəbul və ölçmə

İcraçı hər axını R/AT ID-si, aktual OpenAPI operation və data state ilə bağlayır. Prototipdən vizual screenshot almaq real backend, permission və usability qəbulunu əvəz etmir. Hədəf: 360 px-də üfüqi səhifə sürüşməsi yoxdur, rezervasiya median 45 saniyə, problemsiz 4 otaq yoxlaması 90 saniyə, 5 yeni istifadəçidən ≥4-ü köməksiz tamamlayır. Faktiki nəticə protokolda ayrıca saxlanır.
