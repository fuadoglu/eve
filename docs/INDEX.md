# Eve — sənədlər xəritəsi

Sənəd bazası: 2026-11-10, Asia/Baku. Dil: Azərbaycan dili. Status: **icra üçün normativ spesifikasiya; tətbiq tamamlanmayıb**.

## Oxuma qaydası

Əvvəl AGENTS və qərar reyestri, sonra aid olduğunuz modulun tələbləri, texniki müqaviləsi və qəbul testləri oxunur. Tapşırıqda tələb ID-si və test ID-si göstərilir. Mübahisədə cari istifadəçi göstərişi, sonra qərar reyestri, sonra modul spesifikasiyası əsasdır; ziddiyyət səssiz həll edilmir.

| Sənəd | Cavablandırdığı sual |
|---|---|
| [Qərar reyestri](01-product/DECISIONS.md) | Nə razılaşdırılıb, nə texniki seçimdir, nə xaricdən asılıdır? |
| [Mənbə və tələb inventarı](01-product/SOURCE-INVENTORY.md) | Rəsmi məhsul mənbələri və R01–R16 xəritəsi haradadır? |
| [Tələb və sərhəd auditi](04-quality/REQUIREMENT-AUDIT.md) | PRD/trace fərqləri və kritik sərhədlər necə yoxlanılıb? |
| [Traceability bağlanması](04-quality/TRACE-CLOSURE.md) | Qərar və acceptance xəritəsinin təkrar və mənfi yoxlaması necə aparılıb? |
| [PRD](01-product/PRD.md) | Məhsulun sərhədi və normativ tələbləri nədir? |
| [Əməliyyat qaydaları](01-product/OPERATIONS.md) | Rezervasiya, tapşırıq, inventar necə işləyir? |
| [Abunə və maliyyə](01-product/BILLING-FINANCE.md) | Hansı pul nəyin uçotudur, abunə necə uzanır? |
| [Paylaşım və təlimat](01-product/SHARING-GUIDES.md) | Public səhifə, QR və məxfi keçid fərqi nədir? |
| [Mobil UX](02-design/MOBILE-UX.md) | Sürət və sadəlik necə ölçülür? |
| [Ekran müqavilələri](02-design/SCREENS.md) | Ekranın sahələri, düymələri, boş və xəta vəziyyətləri nədir? |
| [Arxitektura](03-engineering/ARCHITECTURE.md) | Texnologiya və modul sərhədləri necədir? |
| [Data modeli](03-engineering/DATA-MODEL.md) | Cədvəllər, əlaqələr və invariantlar nədir? |
| [API müqaviləsi](03-engineering/API-CONTRACT.md) | Sorğu/cavab, səhv və idempotentlik necədir? |
| [Əməliyyat/payload auditi](03-engineering/OPERATION-PAYLOAD-AUDIT.md) | EVE-004.1 üçün mövcud API əməliyyatları necə yoxlanıb? |
| [State/capability auditi](03-engineering/STATE-CAPABILITY-AUDIT.md) | EVE-004.2 üçün DB enum, keçid və API icazə sərhədləri necə tutuşdurulub? |
| [Təhlükəsizlik](03-engineering/SECURITY.md) | Kim hansı resursa daxil ola bilər? |
| [İnteqrasiyalar](03-engineering/INTEGRATIONS.md) | Auth, Payriff, WhatsApp və media necə yoxlanılır? |
| [Email giriş feasibility](03-engineering/AUTH-FEASIBILITY.md) | EVE-003.1 üçün rəsmi mənbə, namizəd axın və açıq SMTP/scanner sınağı |
| [Payriff feasibility](03-engineering/PAYRIFF-FEASIBILITY.md) | EVE-003.2 üçün hosted checkout faktları və təsdiqsiz merchant/API sərhədi |
| [Qəbul sınaqları](04-quality/ACCEPTANCE.md) | İşin düzgünlüyü necə sübut edilir? |
| [OpenAPI/schema qəbulu](04-quality/OPENAPI-SCHEMA-CLOSURE.md) | EVE-004.3 contract və mənfi sınaq sübutu nədir? |
| [Red-team](04-quality/RED-TEAM.md) | Hansı səhvlər buraxılışı dayandırır? |
| [X10 düşüncə çərçivəsi](04-quality/X10-REVIEW.md) | Qərar hansı on baxışdan yoxlanılıb? |
| [Yol xəritəsi](05-delivery/ROADMAP.md) | İcra asılılıqları və milestone çıxışları |
| [Backlog](05-delivery/BACKLOG.md) | Konkret task və qəbul meyarları |
| [GitHub qaydası](05-delivery/GITHUB-WORKFLOW.md) | Branch, commit, PR, issue, milestone |
| [Codex başlanğıcı](05-delivery/CODEX-START.md) | İcra edən agentə hazır giriş tapşırığı |
| [Xarici asılılıqlar](05-delivery/EXTERNAL-DEPENDENCIES.md) | Production üçün nə hələ təmin edilməyib? |
| [İstismar](05-delivery/RUNBOOK.md) | Deploy, rollback, backup və hadisə |
| [GitHub task xəritəsi](05-delivery/GITHUB-TRACKING.md) | 8 epik və 30 issue-nun dəqiq keçidləri |
| [İcra statusu](05-delivery/STATUS.md) | Faktiki nə edilib, sübutu haradadır? |
| [Provider spike sübutu](04-quality/evidence/eve-003-feasibility.md) | EVE-003.3 mənbə/fərziyyə/bloklayıcı və sonrakı gate xəritəsi |
| [Status keçidləri](01-product/STATE-MACHINES.md) | Hər action-un şərti və atomik yan təsiri |
| [Konfiqurasiya](01-product/CONFIGURATION.md) | Limit, vahid, dəyişmə səlahiyyəti və əsaslandırma |
| [Kliklənən mobil prototip](02-design/PROTOTYPE.md) | UI01–19 demo və istifadə qaydası |
| [Prototip brauzer sübutu](04-quality/evidence/eve-002-1-2-browser.md) | EVE-002.1/.2 üçün 360 px Chrome, klaviatura və flow yoxlaması |
| [Dəqiq form axınları](02-design/FLOW-SPEC.md) | Sahə, default, düymə, xəta və fallback |
| [OpenAPI 3.1 JSON](03-engineering/openapi.json) | Tam request/response müqaviləsi |
| [Maşın data lüğəti](03-engineering/data-dictionary.json) | Sütun-sütun schema və invariantlar |
| [DB giriş sərhədi](03-engineering/ACCESS-BOUNDARY.md) | Base cədvəl grant və RPC qaydaları |
| [API→DB sahə xəritəsi](03-engineering/field-bindings.json) | Ad/limit/enum uyğunluğu |
| [İzləmə matrisi](04-quality/TRACEABILITY.md) | Tələb–ekran–API–data–task–test əlaqələri |
| [Test protokolu](04-quality/TEST-PROTOCOL.md) | Təkrar edilən Given/When/Then və sübut |
| [Atomik iş paketləri](05-delivery/WORK-PACKAGES.md) | 30 issue daxilində 90 bounded vahid |
| [Yekun sənəd auditi](04-quality/DOCUMENTATION-AUDIT.md) | Tapıntı, düzəliş, həqiqi yoxlama və açıq qapılar |
| [Mənbələr](REFERENCES.md) | Texniki qərarların rəsmi istinadları |

## Terminlər

**Ev / əmlak:** abunə olunan vahid; UI əsas naviqasiyası “Mənzillər” adlanır, bağ evi də qəbul edir. **Tenant:** bir sahibin təşkilati məlumat sərhədi. **Menecer təyinatı:** istifadəçi + konkret ev + icazə səviyyəsi. **Pul qeydi:** Eve-nin qəbul etmədiyi kirayə əməliyyatının uçotu. **Abunə ödənişi:** Payriff ilə Eve-yə ödənilən xidmət haqqı. **Təhvil yoxlaması:** inventarın dəyişməz nüsxəsi üzrə müəyyən hadisənin cavabları. **Public:** keçidi olan şəxsə açıqdır; məxfi deyil.
