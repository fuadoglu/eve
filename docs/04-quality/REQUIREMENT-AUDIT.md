# Tələb və sərhəd auditi — EVE-001.2

Tarix: 2026-11-11. Giriş: main commit `2562553` və [EVE-001.1 inventarı](../01-product/SOURCE-INVENTORY.md). Bu audit sənəd əlaqələrini yoxlayır; işləyən tətbiq, RLS və ya provider sandbox nəticəsi deyil.

## Qəbul xəritəsinin tutuşdurulması

[PRD](../01-product/PRD.md)-də R01–R16 üçün göstərilən AT siyahıları [traceability.json](traceability.json), [TRACEABILITY.md](TRACEABILITY.md) və [acceptance-scenarios.json](acceptance-scenarios.json) ilə tutuşduruldu. On altı tələbdən beşində siyahı fərqi var. Machine trace əlaqələri ssenarilərin `requirements` sahəsindən yaranır; PRD-dəki siyahı eyni əlaqələri tam əks etdirmir.

| ID | Fakt və nəticə | Nəticə / növbəti addım |
|---|---|---|
| R05 | Auditdən əvvəl PRD AT11–14 yazırdı; trace AT11–13 göstərirdi. AT14 ssenarisində yalnız R06 var və xərc təsdiqi/allocation yoxlanır. | Bu PR-də PRD və inventar AT11–13-ə düzəldildi; maşın ssenarisi dəyişməyib. |
| R06 | Auditdən əvvəl PRD AT13–14 yazırdı; trace AT14 göstərirdi. AT13 yalnız R05-dir və realtor settlement yoxlayır. | Bu PR-də PRD və inventar AT14-ə düzəldildi; maşın ssenarisi dəyişməyib. |
| R09 | Trace əlavə AT12 göstərir. AT12 ssenarisi inspection və deposit allocation sərhədini yoxlayır, `requirements` R05 və R09-dur. | AT12-ni R09 üçün cross-coverage kimi saxla; PRD və trace arasındakı əhatə fərqini açıqlaşdır. |
| R10 | Trace əlavə AT28 göstərir. AT28 expiry zamanı safety QR istisnasını yoxlayır, `requirements` R12 və R10-dur. | AT28-i R10 üçün cross-coverage kimi saxla; PRD və trace arasındakı əhatə fərqini açıqlaşdır. |
| R11 | Trace əlavə AT08 göstərir. AT08 public valid departure ilə gecələmə availability fərqini yoxlayır, `requirements` R04 və R11-dir. | AT08-i R11 üçün cross-coverage kimi saxla; PRD və trace arasındakı əhatə fərqini açıqlaşdır. |

R05/R06 qəbul əlaqələri bu PR-də ssenari və trace ilə uyğunlaşdırılıb; səbəb, təsirlənən R/AT ID-ləri və migration təsiri [D31](../01-product/DECISIONS.md)-də yazılıb. AT13 və AT14 ssenariləri və M7-də bütün qəbul testləri tələbi saxlanılır. R09/R10/R11 əlavə testləri ssenarilərdə cross-coverage kimi qalır; EVE-001.3 yekun trace və qərar bağlanmasını yoxlayacaq. Bu sənəd tətbiq testlərinin keçdiyini iddia etmir.

EVE-001.1 inventarının əsas cədvəli PRD qəbul siyahısını təqdim etdiyini desə də, R09 üçün AT12 və R11 üçün AT08-i əlavə etmişdi. Bu PR həmin iki sətri PRD-yə uyğunlaşdırır; əlavə cross-coverage inventarın fərq cədvəlində və machine trace-də saxlanılır.

## Əsas təhlükəsizlik və pul sərhədləri

| Sərhəd | Yoxlanmış mənbələr | Nəticə və sonrakı sübut |
|---|---|---|
| Şifrəsiz giriş və scanner | [D03](../01-product/DECISIONS.md), [AT01–03](ACCEPTANCE.md), [RT07](RED-TEAM.md) | Email link və scanner/replay mənfi ssenarisi sənədlərdə ayrıdır. Real SMTP və cross-device sübutu EVE-007.3 gate-indədir. |
| Tenant və base-table giriş | [Access boundary](../03-engineering/ACCESS-BOUNDARY.md), [AT04–06](ACCEPTANCE.md), [RT01/RT08](RED-TEAM.md) | Base grant və cari membership sərhədi təsvir edilib. SQL/RLS və tenant isolation sübutu EVE-006.3-də tələb olunur. |
| Payriff və kirayə uçotu | [D07](../01-product/DECISIONS.md), [billing/finance](../01-product/BILLING-FINANCE.md), [AT11–14, AT26–27](ACCEPTANCE.md) | Payriff SaaS abunəsi üçündür; kirayə və deposit ayrıca uçotdur. Provider yoxlaması və ledger testləri hələ tələb olunur. |
| Public/noindex və safety QR | [D08/D16/D21](../01-product/DECISIONS.md), [paylaşım](../01-product/SHARING-GUIDES.md), [AT21/AT24/AT28](ACCEPTANCE.md) | noindex məxfilik deyil; dərc edilmiş safety QR expiry-də açıq qalır. Public DTO və expiry testləri hələ tələb olunur. |
| GET və scoped task | [RT09](RED-TEAM.md), [AT15–16](ACCEPTANCE.md) | GET/prefetch task qəbul və completion yaratmamalıdır. Real API mənfi testi EVE-017.3-də tələb olunur. |

Bu cədvəl seçilmiş kritik sərhədlərin sənəd uyğunluğunu yoxlayır; bütün implementasiya və bütün mümkün ziddiyyətlər üçün yekun təhlükəsizlik auditi deyil. Müstəqil review və EVE-001.3 qərar/trace bağlanması qalır.
