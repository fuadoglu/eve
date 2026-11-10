# İcra backlog-u

Status: taskların hamısı ilkin olaraq **Backlog**. Ready olmaq üçün taskın asılılığı, owned paths və test fixture-si məlum olmalıdır. GitHub epic issue-ları GitHub iş qaydası ilə əlaqələndirilir; bunlar taskların kodlandığını bildirmir.

| Task | M | İş və sərhəd | Asılılıq | Qəbul / sübut |
|---|---|---|---|---|
| EVE-001 | M0 | Spec və qərar uyğunluğunu yoxla, unresolved register bağla | — | R01–16 map, ziddiyyət yoxdur |
| EVE-002 | M0 | UI01–18 clickable mobil prototip; production kod deyil | 001 | 360 px, 5 nəfər test protokolu |
| EVE-003 | M0 | Auth cross-device/scanner və Payriff API feasibility spike | 001 | Rəsmi schema, sandbox evidence; secret yoxdur |
| EVE-004 | M0 | OpenAPI 3.1, domain state/event və fixture kontraktı | 001,003 | Request/response/error/capability schema |
| EVE-005 | M1 | Next/TS/pnpm/Node pin, env example, CI scripts | 004 | Təmiz checkout build/typecheck |
| EVE-006 | M1 | SQL schema, composite FK, RLS, seed, generated types | 004,005 | AT04–06 DB negative tests |
| EVE-007 | M1 | Passwordless email, session, confirm/resend/logout | 003,005,006 | AT01–03 real SMTP staging |
| EVE-008 | M1 | Ev create/trial claim, manager invite/property permissions | 006,007 | AT04–06, AT25 race |
| EVE-009 | M1 | Dizayn tokenləri, shell, 3 nav, contextual +, empty/error | 002,005 | AT29 keyboard/width |
| EVE-010 | M2 | Unified occupancy/hold/RPC/lock və interval query | 006,008 | AT07–09 concurrency |
| EVE-011 | M2 | Rezervasiya form/detail, quote, receipt atomic create | 009,010 | AT07–11 E2E |
| EVE-012 | M2 | Date/move/cancel/no-show/check-in/out/version | 010,011 | AT10 transition matrix |
| EVE-013 | M2 | Bu gün və mobil agenda/ay, hazırlıq göstəricisi | 009,011,012 | AT29; təqvim query perf |
| EVE-014 | M3 | Rent/deposit/refund ledger və money sheets | 011,012 | AT11–12; rounding/refund |
| EVE-015 | M3 | Realtor collection/settlement və net hesab | 014 | AT13 nümunə/race |
| EVE-016 | M3 | Expenses/allocation/payment/approval/recurring draft | 014,008 | AT14; scope/sum constraint |
| EVE-017 | M3 | Kontakt, task state, scoped link, WhatsApp fallback | 008,009 | AT15–16 token/GET |
| EVE-018 | M3 | Cleaning readiness və notification outbox/jobs | 012,017 | AT16,AT36 dedupe |
| EVE-019 | M4 | Inventory room/item/template/copy/import preview | 006,009 | AT35; tenant-safe copy |
| EVE-020 | M4 | Daily context/event-side snapshots, jobs və revisions | 018,019 | AT17–19; catch-up |
| EVE-021 | M4 | Linkdən otaq yoxlama UX, autosave, problem media | 017,020,022 | AT18–19,AT30 real phone |
| EVE-022 | M5 | Public/private upload pipeline, quota, signed media | 006,008 | AT06,AT21,AT32 file tests |
| EVE-023 | M5 | Guide block/locales/publish və stable QR export | 009,022 | AT20–21 camera scan |
| EVE-024 | M5 | Public property DTO/OG/noindex və preview switches | 009,022 | AT22–24 PII audit |
| EVE-025 | M5 | Available nights/departures və interval quote | 010,024 | AT08,AT24 stale/range |
| EVE-026 | M6 | Plan catalog/orders/period anchor/entitlement | 006,008,003 | AT25,AT28 month/leap |
| EVE-027 | M6 | Payriff adapter/verify inbox/reconcile/idempotency | 026,003 | AT26–27 sandbox |
| EVE-028 | M6 | Billing UI/expiry/renewal və toplu same-owner checkout | 027,014,017,023,024 | AT28 bütün modullar |
| EVE-029 | M7 | Scoped export, operator/support və audit redaction | 014,016,020,027 | AT32,AT35 |
| EVE-030 | M7 | E2E/security/a11y/perf, restore/rollback, handoff | 001–029 | AT01–36; P0/P1=0 |

## Hər taskın issue mətni

Məqsəd; scope; exclusions; yuxarıdakı dependency; owned paths; R/AT ID-ləri; acceptance checklist; test əmri; environment; migration/rollback; agent owner; reviewer; blocker. UI task backend mock-la işləyibsə “integrated” sayılmır.

## GitHub status qaydası

Backlog → Ready → In progress → Review → Done. Blocked ayrıca səbəb/əlaqə ilə. Taskın “Done” olması merge edilmiş kod və faktiki sübut tələb edir. M0 spec task-ı bu docs commit-lə qismən hazırdır; prototype, OpenAPI və provider spike hələ icra olunmayıb.
