# OpenAPI/schema qəbulu — EVE-004.3

Tarix: 2026-11-11. Giriş: EVE-004.1 `a54cfa2`, EVE-004.2 `cad93d9` main commit-ləri. Normativ mənbələr: [OpenAPI](../03-engineering/openapi.json), [API müqaviləsi](../03-engineering/API-CONTRACT.md), [state auditi](../03-engineering/STATE-CAPABILITY-AUDIT.md) və [ACCEPTANCE](ACCEPTANCE.md). Bu sənəd tətbiq route-u, DB/RLS və provider sandbox sübutu deyil.

## Qəbul sərhədi

- OpenAPI 3.1 spec və 207 komponent JSON Schema yoxlanır. 117 əməliyyatın operationId, tələb, capability, entitlement, security, request/cavab schema və 2xx əlaqələri contract validatorundan keçir; field binding və state enum əlaqələri ayrıca həmin validatorun hissəsidir.
- `x-contract-examples` hazırda 12 müsbət, 20 mənfi payload-dan ibarətdir. Python validatoru hər nümunəni faktiki JSON Schema ilə yoxlayır və hər iki istiqamətin mövcudluğunu məcburi edir. Bütün 207 schema üçün nümunə olduğunu iddia etmir.
- Global `SessionCookie` normativdir. Doqquz dəqiq anonim/public/provider endpoint-i `security: []`, on bir məxfi keçid endpoint-i `ScopedLink` istifadə edir. Qalan şəxsi əməliyyatlar session tələb edir. `receivePayriffEvent` açıq transport exception-udur; provider payload-u serverdə status/merchant/order/amount/currency doğrulamasından keçməyincə entitlement dəyişmir. EXT05 provider imza/status forması açıq qalır.

## Mənfi sübut

Müvəqqəti OpenAPI kopyasında bütün mənfi nümunələr silinəndə Python validatoru `Both positive and negative contract examples required` ilə exit 1 verdi. `getProfile` və `readScopedTask` əməliyyatlarına `security: []` yazıldıqda, həmçinin global security boşaldıldıqda contract validatoru exit 1 verdi. Normal müqavilə exit 0 verir. EVE-004.1-in boş request/cavab schema və EVE-004.2-nin state/capability mənfi sınaqları əvvəlki PR-lərdə ayrıca sübut olunub.

Müstəqil baxış açıq/scoped operationId üçün security doğru qalsa da capability-ni `owner` etməyin keçdiyini tapdı. Validator indi bu 20 exception-un hər birini dəqiq capability ilə bağlayır. `readPublicProperty` və `readScopedTask` capability-si `owner` edilən iki müvəqqəti kopyada `security capability mismatch` ilə exit 1 alındı; normal müqavilə exit 0 qaldı.

## Qalan sərhəd

Bu nəticə işləyən route, aktual membership, RLS/storage, SMTP/Payriff, mobil brauzer və M7 AT01–36 tətbiq sınaqlarını əvəz etmir. EVE-005 scaffold və sonrakı domain paketləri API/DB müqaviləsini runtime-a bağlamalıdır. Migration yoxdur; rollback validator və sənəd commit-lərini revert etməkdir.
