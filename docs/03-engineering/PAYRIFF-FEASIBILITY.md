# EVE-003.2 — Payriff order/status/webhook feasibility

Yoxlama tarixi: 2026-11-12 (Asia/Baku). Bu, R12, D07/D14, AT26–28 üçün **rəsmi açıq sənəd əsasında feasibility** nəticəsidir. Merchant hesabı, sandbox və canlı ödəniş işlədilməyib. Məhsulun normativ axını [BILLING-FINANCE](../01-product/BILLING-FINANCE.md), [INTEGRATIONS](INTEGRATIONS.md) və [SECURITY](SECURITY.md)-dədir.

## Sənədləşmiş fakt, Eve qərarı və açıq sual

| Mövzu | Rəsmi açıq mənbədəki fakt | Eve üçün qərar / hələ təsdiqsiz hissə |
|---|---|---|
| Hosted checkout | [Payriff hosted checkout](https://docs.payriff.com/docs/hosted-checkout) merchant-in payment/order yaradıb müştərini payment URL-ə yönləndirdiyini və yekun statusun dashboard/API ilə yoxlandığını təsvir edir. | Yalnız Eve **abunəsi** üçün serverdə order yaradılır; browser return `paid` etmir. Dəqiq create/status endpoint və payload merchant API versiyası ilə təsdiqlənməyib. |
| Developer inteqrasiyası | [Developer portal](https://docs.payriff.com/docs/developer-portal) REST reference, secret key və webhook testing imkanını təsvir edir. | Secret yalnız serverdədir. Açıq səhifədəki nümunə merchant hesabında aktiv API versiyası, auth header formatı, event key və webhook verification protokolu üçün sandbox sübutu deyil. |
| Transaction status | [Transactions](https://docs.payriff.com/docs/transactions) order/invoice reference, amount, currency və statusla reconciliation ehtiyacını göstərir. | Eve daxili `billing_order` state-ləri provider status label-larından ayrıdır. Provider enum-u və `paid` ekvivalenti EXT05-də təsdiqlənənədək mapping yazılmır. |
| Recurring | [Recurring payments](https://docs.payriff.com/docs/recurring-payments) açıq səhifəsi gündəlik, həftəlik və aylıq intervalı təsvir edir; illik intervalı həmin siyahıda göstərmir. | Bu, illik recurring-in qəti mümkünsüzlüyü demək deyil; merchant üzrə **təsdiqsizdir**. İlkin aylıq/illik plan manual hosted checkout kimi qalır, auto-renew yalnız opt-in və provider təsdiqindən sonra açılır. |

## Adapter sərhədi və yoxlanacaq sınaqlar

Eve-nin daxili adapter müqaviləsi `createOrder(order, returnUrl)`, `getOrderStatus(providerId)`, `normalizeVerifiedEvent(payload)` və `reconcile(order)`-dır. Bu adlar **Eve interfeysidir**, Payriff endpoint və ya event schema iddiası deyil. Order owner/amount/currency/merchant serverdə saxlanılan dəyərlə tutuşdurulmadan entitlement tətbiq edilmir. Browser return yalnız `pending` göstərir. Webhook varsa onun doğrulama üsulu provider sənədindən/sandbox-dan alınır; təsdiqsiz `signature` field və ya status enum-u uydurulmur. Doğrulanmış event də idempotent DB transaction və order-line unique sərhədini əvəz etmir.

| AT | Sandbox-da tələb edilən sübut | Hazırkı nəticə |
|---|---|---|
| AT26 | Forged browser return/webhook `paid` etmir; order/amount/currency/merchant server statusu ilə yoxlanır | Yalnız yoxlama planı; sandbox yoxdur. |
| AT27 | Duplicate, out-of-order, delayed event və status lookup/reconcile bir dəfə entitlement tətbiq edir | Yalnız yoxlama planı; event formatı təsdiqsizdir. |
| AT28 | Manual monthly/yearly checkout, renewal və expiry; recurring yalnız merchant dəstəyi və opt-in ilə | Məhsul qərarı var; Payriff merchant hesabında təsdiq yoxdur. |

## Bloklayıcı və növbəti qərar

EXT04 merchant/sandbox hesabı, EXT05 təsdiqli API versiyası, status mapping, webhook doğrulaması və recurring/illik dəstək açıqdır. EVE-027.3 provider sandbox sınağı bu faktları və redaktə edilmiş request/response/event sübutunu bağlamalıdır. Bu spike EVE-003.2 feasibility artefaktıdır; checkout, billing və ya provider sandbox PASS deyil.
