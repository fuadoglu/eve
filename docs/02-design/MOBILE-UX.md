# Mobile-first UX və dizayn sistemi

R13. Bu sənəd vizual prototipi əvəz etmir; prototip və tətbiqin qəbul müqaviləsidir.

## İnformasiya arxitekturası

Aşağı sabit naviqasiya: **Bu gün · Təqvim · Mənzillər**. Bir kontekstli + düyməsi: rezervasiya, pul qeydi, xərc, tapşırıq. Profil/menecer/abunə/dəstək əlavə menyudadır. Mənzil daxilində alt bölmələr secondary naviqasiyadır; beşinci əsas tab yaradılmır.

Bir hesabın bütün icazəli evləri görünür. Ev sətrində sahibin adı, adlar eyni olsa cover/ərazi var. Sahibə görə filtr saxlanıla bilər, maliyyə yekunlarında sahib sərhədi itmir. “Aktiv workspace” dəyişərək başqa evləri gizlətmək tələb edilmir.

## Vizual istiqamət

İşıqlı, sakit, məzmun yönümlü interfeys. Brend adı evo/daygo deyil, yalnız **eve / Eve**. Ağ səth, slate mətn, bir əsas teal aksent; dekorativ gradient və böyük dashboard kart yığını yoxdur.

| Token | İlkin qərar |
|---|---|
| Səhifə fonu | #F8FAFC |
| Səth | #FFFFFF |
| Əsas mətn | #0F172A |
| İkinci mətn | #475569 |
| Əsas düymə | #0F766E, ağ mətn |
| Diqqət / xəta | amber / red; həmişə ikon və mətnlə |
| Ölçü şkalası | 4, 8, 12, 16, 24, 32 px |
| Əsas mətn | 16 px; input ən az 16 px |
| Toxunma sahəsi | Ən az 44×44 CSS px, əsas CTA 48 px |
| Künc | 12 px; komponentdən komponentə təsadüfi dəyişmir |
| İkonlar | Lucide; adlandırılmış düymə ilə |
| Şrift | Azərbaycan hərflərini dəstəkləyən self-hosted/system sans |

WCAG 2.2 AA kontrast və keyboard audit faktiki aparılmalıdır; bu rəng cədvəli sertifikat deyil. Focus ring, label, aria error, screen reader status və reduced motion dəstəklənir.

## Responsive davranış

- 360–430 px əsas hədəf; 320 px-də məzmun itmir. iPhone və Android real cihaz testi.
- 768 px-dən genişdə forma iki sütuna keçə bilər; mobil sıra saxlanır.
- Desktop-da sidebar və geniş təqvim mümkündür, başqa məhsul axını yaratmır.
- Səhifə səviyyəsində horizontal scroll yoxdur. Çox-ev təqvimi mobil agenda və bir-ev aylıq görünüşlə əvəz edilir; geniş grid tək həll deyil.
- Klaviatura CTA-nı örtmür. Sticky düymə bottom nav/safe-area ilə toqquşmur.
- Pul input-u decimal keypad, telefon tel input, tarix lokal oxunaqlı formatda.
- Drag yeganə idarəetmə üsulu deyil; keyboard və toxunma alternativi var.

## Davranış

Bir ekranda bir əsas CTA. “Göndərildi”, “Tamamlandı”, “Ödənildi” yalnız həqiqi hadisədən sonra. WhatsApp actual delivery sübutu deyil.

Form kontekstdən evi/rezervasiyanı doldurur və göstərir. Opsional sahələr “Əlavə məlumat” altında. Date picker gecə ilə çıxış sərhədini fərqləndirir.

Loading skeleton yeri sabit saxlayır. Yavaş şəbəkədə submit disabled + mətn; təkrar sorğu idempotentdir. Pul/rezervasiya server təsdiqindən əvvəl uğur sayılmır. Sadə filter kimi aşağı riskli UI optimistic ola bilər.

Xətada məlumat itməsin, xəta sahəyə yaxın olsun. Toast tək xəta izahı deyil. Offline badge + “Yadda saxlanılmayıb”; autosave server təsdiqi yoxdursa saved yazılmır. Şəxsi draft persistent localStorage-da saxlanmır.

Boş ekran konkret növbəti işi göstərir: “İlk evini əlavə et”, “Bu gün görüləcək iş yoxdur”. Expired token məxfi kontekst açıqlamayan neytral mətn göstərir.

## UX qəbul planı

5 ilk istifadəçi: 2 sahib, 1 menecer, 2 müxtəlif rəqəmsal bacarıqlı icraçı. Real telefonda izahsız giriş, rezervasiya/beh, task paylaşma, ev yoxlama. Ölçü: completion, median vaxt, səhv, kömək sayı. Hədəf ≥80% köməksiz uğur. Screenshot usability test əvəzi deyil.

PRD LCP/INP/CLS hədəfləri ilə ölçülür. Lab cihaz/network profili və commit yazılır. RUM PII-siz və məxfilik qaydasına uyğun olur.
