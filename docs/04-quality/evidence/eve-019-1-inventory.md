# EVE-019.1 — otaq, əşya və standart inventar şablonu

Status: **icra olunur; merged/Done deyil**. Branch: `feat/EVE-019-1-inventory`; parent issue: #27.

## Scope

Mövcud API/data müqaviləsinə uyğun property-scoped inventar oxusu, otaq və əşya yaratma, `standard_apartment` + `append_non_duplicate` şablon əməliyyatı əlavə edilir. Owner və inventory icazəli menecer yoxlanır; yazı üçün trial/active entitlement tələb olunur. Şablon tətbiqi eyni property üzrə transaction lock alır, mövcud uyğun otaq/əşyanı saxlayır və çatışmayanları əlavə edir. Standart siyahı prototip UI10-dan götürülür: dörd otaq, 11 əşya.

Inventory RPC-ləri bu scope-da inventory DTO və create/template contract-ı verir. D34 inventar mediası üçün ayrıca `private_inventory` classification və private bucket müəyyən edir. Yalnız eyni property/owner-a aid, validated və silinməmiş media item-ə bağlanır; DTO media ID-lərini qaytarır, URL/path qaytarmır. Real upload/finalize/proxy və hosted Storage davranışı açıq external gate-dir. Bu paket import preview, inventory copy, update/archive və UI/server route-u iddia etmir.

## İlkin yoxlama sübutu

- `node scripts/docs-check.mjs` — exit 0; 58 Markdown faylı, R01–16, AT01–36 və EVE-001–030 yoxlanıb.
- `node scripts/verify-contracts.mjs` — exit 0; 117 API əməliyyatı, 52 cədvəl, 255 field binding, 90 acyclic package, 16 trace row və 36 scenario yoxlanıb.
- `git diff --check` — exit 0.
- `node_modules/.bin/tsc --noEmit` — exit 0.
- Local PostgreSQL 14.18 sintetik DB-də 014–016 daxil bütün migration-lar hər biri ayrıca transaction-da, storage boundary, property-trial, inventory media, inventory foundation, RLS coverage və API allowlist smoke exit 0. Köhnə server üçün yalnız test mühitinin migration nüsxəsində PostgreSQL 16/17 role membership `SET/INHERIT` kataloq sintaksisi və role grant option-u uyğunlaşdırılıb; repo migration faylları dəyişməyib. Bu nəticə CI PostgreSQL 17 və Supabase local sübutu sayılmır.
- `node scripts/test-mobile-shell.mjs` lokal `/today` serveri `localhost:4177`-də olmadığı üçün `ERR_CONNECTION_REFUSED` ilə dayandı; bu paket UI komponenti təqdim etmir və mobil UI qəbulunu bağlamır.
- Müstəqil QA follow-up review D34-dən sonra P1/P2 tapmadı; scope yalnız local DB/RPC idi. PR #77 CI #43396662567-də docs və PG17 `sql_schema` keçdi, amma Supabase CLI migration owner transferində `api` schema CREATE grant çatmadığına görə `supabase_local` uğursuz oldu. Fix commit `43303b73dfdbc350af7c5391b93e9c82ba81c2f3` temporary CREATE grant + revoke əlavə etdi. Eyni commit üçün CI #43397700618 işləyir; Supabase local nəticəsi və PR merge gözlənilir.

## Qəbul ssenariləri

Smoke `standard_apartment` tətbiqində 4 otaq/11 əşyanı, ikinci tətbiqdə dublikat olmamasını və mövcud miqdarın saxlanmasını yoxlayır. Əlavə otaq/əşya DTO-su, eyni-property media binding və oxu DTO-su, başqa property/olmayan media rəddi, boş ad, naməlum şablon, draft subscription write rəddi, başqa tenantın oxu rəddi və authenticated base-table read rəddi local PG14 harness-də keçib. Bu, hosted Data API, Supabase local, real mobil UI və production nəticəsi deyil. D34 media migration-ları və bu genişləndirilmiş smoke üçün PostgreSQL 17 CI hələ tələb olunur.

İlk read-only QA review media DTO davranışında P1 müqavilə fərqini tapdı. D34 və `private_inventory` classification/bucket migration-ları həmin tapıntıya cavab olaraq eyni branch-də əlavə edildi. Follow-up QA P1/P2 tapmadı; sonra CI Supabase owner transfer privilege çatışmazlığını tapdı və fix commit-də bağlandı. Final Supabase local gate hələ açıqdır.
