# İstismar və təhvil runbook-u

Planlaşdırılan prosedurdur; bu mərhələdə production sistem və restore sübutu yoxdur.

## Mühit və deploy

1. Local/staging/production DB, bucket, SMTP və Payriff credential-ları ayrıdır.
2. Clean install, typecheck/unit/DB/API/E2E/build və migration dry-run keçir.
3. Staging-də real provider sandbox, mobil smoke, privacy projection yoxlanır.
4. Production migration expand/contract üsulu ilə; destructive addım ayrıca review.
5. App deploy sonrası auth, read-only public/QR, calendar write və billing status smoke.
6. Provider real charge smoke yalnız səlahiyyətli test hesabı və ayrıca faktiki ödəniş scope-u ilə.
7. Release notes commit/tag, migration, evidence və rollback addımlarını saxlayır.

## Rollback

App previous deployment-a qaytarıla bilər; DB migration özbaşına avtomatik downgrade edilmir. Backward-compatible expand migration üstün tutulur; data-destructive dəyişiklik üçün backup və forward-fix planı əvvəl yazılır. Billing event-ləri rollback-də silinmir; apply əməliyyatı unique olduğuna görə reconcile təhlükəsizdir.

## Backup / restore

İlkin hədəf RPO ≤24 saat, RTO ≤4 saat; provider planı və faktiki restore drill ilə təsdiqlənmədən SLA deyil. DB və private/public media inventarı ayrıca backup edilir. Storage obyektləri database backup-ında mövcud sayılmır.

Aylıq staging restore drill: DB bərpa → file manifest/media bərpa → FK/count/hash nümunələri → RLS/user isolation → revoked tokenin qapalı qalması → billing event/apply consistency. Staging job-lar real bildiriş/charge göndərməsin. Restore report tarix, commit, müddət və itki intervalı saxlayır.

## Monitorinq

Server errors/p95, auth delivery failure, DB pool/slow queries, cron heartbeat/lag, outbox failure, pending billing age, verified→applied mismatch, storage quota və upload orphan. PII/token/card telemetry yoxdur.

Alert sahibi təyin edilməlidir. Alert testlə tetiklenmədən “monitoring aktivdir” yazılmır. Pending payment reconcile threshold ilkin 15 dəqiqə; provider limitinə uyğun tuning edilir.

## Hadisələr

Tenant sızması: təsirlənmiş route/flag disable, scoped access revoke, evidence redacted qorunur, digər tenants yoxlanır, sahibə fakt əsaslı məlumat. Payment mismatch: avtomatik ikinci charge yox, provider status lookup və order/line audit. Cron dayanması: manual idempotent catch-up; occupancy write yenə expired hold-u yoxlayır.

## Hesab silinməsi / retention

Archive ilə hüquqi silinmə fərqlidir. Owner request-i identity doğrulamasından sonra private linkləri revoke edir; qanuni maliyyə/audit retention müddəti hüquqi qərarla təyin edilir. Safety QR üçün “abunə bitməsi” ilə “hesabın silinməsi/xidmətin bağlanması” ayrı davranışdır; hüquqi təsdiq olmadan əbədi saxlanma vədi yoxdur.

## Dəstək və operator

Minimal operator paneli hesab/ev/abunə/order/support statusunu göstərir. Şəxsi qonaq məzmununa ümumi baxış verilmir. Həssas müdaxilə səbəb/audit tələb edir. Manual entitlement fix original event və səbəb olmadan edilmir.

## Təhvil paketi

Source+lockfile; env adları; migrations/seed; OpenAPI; test evidence; UX prototype/report; provider configuration steps; backup/restore report; monitoring ownership; known issues; release notes. Secretlər paketdə yoxdur.
