# İlkin limitlər və dəyişən ayarlar

Maşın mənbəyi: [configuration.json](configuration.json). Qiymətlər və sınaq istifadəçi qərarıdır; media, rate limit və keçid müddətləri versiyalanmış ilkin texniki seçimlərdir. Bunlar istifadəçi üçün uzun ayar forması yaratmır.

## Dəyişiklik səlahiyyəti

| Səviyyə | Nə dəyişir? | Necə? |
|---|---|---|
| Məhsul sahibi | Qiymət, sınaq, əsas paket sərhədi | Qərar reyestri, təsir analizi və release; mövcud ödənilmiş hüquq səssiz azaldılmır |
| Texniki operator | Kvota, batch, rate limit, token TTL | Auditli server config; validator və regression; provider uyğunluğu yoxlanılır |
| Ev sahibi | Giriş/çıxış saatı, public seçimlər, evin qaydaları | Ev ayarları; başqa sahibin ayarına təsir etmir |
| İstifadəçi | Bildiriş seçimləri və sakit saatlar | Öz ayarları; əsas sistem təhlükəsizliyini söndürmür |

## Dəqiq vahidlər

Fayl kvotalarında 1 MiB = 1 048 576 byte. Video müddəti server metadata-sından yoxlanır; client iddiası kifayət deyil. Qiymət integer qəpik, göstərilən AZN 100-ə bölünür. Trial 168 saat; aylıq/illik plan calendar period-dur, 30/365 gün kimi sabitlənmir. Gecələmə günləri evin local_date-i, server vaxtı UTC-dir.

## Limitə çatanda UX

Fayl seçilməzdən ölçü həddi görünür; server faktiki ölçünü də yoxlayır. Xəta: “Bu video 100 MiB-dan böyükdür. Daha qısa video seçin və ya video keçidi əlavə edin.” Kvota doludursa mövcud məzmun silinmir; yeni yükləmə rədd edilir, sahibə istifadə olunan həcm və təhlükəsiz silinə bilən fayllar göstərilir. Aktiv təhlükəsizlik təlimatının faylı təsadüfən silinmir; istinad yoxlaması var.

Rate limit: retry vaxtı göstərilir, email mövcudluğu açıqlanmır. Keçidin müddəti bitəndə digər şəxsin nömrəsi yox, “Yeni keçid istəyin” neytral mesajı görünür. Bildiriş icazəsi yoxdursa əsas iş “Bu gün” ekranında qalır.

## Üstünlük və versiyalama

Config > env ad-hoc override deyil: hər mühitdə hansı versiyanın işlədiyi məlum olmalıdır. Server qiyməti authoritative-dir; browser qiymət/küota/TTL dəyişdirə bilməz. Provider planı seçilmiş session limitini dəstəkləmirsə bu xarici gate-dir, faktiki ayar sübutu olmadan aktiv sayılmır.

Hüquqi retention müddətləri bu texniki cədvəldən çıxarılmır. Mühasibat və şəxsi məlumatların saxlama/silinmə qaydası hüquqi təsdiq tələb edir; deployment qapısında ayrıca yoxlanır.
