<div align="center">

# eve
### Evlərin bir yerdə.

**Günlük kirayə evlərinin mobil idarəetməsi**

![Mərhələ](https://img.shields.io/badge/m%C9%99rh%C9%99l%C9%99-icra_spesifikasiyas%C4%B1-2563EB)
![Dil](https://img.shields.io/badge/s%C9%99n%C9%99dl%C9%99r-AZ-16A34A)
![Platforma](https://img.shields.io/badge/platforma-PWA-7C3AED)
![Bazar](https://img.shields.io/badge/bazar-Az%C9%99rbaycan-0891B2)

**📅 Təqvim · 🏠 Evlər · ✅ Tapşırıqlar · 📦 Təhvil yoxlaması · 📱 QR təlimatlar**

</div>

---

## Məhsulun vədi

Eve ev sahibinin WhatsApp, dəftər və cədvəllərə bölünmüş işlərini bir yerdə birləşdirir. Sahib boş tarixləri görür, rezervasiya və pul qeydi yaradır, menecerə ev həvalə edir, icraçıya tapşırıq və qonağa təlimat paylaşır.

**Eve kirayə marketplace-i və ödəniş vasitəçisi deyil.** Payriff yalnız Eve abunəsi üçün istifadə olunur. Kirayə, beh, depozit və komissiyalar sahibin uçot qeydləridir.

> **Hazırkı vəziyyət:** bu repo məhsulun icra və təhvil spesifikasiyasıdır. İşlək tətbiq və inteqrasiyalar hələ yoxdur. Kliklənən sənəd prototipi mövcuddur; real backend və provider çağırışı etmir. Tətbiq testləri hələ icra olunmayıb. Nişanlar build və ya təhlükəsizlik yoxlamasının keçdiyini bildirmir.

## 🧭 Haradan başlamalı?

| Oxucu | Oxuma ardıcıllığı |
|---|---|
| Məhsul sahibi | [Qərarlar](docs/01-product/DECISIONS.md) → [Məhsul](docs/01-product/PRD.md) → [Yol xəritəsi](docs/05-delivery/ROADMAP.md) |
| Dizayner | [Mobil UX](docs/02-design/MOBILE-UX.md) → [Ekranlar](docs/02-design/SCREENS.md) |
| Backend / data | [Arxitektura](docs/03-engineering/ARCHITECTURE.md) → [Data modeli](docs/03-engineering/DATA-MODEL.md) → [API](docs/03-engineering/API-CONTRACT.md) |
| QA / təhlükəsizlik | [İcazələr](docs/03-engineering/SECURITY.md) → [Red-team](docs/04-quality/RED-TEAM.md) → [Qəbul sınaqları](docs/04-quality/ACCEPTANCE.md) |
| Codex / inteqrator | [AGENTS.md](AGENTS.md) → [Başlanğıc tapşırığı](docs/05-delivery/CODEX-START.md) → [Backlog](docs/05-delivery/BACKLOG.md) |

Tam naviqasiya: **[Sənədlər indeksi](docs/INDEX.md)**.

## 🔬 İcra üçün dəqiq müqavilələr

| Müqavilə | Mənbə |
|---|---|
| API: sahələr, cavablar, xətalar və icazələr | [OpenAPI 3.1](docs/03-engineering/openapi.json) |
| Cədvəllər, sütunlar, FK və RLS sərhədi | [Data dictionary](docs/03-engineering/data-dictionary.json) |
| API→DB ad/limit/enum uyğunluğu | [Field bindings](docs/03-engineering/field-bindings.json) |
| Düymələrin status və yan təsirləri | [State machines](docs/01-product/STATE-MACHINES.md) |
| Ekran və forma davranışı | [Mobil prototip](docs/02-design/PROTOTYPE.md) · [Flow spec](docs/02-design/FLOW-SPEC.md) |
| Tələbdən testə qədər əlaqə | [Traceability](docs/04-quality/TRACEABILITY.md) |
| 30 parent issue daxilində 90 kiçik iş vahidi | [Work packages](docs/05-delivery/WORK-PACKAGES.md) |
| Müstəqil baxışın nəticəsi və sərhədlər | [Sənəd auditi](docs/04-quality/DOCUMENTATION-AUDIT.md) |

Sənədlərin praktik başlanğıcı: `node scripts/docs-check.mjs` və `node scripts/verify-contracts.mjs`. Python schema yoxlaması və demo smoke qaydası [CONTRIBUTING](CONTRIBUTING.md)-dədir.


## ⚡ Gündəlik istifadə

1. **Bu gün:** gələnlər, çıxanlar, gecikən işlər və pul xatırlatmaları.
2. **Təqvim:** boş tarixlər, rezervasiya və bloklama.
3. **Mənzillər:** məlumat, inventar, təlimat, public səhifə və ev üzrə nəticələr.

Kontekstli **+** düyməsi: rezervasiya, pul qeydi, xərc, tapşırıq. Əsas məlumat bir dəfə yazılır, əlaqəli hissələr yenilənir.

## 👥 Bir hesab, bir neçə məsuliyyət

- Bir sahib bir neçə ev əlavə edir.
- Bir menecer müxtəlif sahiblərin seçilmiş evlərini bir paneldə idarə edir.
- İcazələr **ev üzrədir**, hesab üzrə ümumi rol deyil.
- Usta və təmizlikçi yalnız konkret tapşırıq keçidindən istifadə edir.
- Email keçidi ilə giriş; şifrə yoxdur.

## 💳 Abunə

| Plan | Hər ev üçün |
|---|---:|
| Aylıq | **9,99 AZN** |
| İllik | **99,99 AZN** |
| İlk ev | **Bir dəfə 7 gün sınaq** |
| Menecer | **Əlavə abunə haqqı yoxdur** |

İllik plan əvvəl razılaşdırılmış məhsul qaydasıdır; kirayə puluna vasitəçilik edilmir. Payriff-də avtomatik illik yeniləmə ayrıca təsdiqlənməyib. Qaydalar: [Abunə və maliyyə](docs/01-product/BILLING-FINANCE.md).

## 🛠 Texnoloji istiqamət

![Next.js](https://img.shields.io/badge/Next.js-000000?logo=nextdotjs&logoColor=white)
![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?logo=typescript&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-1C1C1C?logo=supabase&logoColor=3ECF8E)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)
![Tailwind CSS](https://img.shields.io/badge/Tailwind_CSS-0F172A?logo=tailwindcss&logoColor=38BDF8)
![Vercel](https://img.shields.io/badge/Vercel-000000?logo=vercel&logoColor=white)


| İkon | Texnologiya | Təyinat |
|---|---|---|
| ⚛️ | Next.js App Router + TypeScript | Bir tətbiqdə panel, server əməliyyatları və public keçidlər |
| 🐘 | Supabase PostgreSQL | Əlaqəli data, RLS, tranzaksiyalar |
| 🔐 | Supabase Auth | Şifrəsiz email keçidi və sessiyalar |
| 🗂️ | Supabase Storage | Səlahiyyətlə ayrılmış media |
| 🎨 | Tailwind CSS + shadcn/ui + Lucide | Vahid, əlçatan interfeys |
| 📝 | React Hook Form + Zod | Qısa formalar və serverdə təkrar validasiya |
| 🌐 | next-intl | AZ interfeys; çoxdilli təlimat və təqdimat məzmunu |
| 💳 | Payriff | Yalnız Eve abunə ödənişi |
| 🚀 | Vercel Pro | Planlaşdırılan production yerləşdirmə |

Versiyalar icra başlanarkən rəsmi dəstək/security vəziyyətinə görə seçilir və lockfile-da sabitlənir. “Latest” production siyasəti deyil.

## 🧩 İcra xəritəsi

**M0 Müqavilələr → M1 Təməl → M2 Təqvim → M3 Pul və işlər → M4 İnventar → M5 Paylaşım → M6 Abunə → M7 Buraxılış**

**[GitHub-da 8 mərhələ epiki və 30 task](docs/05-delivery/GITHUB-TRACKING.md)** yaradılıb. Native milestone konfiqurasiyası ayrıca izlənilir.

Hər mərhələnin qəbul şərti və asılılığı [ROADMAP](docs/05-delivery/ROADMAP.md)-dədir. Kodun dəyişməsi [GitHub iş qaydası](docs/05-delivery/GITHUB-WORKFLOW.md) ilə, agentlər [AGENTS.md](AGENTS.md) ilə idarə olunur.

## 🛡 Keyfiyyət mövqeyi

Tenant izolyasiyası, rezervasiya toqquşmaları, Payriff təkrar hadisələri və məxfi keçidlər release gate-dir. “İşləyir” ifadəsi konkret commit və yoxlama sübutu tələb edir. Keçilməyən test uğurlu göstərilmir.

## 📚 Layihənin hazırkı sərhədi

Bu commit sənədləşmə təhvilidir; saytın yayımlanması və production aktivləşdirilməsi deyil. Sahibin domeni, provider hesabları, ödəniş müqaviləsi və hüquqi mətn təsdiqi [Xarici asılılıqlar](docs/05-delivery/EXTERNAL-DEPENDENCIES.md)-də izlənilir.

Lisenziya verilməyib; açıq mənbə istifadəsi hüququ təsis edilmir. Şəxsi məlumat və məxfi açarlar repoya daxil edilmir.
