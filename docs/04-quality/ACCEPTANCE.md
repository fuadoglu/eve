# Qəbul sınaqları və Definition of Done

Status: **bütün tətbiq testləri planlaşdırılıb, hələ icra edilməyib**. Hər sınaq üçün commit, mühit, fixture, addım, nəticə və artefakt yolu saxlanılır. Mock, integration, provider sandbox və real cihaz sübutları ayrıdır.

| ID | Ssenari və gözlənilən nəticə |
|---|---|
| AT01 | Yeni email → link → ilk ev; şifrə/profil məcburiyyəti yoxdur |
| AT02 | App bağla/aç sessiya qalır; logout sonrası private UI/cache görünmür; logout-all access TTL yoxlanır |
| AT03 | Expired/replay link, redirect injection, mail scanner, cross-device, rate limit və enumeration davranışı |
| AT04 | A/B owners, M menecer A1 daily/B1 full; yalnız verilmiş evlər görünür |
| AT05 | Membership revoke sonrakı request-i rədd edir, digər sahibin evi işləyir; IDOR/body owner dəyişmə bloklanır |
| AT06 | Daily rent entry-ni görür, tenant finance/export görmür; storage-da da eyni isolation |
| AT07 | Eyni gecələrə paralel booking/hold/block-dan yalnız biri uğurlu; DB race testi |
| AT08 | Checkout günü yeni checkin mümkündür; public valid departure gecə ilə qarışmır |
| AT09 | Expired hold cron işləməsə yeni booking-i bloklamır; retry dublikat yaratmır |
| AT10 | Tarix/ev dəyişmə və erkən çıxış price/occupancy/task ilə atomik; stale version 409; completed task itmir |
| AT11 | 300 AZN quote+100 receipt=200 debt; refund və artıq ödəniş görünür; integer rounding |
| AT12 | Deposit rent income deyil; zədə formu avtomatik tutulma yaratmır; refund original limit-i aşmır |
| AT13 | Realtor 100 collected/30 fee → 70 owner due; transfer yeni rent receipt yaratmır |
| AT14 | Proposed expense təsdiqsiz hesabatda xərclənmiş sayılmır; allocation cəmi və cross-owner qadağası |
| AT15 | WhatsApp GET/prefetch task accept etmir; installed/missing fallback; “göndərildi” yalan statusu yoxdur |
| AT16 | Accept/report/confirm vəziyyətləri; scoped expense; ikiqat completion cleaning dublikatı yaratmır |
| AT17 | Daily context boş gündə overdue deyil; eyni gün iki turnover ayrı qalır |
| AT18 | Verən/alan ayrı cavab; digərinin tamamlaması məcburi deyil; claimed name verified identity deyil |
| AT19 | Snapshot sonradan inventar dəyişsə sabit qalır; completed immutable, correction revision; server autosave truthful |
| AT20 | AZ/RU/EN published version və fallback; guide edit QR-ni dəyişmir; kamera ilə çap skanı |
| AT21 | Guest kodu safety QR/expired cache-də yoxdur; qonaq linki expiry və revoke media-nı da bağlayır |
| AT22 | Public initial OFF, dates/price/map OFF; owner açır, daily manager visibility dəyişə bilmir |
| AT23 | Public HTML/JSON/RSC/OG media metadata-da telefon/guest/block reason/owner ID yoxdur |
| AT24 | noindex headers/meta, sitemap exclusion; unavailable vahid neytral; stale quote refresh rezervasiya yaratmır |
| AT25 | Paralel first property create yalnız bir trial verir; delete/archive yeni trial vermir |
| AT26 | Forged success redirect/webhook order-u aktiv etmir; amount/currency/order/merchant yoxlanır |
| AT27 | Duplicate/out-of-order paid event entitlement-i bir dəfə uzadır; expired order reconcile; partial provider failure |
| AT28 | Ay sonu/leap year/early renewal/trial purchase/plan switch/expiry read-only; safety QR açıq qalır |
| AT29 | 320/360/390/430 px, keyboard safe-area, 44 px target, focus/reader/error; horizontal page scroll yoxdur |
| AT30 | Təkrar submit, offline/reconnect, slow API həqiqi status verir; daxil edilən mətn itmir |
| AT31 | Public mobil lab və panel p95 metrikası PRD büdcəsinə qarşı; real trafiksiz p75 iddiası yoxdur |
| AT32 | Audit secret scan; CSV formula injection; export yalnız icazəli scope; operator reason audit |
| AT33 | DB + private media staging restore, qarşılıqlı FK və token revoke yoxlanılır |
| AT34 | Deploy failure, feature flag, migration forward-fix/rollback rehearsal; monitoring alert real trigger |
| AT35 | Import preview səhv sətir göstərir; confirm hash/idempotency; inventar şablonundan ilk setup |
| AT36 | Outbox retry/dedupe, quiet hours, timezone/catch-up, failed push/email “Bu gün”ü gizlətmir |

## Test qatları

- Unit: monetary math, month anchor, commission, state transition; implementation-ı təkrarlayan mənasız test yox.
- DB integration/pgTAP: RLS, composite FK, occupancy race, immutable data, transactional writes.
- API integration: auth/origin/version/idempotency, public projection, upload scope.
- Playwright E2E: login test flow, əsas mobil əməliyyat, task/inspection, expiry.
- Provider sandbox: Payriff status/webhook/reconcile və SMTP real delivery.
- Real cihaz: iPhone Safari/PWA və Android Chrome, QR camera, WhatsApp, mikrofon fallback.

## Təmiz checkout müqaviləsi

M1 package scripts yaradanda və README-də təsdiqləyəndə: pnpm install --frozen-lockfile; pnpm typecheck; pnpm test; pnpm test:db; pnpm test:e2e; pnpm build; pnpm docs:check. Bunlar hazırda işləyən əmrlər kimi təqdim edilmir. Lint yalnız repo CI siyasətində tələb ediləndə.

## Definition of Done

Tələb və test ID-si bağlanıb; mobile/error/empty/loading vəziyyətləri var; permission/RLS/storage mənfi testi var; schema/API uyğun; secrets yoxdur; docs yenilənib; CI sübutu actual commit-ə aiddir; müstəqil review bitib; P0/P1 yoxdur. Migration geri dönüş planı və sandbox nəticəsi aidiyyəti olduqda əlavədir.

Skipped yoxlama “passed” deyil. Environment/provider yoxdursa task Blocked və ya partial qalır. Screenshot təhlükəsizlik testinin əvəzi deyil. Branch-də işləməsi merged main-də də yoxlanmadan milestone Done olmur.
