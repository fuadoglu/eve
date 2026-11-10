# Eve — kliklənən mobil UX prototipi

**Artefakt:** [prototype.html](prototype.html). Bu, məhsulun davranışını və görünüşünü komanda ilə razılaşdırmaq üçün hazırlanmış təkfayllı sənəd prototipidir. Production tətbiqi, backend, auth sessiyası, WhatsApp göndərişi və Payriff inteqrasiyası deyil.

## Açmaq

Faylı müasir brauzerdə açın. İstəyə görə repository kökündə `python -m http.server 4173` başladın və `http://localhost:4173/docs/02-design/prototype.html` ünvanını açın. Faylın özü xarici şrift, kitabxana, şəkil və API sorğusu tələb etmir. Mənbədə yalnız saxta nümunələr var; real qonaq və hesab məlumatı əlavə etməyin.

Yuxarıdakı **Ekrana keç** seçimi ekranlar arasında keçid üçündür; production UI hissəsi deyil. **Vəziyyəti göstər** seçimi normal, boş, loading, xəta, icazəsiz və offline təqdimatları nümayiş etdirir. **Demonu sıfırla** yalnız açıq səhifənin yaddaşını sıfırlayır.

## Nə real şəkildə kliklənir?

- Üç əsas naviqasiya: Bu gün, Təqvim, Mənzillər.
- Kontekstli `+`: rezervasiya, pul qeydi, xərc və tapşırıq üçün qısa forma.
- Email → emaili yoxla → təsdiq → panel ekran keçidi; heç bir email göndərilmir.
- Rezervasiya formasında məcburi sahə və tarix ardıcıllığının nümunə yoxlaması.
- Kirayə pulunun nümunə alınması/qaytarılması: yalnız səhifədəki saxta məbləğ dəyişir.
- Rezervasiyada giriş → çıxış; işçidə qəbul → tamamlandığını bildir → sahibdə təsdiq statuslarının yaddaşdaxili təqdimatı.
- İnventarda otaq siyahısı → “Hamısı qaydasındadır” / “Problem var”; çatışmayan say və yoxlanmama səbəbi; tamamlanmış nümunənin kilidlənməsi.
- Public səhifədə yalnız ardıcıl uyğun gecələrin seçimi; çıxış sərhədi gecələməyə uyğun olmayan günə də düşə bilər. Tarix seçimi rezervasiya yaratmır.
- Tarix mətnini kopyalama: Clipboard API faktiki uğurlu olduqda “kopyalandı” bildirişi; dəstək yoxdursa seçilə bilən mətn pəncərəsi.
- Sauna təlimatının AZ/RU/EN məzmun versiyaları.

## Ekran əhatəsi

| Ekran | Prototipdə olan | Backend/sonrakı icraya qalan |
|---|---|---|
| UI01 Giriş | Email forması, browser email validasiyası | Rate limit, SMTP, həqiqi magic link |
| UI02 Emaili yoxla | Ünvan, düzəliş, nümunə keçid | 60 saniyəlik real resend və delivery |
| UI03 Təsdiq | Açıq istifadəçi toxunuşu | Provider token verification və refresh session |
| UI04 Bu gün | Giriş/çıxış, iş, pul kartları | Canlı məlumat və yetkiyə uyğun projection |
| UI05 Təqvim | Bir ev üzrə ay və agenda keçidi | Real date query, concurrency və çox ev süzgəci |
| UI06 Mənzillər | İki ev, sahib/menecer konteksti | Canlı sahib filtri və pagination |
| UI07 Mənzil | Məlumat və alt bölmə keçidləri | Redaktə, readiness və entitlement |
| UI08 Rezervasiya | Qiymət/balance, pul forması, statuslar | Real quote, depozit/realtor ledger və atomik write |
| UI09 Task | İşin detalları, paylaşım izahı, sahib təsdiqi | Token yaratma, WhatsApp deep link, audit |
| UI10 İnventar | Otaq/əşya/say, şablon görünüşü | CRUD, import və icazəli kopyalama |
| UI11 Evi yoxla | Ayrı otaq cavabları, problem və completion | Server autosave, snapshot, tərəf/revision izolyasiyası |
| UI12 İşçi | Qəbul/bildirmə, yoxlama və xərc forması | Scoped server state və expiry |
| UI13 Guide redaktoru | Başlıq, təsnifat, mətn, önizləmə | Media, version/publish və QR export |
| UI14 Public | Təqdimat, uyğun tarix, qiymət, qayda | Safe DTO, provider/media, cache invalidation |
| UI15 QR guide | Üç dil və addımlar | Modelə uyğun həqiqi safety content, media playback |
| UI16 Menecer | Email, icazə və ev seçimi | Real invite, revoke və property memberships |
| UI17 Abunə | Plan/məbləğ və aydın demo CTA | Payriff checkout, verification və period hesabı |
| UI18 Ayarlar | Profil və naviqasiya | Profile write, logout-all, support və export |
| UI19 Operator | Pending order, reason və araşdırma nümunəsi | Operator auth, provider lookup və audit |

Prototipdəki düymə backend əməliyyatı edə bilmirsə, açıq **DEMO** bildirişi göstərir. “Göndərildi”, “Serverdə saxlanıldı”, “Ödəniş uğurludur” kimi həqiqətə uyğun olmayan nəticə yoxdur. Göstərilən statuslar və məbləğlər yalnız səhifə yaddaşındadır; refresh-də silinir. `localStorage`, cookie və service worker yaradılmır.

## UX yoxlama ssenariləri

1. 360 px enində emaili yazın, nümunə keçiddən panelə daxil olun. Şifrə və məcburi profil mərhələsi olmamalıdır.
2. `+` → rezervasiya; çıxışı girişdən əvvəl seçin. Sahə məlumatları itirilmədən xəta görünməlidir. Sonra düzgün aralıqla tamamlayın.
3. Rezervasiyada `Pul al` ilə 50 AZN rent əlavə edin. Nümunə qalıq 150 AZN olmalıdır. Depozit seçimi rent balansını artırmamalıdır.
4. İşçi ekranında işi qəbul edin və tamamlandığını bildirin; sahib task ekranında təsdiqləyin. Qəbul etmədən bildirmə və bildirişsiz təsdiq aydın xəbərdarlıq verməlidir.
5. İnventar yoxlamasını dərhal bitirməyə çalışın. Heç bir otaq əvvəlcədən təsdiqlənmiş olmamalıdır. Bir otaqda problem, digərində yoxlanmama səbəbi qeyd edin; digərlərini təsdiqləyin.
6. Public səhifədə 11–14 noyabrı seçin: 11/12/13 gecələri uyğun, 14 yalnız çıxış sərhədi ola bilər. Əlçatmaz tarixdə dolu/blok səbəbi görünməməlidir.
7. Sauna səhifəsində dilləri dəyişin. Ümumi QR səhifəsində qapı kodu, Wi-Fi şifrəsi, owner avatarı və panel naviqasiyası olmamalıdır.
8. `Vəziyyəti göstər` seçimlərinin hər birini yoxlayın. Offline halda formun submit-i uğur göstərməməlidir.
9. Klaviatura ilə naviqasiya, dialog açma/bağlama, Escape və görünən focus-u yoxlayın. Form label-ları input-lara bağlıdır.

## Yoxlama sərhədi

JS sintaksisi və statik DOM müqavilələri local runtime-da yoxlanılır. Brauzer və screenshot QA inteqrator tərəfindən aparılır; həmin nəticə ayrıca sübut kimi qeydə alınmalıdır. Real istifadəçi ilə ≥80% köməksiz tamamlama, həqiqi cihaz, QR çap skanı, screen reader və performans hədəfləri bu prototip hazırlanması ilə keçilmiş sayılmır.

## Dəyişiklik qaydası

Bu prototip tələbləri genişləndirmir. Normativ davranış [FLOW-SPEC](FLOW-SPEC.md), [ekran müqavilələri](SCREENS.md) və məhsul sənədləridir. UI-da yeni addım yalnız əsas işə xidmət etdiyi halda qəbul edilir. Son məhsulda demo idarəetmə paneli və saxta məlumatlar olmamalıdır.
