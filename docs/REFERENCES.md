# Rəsmi mənbələr və texniki təsdiq

Yoxlama tarixi: 2026-11-10. Mənbələr dəyişə bilər; icra başında API/versiya yenidən yoxlanmalıdır. Bunlar hazır inteqrasiya sübutu deyil.

| Mənbə | İstifadə məqsədi |
|---|---|
| [Next.js App Router](https://nextjs.org/docs/app/getting-started) | Server/client sərhədi və tətbiq strukturu |
| [Next.js PWA](https://nextjs.org/docs/app/guides/progressive-web-apps) | Manifest, quraşdırma və platforma məhdudiyyətləri |
| [Supabase passwordless](https://supabase.com/docs/guides/auth/auth-email-passwordless) | Email link/token verification |
| [Supabase sessions](https://supabase.com/docs/guides/auth/sessions) | Refresh, expiry və logout davranışı |
| [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) | User scoped data policy və bypass sərhədi |
| [Supabase Storage security](https://supabase.com/docs/guides/storage/security/access-control) | Private media və access policy |
| [PostgreSQL range constraints](https://www.postgresql.org/docs/current/rangetypes.html) | Gecələmə intervalı və exclusion constraint |
| [Payriff sənədləri](https://docs.payriff.com/) | Merchant API versiyası və payment status |
| [Payriff recurring](https://docs.payriff.com/docs/recurring-payments) | Auto-renew capability ayrıca doğrulanır |
| [Google noindex](https://developers.google.com/search/docs/crawling-indexing/block-indexing) | noindex və crawler davranışı |
| [Vercel Hobby](https://vercel.com/docs/plans/hobby) | Commercial production üçün Pro seçiminin əsaslandırılması |
| [WCAG 2.2](https://www.w3.org/TR/WCAG22/) | Accessibility qəbul meyarları |

## Açıq provider yoxlamaları

Payriff exact webhook verification schema və illik recurring hesab üzrə təsdiqlənməlidir. Supabase magic link cross-device/PKCE və scanner davranışı sınaq tələb edir. Supabase database backup-ı media backup-ının sübutu deyil. PWA push platformadan asılıdır; email və in-app fallback saxlanılır.
