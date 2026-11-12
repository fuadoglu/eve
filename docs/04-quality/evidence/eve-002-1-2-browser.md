# EVE-002.1/.2 — mobil prototip sübutu

Tarix: 2026-11-12, Asia/Baku. Brauzer sınağının əsas commit-i `7f624e8`; forma atributu düzəlişinin inteqrasiya commit-i `1fd9599` (`docs/EVE-002-1-2-integration`). Mühit: macOS 27.2, Google Chrome 157.0.8103.38, lokal `python3 -m http.server 4174 --bind 127.0.0.1`, `http://127.0.0.1:4174/docs/02-design/prototype.html`. Real telefon və real istifadəçi deyil. Yalnız sintetik demo məlumatı işlədildi.

## Paket və müqavilə xəritəsi

| Paket | Normativ mənbə və artefakt | Faktiki müsbət və mənfi yoxlama |
|---|---|---|
| EVE-002.1 — mobil wireframe və komponentlər | `MOBILE-UX.md` üç əsas naviqasiya, bir kontekstli `+`, 360 px, 44 px hədəf; `SCREENS.md` UI01–19; `prototype.html` mobil shell, kart, forma, dialog, bottom nav və altı vəziyyət | Chrome 360 CSS px-də UI01–19 × normal/empty/loading/error/noaccess/offline = 114 render; hər dəfə `document.documentElement.scrollWidth <= innerWidth`. Ölçülən `innerWidth=360`, `scrollWidth=360`. Kontekstli `+` dialogu açıldı; Escape bağladı və fokus `Əlavə et` düyməsinə qayıtdı. |
| EVE-002.2 — kliklənən əsas axınlar | `FLOW-SPEC.md` F01, F03, F05, F07–F10; `PROTOTYPE.md` UI axınları; `scripts/test-prototype.mjs` | Chrome-da `+` → Rezervasiya formu və Tab→Enter ilə Təqvim keçidi işlədi. Yaddaşdaxili smoke 71 assertion ilə email ekran keçidi, yanlış tarixdə formanı saxlayan xəta, rent/depozit/refund ayrılığı, public çıxış sərhədi və blok səbəbinin gizliliyi, AZ/RU/EN, yoxlanmamış inventarın completion rəddi, task accept/report/confirm ayrılığını keçdi. Bu əməliyyatlar real server uğuru kimi təqdim edilmir. |

Prototip forma sahələri və nümunə default-ları `FLOW-SPEC.md` ilə müqayisə edildi: email; rezervasiyada ev konteksti, giriş/çıxış, qonaq adı, AZN qiymət və opsional pul; pul növü kirayə/depozit; task və inventar statusları. `prototype.html` HTML `name`-ləri demo formun daxili adlarıdır, OpenAPI payload-u deyil. OpenAPI/DB enum və limitləri dəyişdirilməyib; `verify-contracts.mjs` onların 255 binding uyğunluğunu yoxladı.

## Brauzer addımları və nəticə

1. Chrome DevTools Responsive Width `360` seçildi. Console-da `innerWidth`, `document.documentElement.scrollWidth` və `document.body.scrollWidth` hamısı `360` qaytardı.
2. UI04-dən aşağı naviqasiyanın Təqvim düyməsi UI05-i açdı. Əlavə et → Rezervasiya formu açıldı; məcburi sahələr label-lə göründü. Escape dialogu bağladı və fokus Əlavə et-ə qayıtdı. Ardınca Tab fokusunu Bu gün düyməsinə, növbəti Tab və Enter Təqvimə keçirdi.
3. Real Chrome runtime-ında 19 ekranın hər biri altı demo vəziyyətində render edildi. `114` ölçmənin heç birində səhifə səviyyəsində üfüqi overflow yox idi (`overflow=0`). Bu, hər komponentin bütün 320–430 px kombinasiyalarını və ya real cihaz safe-area davranışını təsdiqləmir.
4. Chrome Issues paneli iki form-control `id/name` və bir autocomplete tövsiyəsi göstərdi. Təqvim/owner filter select-lərinə, manager-property və expense-paid checkbox-larına `name`, manager email input-una `name` və `autocomplete=email` əlavə edildi (`1fd9599`). Reload sonrası Issues paneli `0 page errors, 0 breaking changes, 0 possible improvements` göstərdi; 114 genişlik yoxlaması yenidən `overflow=0` verdi.

## Əmr nəticələri

| Əmr | Nəticə |
|---|---|
| `node scripts/test-prototype.mjs` | exit 0; 71 assertion, 19 ekran, 6 vəziyyət, 6 forma |
| `node scripts/docs-check.mjs` | exit 0; 46 Markdown faylı |
| `node scripts/verify-contracts.mjs` | exit 0; 117 operation, 52 cədvəl, 255 field binding, 90 paket |
| `/tmp/eve-docs-venv/bin/python scripts/validate-schemas.py` | exit 0; 207 schema, 12 müsbət və 20 mənfi nümunə |
| `git diff --check` | exit 0 |

## Müstəqil baxış

İnteqrator müəllifin brauzer addımlarını ayrıca Chrome sessiyasında, 360 CSS px-də təkrarladı: `innerWidth`, `documentElement.scrollWidth` və `body.scrollWidth` hər biri 360 idi; UI04 → Təqvim UI05 keçdi; Əlavə et → Rezervasiya formu açıldı; Escape formanı bağladı və fokus Əlavə et düyməsinə qayıtdı. Formun məcburi sahə label-ləri accessibility ağacında göründü. Bu baxış 114 kombinasiyalı ölçməni müstəqil təkrarlamır.

## Sərhəd və açıq qapılar

Bu sübut **sənəd prototipi** üçündür. Chrome responsive emulyasiyası real telefon, screen reader, 5 iştirakçılı köməksiz usability, provider, API, RLS, Storage və production tətbiq testini əvəz etmir. EVE-002.3/EXT09 açıq qalır; EVE-009 production UI və AT29 tam a11y/320–430 px qapısı ayrıca icra olunur. Prototipdəki DEMO əməliyyatları serverə yazmır. PR/main CI nəticəsi merge-dən sonra GitHub tarixçəsində ayrıca görünür.
