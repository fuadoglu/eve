# State və capability uyğunluğu — EVE-004.2

Tarix: 2026-11-11. Giriş: EVE-004.1 main `a54cfa2`. Bu, sənəd müqaviləsinin yoxlanmasıdır; SQL/RLS və işləyən API sübutu deyil.

## State sərhədi

Beş machine-in saxlanan vəziyyətləri müvafiq DB enum-u ilə müqayisə edilir: reservation/reservation_state, task/task_state, inspection/submission_state, expense/expense_approval, billing_order/order_state. `absent` yalnız hələ yaradılmamış resurs üçün machine başlanğıcıdır, DB dəyəri deyil. `same` mövcud vəziyyəti saxlayan keçiddir. Validator state siyahısının enum-la tam uyğunluğunu, keçid source/destination-unu və terminal state-dən başqa state-ə keçilməməsini yoxlayır.

Billing order enum/API-dəki `refund_review`, `refunded`, `chargeback_review` machine-də yox idi. [D32](../01-product/DECISIONS.md) əsasında review state-ləri əlavə edildi. Operatorun `review_refund`/`review_chargeback` əməliyyatı yalnız `entitlement_applied` order-i auditli review vəziyyətinə keçirir; ödənişi, abunə müddətini və digər order-ləri dəyişmir. `refunded` rezerv dəyərdir, ona heç bir keçid yoxdur. EXT05 provider və EXT07 hüquqi təsdiq olmadan refund icrası və entitlement düzəlişi açılmır. AT32 operator reason/version və dəyişməz müddət sərhədini planlaşdırır; tətbiq testi hələ icra edilməyib.

## Capability sərhədi

Machine capability-si domen əməliyyatının icazəsidir; OpenAPI capability-si konkret çağırış səthinə aiddir. Buna görə adları kor-koranə bərabərləşdirmək olmaz:

| Machine capability | API səthi / əlaqə |
|---|---|
| `reservation.write` | `reservation.write`; ev dəyişməsində hər iki ev üçün `reservation.write_both_properties` |
| `task.manage` | hesablı `task.manage` |
| `task.accept`, `task.complete` | hesablı `task.manage` və ya məxfi keçiddə `link.task.accept` / `link.task.report_done` |
| `inspection.submit` | hesablı `inventory.manage` və ya məxfi keçiddə `link.inspection.write` / `link.inspection.complete` |
| `inventory.manage`, `expense.propose`, `finance.manage` | eyni adlı API capability |
| `billing.owner` | owner-only API `owner` |
| `operator.allowlisted` | `reviewOperatorOrder` üçün eyni adlı API capability |
| `system.billing`, `system.hold_expiry` | daxili təsdiqlənmiş provider/job əməliyyatı; public operationId yoxdur |

Bu xəritə hər request-də property, membership, entitlement və token scope yoxlamasını əvəz etmir. Validator məlum machine capability-lərini və göstərilmiş API capability adlarının mövcudluğunu yoxlayır; real server authorization-u yalnız kod və mənfi inteqrasiya testləri sübut edəcək.

## Yoxlama

Normal müqavilə `node scripts/verify-contracts.mjs` ilə exit 0 verdi. Ayrı müvəqqəti kopyalarda billing machine-dən `refunded` silinəndə `DB state enum mismatch`, transition capability-si `billing.unknown` ediləndə `unmapped capability`, `entitlement_applied` yenidən terminal sayıldıqda `terminal state transition` ilə exit 1 alındı. Docs, schema və prototip yoxlamalarının son commit nəticəsi PR-də qeyd olunur. Migration yoxdur; rollback bu sənəd və machine/validator düzəlişlərinin revertidir.

Müstəqil baxış operator review capability-sini başqa məlum capability ilə əvəz edəndə ilkin validatorun bunu qəbul etdiyini tapdı. D32 üçün keçidə məxsus yoxlama əlavə edildi: `billing_order.review_refund` capability-si `billing.owner` olduqda `operator capability mismatch`, source `pending` olduqda `invalid review source`, entitlement qoruma effekti silindikdə `review must preserve entitlement` ilə exit 1 alındı. Normal müqavilə exit 0 qaldı.

Təkrar baxışda review destination-u `created` ilə əvəzləmək və səbəb/versiya precondition-unu silmək də əvvəlcə keçirdi. Hər review action indi yalnız öz review state-inə gedə bilər və həm operator allowlist, həm səbəb/versiya precondition-u tələb edir. Bu üç əlavə mənfi nümunə exit 1, normal müqavilə exit 0 verdi.

Review effekti siyahısına `extend_current_end` əlavə edilməsi də D32-yə ziddir; validator indi bu iki keçid üçün yalnız audit marker-i və ödəniş/entitlement qoruma effektlərini qəbul edir. Müvəqqəti period mutation nümunəsi exit 1 verdi.
