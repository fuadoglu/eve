# DB/API giriş sərhədi

## Vahid icra qərarı

Mixed-sensitivity base cədvəllər üçün alternativlər siyahısı yox, bir konkret qayda seçilir: **base cədvəllər `app_private` sxemindədir; browser və anonim istifadəçi onları birbaşa oxumur/yazmır.** Supabase Data API-da yalnız təsdiqlənmiş `api` sxemi və onun allowlist RPC-ləri açılır. Bu yeni məhsul modulu deyil, eyni sadə UX-in arxa plan müdafiəsidir.

## Rollar və grant

| Rol | Hüquq |
|---|---|
| Migration owner | Cədvəl/schema yaradır; tətbiq request-lərində istifadə edilmir |
| `app_executor` | NOLOGIN, NOBYPASSRLS, base-table sahibi deyil; lazım olan SELECT/INSERT/UPDATE grant, DELETE default yoxdur |
| `authenticated` | `api` sxeminə USAGE və explicit allowlist funksiyalara EXECUTE; base schema/table grant yoxdur |
| `anon` | Base data və user RPC üçün grant yoxdur; public trafik Next.js public endpoint-indən keçir |
| Server billing/job client | Yalnız həmin server əməliyyatının explicit function grant-ı və payload yoxlaması; brauzerə credential verilmir |

Domain cədvəllərdə ENABLE/FORCE RLS. RLS policy-ləri `app_executor` və Data API-nin yoxlanmış JWT-sindən `request.jwt.claim.sub`/`request.jwt.claims` oxuyan `app_private.current_actor_id()` üzrə cari membership yoxlayır. Hosted Supabase custom role-a `auth` sxemi USAGE vermədiyi üçün executor `auth.uid()` çağırmır; helper eyni doğrulanmış request actor-unu qaytarır. SQL funksiyasının owner-i login olmayan, table owner olmayan executor-dur; SECURITY DEFINER + sabit search_path + schema-qualified adlar. User-dən actor/owner/role parametrinə etibar edilmir. Public execute grant default-u revoke edilir, yalnız explicit funksiyalara qaytarılır. Birbaşa DB bağlantısında request JWT setting-inə user giriş verilmir; real Data API davranışı ayrıca sandbox testidir.

Bu arxitekturada security-invoker view ilə base SELECT grant-ını birlikdə təsadüfən açmaq yoxdur. Frontend serverə eyni session-la müraciət edir; PostgREST RPC birbaşa çağırılsa da eyni capability, column, state və entitlement qaydaları funksiyada tətbiq olunur.

## Sütun və əməliyyat sərhədi

Owner ID immutable-dir. Arxiv/public visibility/manager permission yalnız owner prosedurundadır; adi property patch bunları qəbul etmir. Daily manager üçün contact private_note, başqa ev allocation-u, subscription payment metadata və tenant finance RPC cavabından çıxarılır. RLS sətri açsa belə funksiya safe DTO qaytarır.

Public və tokenli Next.js route user funksiyasını yüksək səlahiyyətlə ümumi `SELECT *` etməyə çevirmir. Ayrı dar public/token projection funksiyası slug/token hash və expiry/public status/cari placement yoxlaması aparır. Dynamic SQL ilə table/column adı request-dən alınmır.

## İcra üçün mənfi test

Authenticated user JWT-si ilə birbaşa `/rest/v1/properties`, private schema profile header, RPC-də owner override, daily manager financial export və server-only billing function çağırışı rədd edilməlidir. Eyni user üçün allowlist reservation RPC-si qanuni scope-da işləməlidir. Membership ləğvindən sonra əvvəlki sessiya yenidən hüquq yaratmır. AT05/AT06 buna görə birbaşa Data API sorğularını da əhatə edir.

Bu fayl grant/RLS miqrasiyasının özü deyil. M1-də grant list, function owner, search_path, policy və test nəticəsi təqdim edilmədən giriş modeli tamamlanmış sayılmır.
