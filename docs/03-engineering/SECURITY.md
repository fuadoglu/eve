# Təhlükəsizlik və səlahiyyət modeli

## Matris

| Əməliyyat | Sahib | Daily manager | Full manager | Scoped link | Public |
|---|---|---|---|---|---|
| Həvalə edilmiş evin rezervasiya/qiymət/qonaq pulu | Bəli | Bəli | Bəli | Xeyr | Xeyr |
| Ümumi gəlir, xərc, mənfəət və maliyyə export | Bəli | Xeyr | Yalnız təyinli ev | Xeyr | Xeyr |
| Xərc təqdim etmək | Bəli | Bəli | Bəli | Öz işində | Xeyr |
| Xərc təsdiqi | Bəli | Xeyr | Bəli | Xeyr | Xeyr |
| Task və daimi inventar idarəsi | Bəli | Bəli | Bəli | Yalnız öz forması | Xeyr |
| Guide/public məzmun redaktəsi | Bəli | Bəli | Bəli | Xeyr | Xeyr |
| Public visibility və link rotation | Bəli | Xeyr | Xeyr | Xeyr | Xeyr |
| Üzvlük, abunə, arxiv, owner settings | Bəli | Xeyr | Xeyr | Xeyr | Xeyr |
| Kontaktlar | Öz tenant-ı | Təyinli evə lazım olan | Təyinli evə lazım olan | Öz işinin məhdud məlumatı | Xeyr |
| Dərc olunmuş təqdimat | Bəli | Bəli | Bəli | Ayrı keçid | Bəli |

Gündəlik menecerin rezervasiya pulu görməsi tenant üzrə mənfəəti görməsi demək deyil. Full bütün sahiblərin hesabatı deyil, verilmiş evlərdir.

## Server və DB

Hər request current user + property + capability + active entitlement yoxlayır; read-only istisnalar expiry qaydasına uyğun. Membership DB-dən gəlir; access JWT-də köhnə rol authoritative deyil. RLS bütün tenant cədvəllərində aktiv və mənfi testlidir. Elevated service key yalnız serverdə, minimal əməliyyat və explicit tenant yoxlaması ilə. Bypass edən admin query user route-da istifadə edilmir.

Cross-tenant FK, composite constraint və server derive birlikdədir. UI gizlətməsi security deyil. İcazəsiz ID-lərə neytral 404 cavabı object enumeration-u azaldır.

## Auth və sessiya

Password sign-in/sign-up və set-password UI/API yoxdur; provider password grant konfiqurasiyası imkan daxilində söndürülür və endpoint negative test olunur. Magic link qısaömürlü/birdəfəlik, sərt redirect allowlist; open redirect yoxdur. İstifadəçi enumeration-a neytral cavab.

Mail scanner/prefetch tokeni istehlak etməsin deyə confirm landing və explicit click axını yoxlanılır. PKCE-nin eyni cihaz/brauzer məhdudiyyəti ayrıca qiymətləndirilir; “hər cihazda işləyir” təsdiqsiz iddia edilmir.

Session server-side cookie qoruması və providerin dəstəklədiyi refresh mexanizmi ilə qurulur; JS əlçatan token varsa XSS təsiri ayrıca nəzərə alınır, HttpOnly olmayan cookie HttpOnly kimi sənədləşdirilmir. Secure/SameSite, CSRF/origin, rotation və logout test edilir. Long session default-un sonsuz təhlükəsiz olduğu iddia edilmir. Üzvlük revoke növbəti request-də tətbiq edilir; logout-all mövcud access token TTL davranışı ilə sınaqdan keçirilir.

## Keçid və məzmun

256-bit random bearer token hash saxlanılır, expiry/revoke resurs və media scope-da yoxlanır. GET-də side effect yoxdur. Private token route no-referrer, no-store, üçüncü tərəf tracker yoxdur. Token analytics/log/error context-ə düşmür. Token landing-də POST /api/v1/link-session ilə doğrulanıb dar scope cookie-sinə dəyişdirilir; bu məcburi bootstrap URL təmizlənməsi və CSRF ilə eyni scope-u qoruyur, domain state-ni dəyişmir.

Public kateqoriyalı, guest-private, receipt, inspection və task media D33-də ayrı private bucket-lərdədir; Storage public download açılmır. MIME magic-byte, ölçü, extension və quota yoxlanılır; HTML/JS/SVG upload aktiv məzmun kimi bloklanır və ya təhlükəsiz sanitization tələb edir. QR generated SVG upload deyil. EXIF public fotolardan təmizlənir. Arbitrary remote URL server fetch-i SSRF-ə çevrilmir; video allowlist.

## Audit və privacy

Audit: actor, operation, resource, request_id, redacted diff. Guest email linki, token, qapı kodu, card data və tam provider payload loglanmır. DB backup private media backup-ını avtomatik əvəz etmir; ayrıca restore planı var.

Operator giriş minimal və allowlisted server authorization-dır. İstifadəçi kimi səssiz impersonation yoxdur. Həssas müdaxilə səbəb və audit tələb edir; payment müddəti manual düzəldilirsə original verification/event saxlanır.

Privacy terms, data retention və silinmə siyasəti hüquqi təsdiqə açıqdır. Hesab silinməsi arxivlə qarışdırılmır. Production üçün təsdiq olmadığı halda implementasiya bu mətnləri qanuni rəy kimi təqdim etmir.

## Məcburi hücum testləri

IDOR, owner/property dəyişmə, manager revoke, daily→full escalation, storage path traversal, token replay, CSRF, XSS safe blocks, SSRF remote media, CSV formula injection, upload abuse, webhook forgery/replay, enumeration/rate-limit, cache cross-user və audit secret scan. Sübutlar ACCEPTANCE və RED-TEAM ID-lərinə bağlanır.

## DB grant sərhədi

[ACCESS-BOUNDARY](ACCESS-BOUNDARY.md) normativdir: base table authenticated/anon üçün açılmır; yalnız safe typed RPC. Private scoped media signed Storage URL deyil, hər request-də revoke/expiry/cari placement yoxlayan proxy-dən verilir. İstifadəçinin əvvəl yüklədiyi baytları geri almaq vədi yoxdur.
