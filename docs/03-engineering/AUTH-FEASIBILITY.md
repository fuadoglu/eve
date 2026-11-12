# EVE-003.1 — email giriş feasibility

Yoxlama tarixi: 2026-11-12 (Asia/Baku). Bu, R01 və AT01–03 üçün **rəsmi sənəd əsasında feasibility** nəticəsidir; işləyən auth route-u, SMTP delivery, cross-device və scanner sandbox testi deyil. Normativ məhsul sərhədi [D03/D04](../01-product/DECISIONS.md), [SECURITY](SECURITY.md) və [INTEGRATIONS](INTEGRATIONS.md)-dədir.

## Rəsmi sənəddə təsdiqlənən faktlar

| Fakt | Rəsmi mənbə | Eve üçün nəticə |
|---|---|---|
| Supabase email Magic Link və OTP passwordless üsulları verir. Magic Link birdəfəlikdir; `signInWithOtp` link göndərə bilər. Redirect yalnız Site URL/allowlist daxilində olmalıdır. | [Passwordless email sign-in](https://supabase.com/docs/guides/auth/auth-email-passwordless) | Şifrə yaratma axını əlavə edilmir; request nəticəsi delivery təsdiqi kimi göstərilmir. |
| PKCE code exchange başlanğıc brauzerdə saxlanan verifier tələb edir; adi PKCE code linkinin başqa brauzer/cihazda exchange edilməsi zəmanətli deyil. Supabase Magic Link template-də `TokenHash` və `verifyOtp` nümunəsi də sənədləşdirir. | [PKCE flow](https://supabase.com/docs/guides/auth/sessions/pkce-flow), [passwordless email sign-in](https://supabase.com/docs/guides/auth/auth-email-passwordless) | `token_hash` confirm variantı namizəddir. Fərqli cihaz davranışı provider mühitində sınaqdan keçmədən seçilmiş həll vəd edilmir. |
| Email scanner linkə `GET` edib birdəfəlik tokeni istifadəçidən əvvəl sərf edə bilər. Supabase aralıq istifadəçi düyməsi olan səhifə təklif edir; SMTP link tracking URL-ni dəyişə bilər. | [Production checklist — email link validity](https://supabase.com/docs/guides/deployment/going-into-prod), [email templates](https://supabase.com/docs/guides/auth/auth-email-templates) | Email URL-si əvvəl Eve confirm landing-ə açılmalı; yalnız açıq istifadəçi hərəkəti token verification-a səbəb olmalıdır. Landing-in `GET`-i session yaratmır. |
| Access JWT qısaömürlü, refresh token yenilənəndə rotasiya olunur; logout təsirinin mövcud JWT TTL-i ilə ayrıca yoxlanması lazımdır. | [User sessions](https://supabase.com/docs/guides/auth/sessions) | D04-ün yenilənən sessiyası real expiry/refresh/logout testindən sonra təsdiqlənə bilər. |
| Default Supabase email göndərişi production delivery üçün nəzərdə tutulmayıb; custom SMTP və sender konfiqurasiyası lazımdır. | [Custom SMTP](https://supabase.com/docs/guides/auth/auth-smtp) | EXT03 təmin edilmədən AT01/AT03 real email delivery PASS deyil. |

Sənədlərdəki provider default müddətləri Eve-nin [15 dəqiqə link TTL və 60 saniyə resend](INTEGRATIONS.md) icra qərarını tətbiq olunmuş konfiqurasiya kimi təsdiqləmir. Staging-də həqiqi parametr və rate-limit yoxlanmalıdır.

## Seçilmiş namizəd axın və mənfi sınaqlar

Bu, implementasiya qərarı üçün yoxlanacaq **namizəddir**: `POST` request → neytral “göndərilməsi istənildi” cavabı → Eve confirm landing `GET` (token sərf edilmir, no-store/no-referrer) → istifadəçinin explicit `POST`/click-i → provider `verifyOtp` → server session cookie → URL-dən tokenin təmizlənməsi. Redirect allowlist serverdə tətbiq edilir. Raw token log, analytics və üçüncü tərəf resursa getmir. Providerin real template və cookie davranışı EVE-007.1–.3-də təsdiqlənməlidir.

| AT | Sınaq | Hazırkı nəticə |
|---|---|---|
| AT01 | Yeni email → link → ilk ev; password API/UI yoxdur | Yalnız müqavilə var; tətbiq və SMTP sınağı yoxdur. |
| AT02 | Refresh, app reopen, logout-all, köhnə access JWT TTL | Sənəd faktı var; runtime sübutu yoxdur. |
| AT03 | Scanner `GET`, replay, expiry, redirect injection, eyni/fərqli cihaz, enumeration və rate limit | Test matrisi təsbit edildi; real provider/scanner sınağı yoxdur. |

## Bloklayıcı və qərar sərhədi

EXT02 Supabase staging, EXT03 custom SMTP/domain təmin edilməyib. Sonrakı EVE-007.3 sınağı real çatdırılma, eyni/fərqli cihaz, scanner-prefetch, replay/expiry, redirect və logout davranışını redaktə edilmiş sübutla bağlamalıdır. Bu spike EVE-003.1 feasibility artefaktıdır; AT01–03 PASS və production auth iddiası deyil.
