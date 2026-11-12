# EVE-009.1/.2 — mobil shell və AT29 qismən sübutu

Tarix: 2026-11-12, Asia/Baku. Branch: `feat/EVE-009-1-3-mobile-shell`; PR və merge commit aşağıdakı GitHub tarixçəsi ilə tamamlanır. Mühit: macOS 27.2, Node 24.5.0, pnpm 12.18.0, Next 16.4.6 production build, Google Chrome 157 headless, 320/360/390/430 CSS px, 740 px hündürlük. Sintetik və şəxsi məlumat yoxdur. Screenshot-lar [360 px əsas ekran](eve-009-360.png) və [360 px menyu](eve-009-menu-360.png)-dur.

| Paket / qəbul | Given → When → Then və faktiki nəticə |
|---|---|
| EVE-009.1 / R13, MOBILE-UX | Dizayn tokenləri və primitivlər `globals.css`-də 4/8/12/16/24/32 px, `#F8FAFC`/ağ/slate/teal, 12 px radius, 44 px minimum hədəf, sistem sans, görünən focus və reduced-motion ilə quruldu. `lucide-react` ikonları komponentdə işlədildi. Production build və typecheck exit 0. |
| EVE-009.2 / UI04–06, FLOW-SPEC ümumi UI | `/today`, `/calendar`, `/properties` linklərinə klik → düzgün route və `aria-current=page`; `+` → dörd adlandırılmış əməliyyat və “Əvvəl ev seçilməlidir” izahı; serverdə ev/giriş olmadığı üçün əməliyyatlar deaktivdir. Escape → menyu bağlanır, fokus `Əlavə et`-ə qayıdır. Heç bir server uğuru, ödəniş və ya rezervasiya iddiası yoxdur. |
| EVE-009.3 / AT29 qismən | Chrome headless 320/360/390/430 px-də hər ölçüdə əsas naviqasiya linkləri ən az 44×44 CSS px, `/today`, `/calendar`, `/properties` və açıq menyuda `documentElement` və `body` enləri viewport-u aşmır; offline mesajı və JS pageerror yoxlaması keçdi. Test `scripts/test-mobile-shell.mjs`: 60 assertion, exit 0. Bu, AT29-un tam qəbulu deyil. |

Müstəqil QA agenti ilk baxışda server sorğusu olmadan “iş/ev yoxdur” mətnini yanlış saydı; hər üç ekran neytral “yüklənməyib” mətninə dəyişdirildi. Offline mətn də dəyişiklik edildiyini uydurmur. Eyni agent təkrar statik baxışda bu tapıntıların bağlandığını təsdiqlədi; real cihaz və screen reader testini keçmiş saymadı. QA browser runtime testini özü icra etməyib.

Əmrlər: `pnpm install --frozen-lockfile` exit 0; `pnpm typecheck` exit 0; `pnpm build` exit 0; `EVE_BROWSER_EXECUTABLE=/Applications/Google Chrome.app/Contents/MacOS/Google Chrome pnpm test:ui` exit 0; `node scripts/docs-check.mjs` exit 0; `node scripts/verify-contracts.mjs` exit 0. CI eyni production build və bundled Chromium ilə test üçün yenilənib; PR/main CI nəticəsi merge-dən sonra faktiki run tarixçəsindən təsdiqlənir.

Sərhəd: bu üç route hazırda auth/backend-ə bağlı olmayan, şəxsi məlumat göstərməyən UI təməlidir. Kontekstli ev seçimi və dörd əməliyyatın real axınları EVE-008/011/014/016/017 mərhələlərindədir. SCREENS üçün permission-denied, real error/retry və tam loading integration, AT29 screen reader/real iPhone və Android/safe-area/keyboard audit hələ yoxdur; EVE-009.3 `in_progress` qalır. EVE-002.3 beş istifadəçi/real telefon gate-i də açıqdır. Schema/API/migration dəyişməyib; rollback bu UI commit-inin geri alınmasıdır.
