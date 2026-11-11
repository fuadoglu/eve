# Əməliyyat və payload müqaviləsi — EVE-004.1

Tarix: 2026-11-11. Giriş: EVE-001.3 merged `091e260`. Normativ mənbə [OpenAPI](openapi.json), semantika [API müqaviləsi](API-CONTRACT.md), qəbul [ACCEPTANCE](../04-quality/ACCEPTANCE.md). Bu yoxlama işləyən server və ya provider nəticəsi deyil.

## Yoxlanan sərhəd

- 117 operation ID-nin hamısında `x-capability`, `x-entitlement`, tələb bağlantısı və 2xx cavab var. OpenAPI-də global `SessionCookie` security var. 20 security override-dan 9-u anonim/public əməliyyat üçün açıq `security: []`, 11-i isə məxfi keçid üçün `ScopedLink`-dir; scoped keçid public access deyil.
- 79 əməliyyatın request body-si var. Validator mövcud request body-də schema, hər 204-dən başqa cavabda isə `$ref` həllindən sonra payload schema tələb edir. Error response-lar ortaq `Error` envelope-una bağlıdır.
- `requestEmailLink` üçün müsbət nümunə: `EmailLinkInput` request, 202 `EmailLinkResultEnvelope` cavabı və `anonymous.email_link` / `exempt` metadata-sı mövcuddur. Bu yalnız schema/metadata uyğunluğudur; email çatdırılması və scanner davranışı AT01–03-də ayrıca sübut tələb edir.

## Mənfi yoxlama və məhdudiyyət

Müvəqqəti kopyada `requestEmailLink` 202 cavabının `content` sahəsi silinəndə `response schema missing`, request body-nin `content` sahəsi silinəndə `request schema missing` ilə hər iki validator çağırışı exit 1 qaytardı. Müstəqil reviewer ortaq `Error400` ref cavabından schema çıxarılanda da exit 1 aldı. Normal müqavilə exit 0 verir. Python OpenAPI/JSON Schema validatoru və mövcud 32 müsbət/mənfi nümunə ayrıca işlədilir. Sınaqlar source fayllarını dəyişmir.

EVE-004.2 state/capability semantikasını, EVE-004.3 bütün schema/fixture inteqrasiyasını ayrıca bağlayır. Bu mərhələdə API route, DB/RLS, real auth, Payriff və mobil istifadəçi sınağı keçilmiş sayılmır. Migration yoxdur; rollback bu sənəd və validator dəyişikliklərinin revertidir.
