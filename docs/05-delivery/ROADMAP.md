# İcra ardıcıllığı və milestone-lar

Bu tarix vəd edən sprint planı deyil. Mərhələlər çıxış keyfiyyətinə görə bağlanır; task sayı tamamlanma meyarı deyil.

| Milestone | Nəticə | Asılılıq | Çıxış qapısı |
|---|---|---|---|
| M0 — İcra müqaviləsi | Məhsul/UX/data/security spec, OpenAPI skeleton, mobil clickable prototip, dependency spike | Bu sənəd bazası | Prototip real istifadə sınağı, icra qərarları və provider qeyri-müəyyənlikləri ayrıdır |
| M1 — Təməl və giriş | Next.js, local Supabase, CI, SQL/RLS, magic link, owner/manager, dizayn tokenləri | M0 | Təmiz checkout build; AT01–06; secret/data isolation |
| M2 — Rezervasiya | Bu gün, mobil təqvim, occupancy/hold, giriş/çıxış və dəyişiklik | M1 | AT07–10 və mobil ilkin axın |
| M3 — Pul və xidmət | Rent/deposit/realtor/expense, əlaqələr, WhatsApp task, cleaning | M2 | AT11–16; integer və scope sübutu |
| M4 — İnventar | Şablon/import, day/event/snapshot, sadə otaq formu, problem | M1 data + M2 event + M3 task contract | AT17–19 və real icraçı usability |
| M5 — Paylaşım | Public təqdimat, availability projection, çoxdilli guide, QR, media | M1, M2; M4 ilə paralel mümkündür | AT20–24; privacy/QR scan |
| M6 — Abunə | Payriff checkout/verification/reconcile, trial/period/expiry, toplu order | M1 permission; M2–5 entitlement integrated | AT25–28 sandbox və expiry regressiya |
| M7 — Buraxılış | Operator/support/export, accessibility/perf/security, restore/rollback | M1–6 | AT01–36 sübutu; P0/P1=0; xarici gate-lər həll |

## Kritik yol və paralellik

M0 → M1 → M2 → M3 → M4/M5 inteqrasiya → M6 yekun gate → M7.
Payriff/SMTP feasibility M0-da başlayır. Billing backend M1 sonrası, UI/expiry inteqrasiyası digər modullarla birləşəndə tamamlanır. M4 və M5 yalnız ortaq media/API müqaviləsi sabit olduqda paralel yazılır.

## Milestone sübutu

Hər mərhələ issue-sunda task bağlantısı, merged PR, acceptance nəticəsi, risk, demo/screenshot və növbəti gate yazılır. “Sənədləşdirildi” = “implementasiya tamamlandı” deyil. Başlanğıcda tətbiq mərhələlərinin hamısı Backlog-dur.

GitHub native Milestones yaradılması ayrıca admin əməliyyatıdır. Yalnız roadmap/epic issue yaradılıbsa bunlar native milestone kimi təqdim edilmir.
