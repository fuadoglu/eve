# Atomik iş paketləri

30 parent issue saxlanılır; aşağıdakı 90 vahid həmin issue-nun ayrıca checklist və PR scope-udur. ID formatı EVE-010.1. Parent issue yalnız bütün vahidlər və milestone qapısı tamamlananda bağlanır.

Maşın mənbəyi: [work-packages.json](work-packages.json). Konkret fayl ownership Ready zamanı ayrılır; qovluq namizədləri agentə eyni faylı paralel dəyişmək icazəsi vermir.

| Paket | İş | Asılılıq | Parent issue |
|---|---|---|---|
| EVE-001.1 | Mənbə və tələb inventarı | — | [#9](https://github.com/fuadoglu/eve/issues/9) |
| EVE-001.2 | Ziddiyyət və sərhəd auditi | EVE-001.1 | [#9](https://github.com/fuadoglu/eve/issues/9) |
| EVE-001.3 | Qərar və traceability bağlanması | EVE-001.2 | [#9](https://github.com/fuadoglu/eve/issues/9) |
| EVE-002.1 | Mobil wireframe və komponentlər | EVE-001.3 | [#10](https://github.com/fuadoglu/eve/issues/10) |
| EVE-002.2 | Kliklənən əsas axınlar | EVE-002.1 | [#10](https://github.com/fuadoglu/eve/issues/10) |
| EVE-002.3 | Real istifadəçi protokolu və düzəliş | EVE-002.2 | [#10](https://github.com/fuadoglu/eve/issues/10) |
| EVE-003.1 | Email cross-device/scanner spike | EVE-001.3 | [#11](https://github.com/fuadoglu/eve/issues/11) |
| EVE-003.2 | Payriff order/status/webhook spike | EVE-003.1 | [#11](https://github.com/fuadoglu/eve/issues/11) |
| EVE-003.3 | Provider sübutu və bloklayıcı reyestri | EVE-003.2 | [#11](https://github.com/fuadoglu/eve/issues/11) |
| EVE-004.1 | Əməliyyat və payload müqavilələri | EVE-001.3 | [#12](https://github.com/fuadoglu/eve/issues/12) |
| EVE-004.2 | Status və capability uyğunluğu | EVE-004.1 | [#12](https://github.com/fuadoglu/eve/issues/12) |
| EVE-004.3 | OpenAPI/schema yoxlamaları | EVE-004.2 | [#12](https://github.com/fuadoglu/eve/issues/12) |
| EVE-005.1 | Pinned runtime və layihə scaffold | EVE-004.3 | [#13](https://github.com/fuadoglu/eve/issues/13) |
| EVE-005.2 | Mühit və secret kontraktı | EVE-005.1 | [#13](https://github.com/fuadoglu/eve/issues/13) |
| EVE-005.3 | Təmiz checkout CI/build | EVE-005.2 | [#13](https://github.com/fuadoglu/eve/issues/13) |
| EVE-006.1 | SQL cədvəl və tenant constraint-ləri | EVE-004.3, EVE-005.3 | [#14](https://github.com/fuadoglu/eve/issues/14) |
| EVE-006.2 | RLS/RPC və storage policy | EVE-006.1 | [#14](https://github.com/fuadoglu/eve/issues/14) |
| EVE-006.3 | DB isolation və concurrency fixture-ləri | EVE-006.2 | [#14](https://github.com/fuadoglu/eve/issues/14) |
| EVE-007.1 | Email request və confirm/resend | EVE-005.3, EVE-006.3, EVE-003.1 | [#15](https://github.com/fuadoglu/eve/issues/15) |
| EVE-007.2 | Session refresh və logout-all | EVE-007.1 | [#15](https://github.com/fuadoglu/eve/issues/15) |
| EVE-007.3 | SMTP/scanner/replay mənfi testləri | EVE-007.2 | [#15](https://github.com/fuadoglu/eve/issues/15) |
| EVE-008.1 | Ev yaradılması və trial atomikliyi | EVE-006.3, EVE-007.2 | [#16](https://github.com/fuadoglu/eve/issues/16) |
| EVE-008.2 | Email invite və property permission | EVE-008.1 | [#16](https://github.com/fuadoglu/eve/issues/16) |
| EVE-008.3 | Revoke və cross-owner negative test | EVE-008.2 | [#16](https://github.com/fuadoglu/eve/issues/16) |
| EVE-009.1 | Dizayn tokenləri və UI primitivləri | EVE-002.2, EVE-005.3 | [#17](https://github.com/fuadoglu/eve/issues/17) |
| EVE-009.2 | Üç naviqasiya və kontekstli plus | EVE-009.1 | [#17](https://github.com/fuadoglu/eve/issues/17) |
| EVE-009.3 | Klaviatura/empty/error/a11y yoxlaması | EVE-009.2 | [#17](https://github.com/fuadoglu/eve/issues/17) |
| EVE-010.1 | Unified occupancy və exclusion | EVE-006.3, EVE-008.3 | [#18](https://github.com/fuadoglu/eve/issues/18) |
| EVE-010.2 | Expired hold lock/catch-up | EVE-010.1 | [#18](https://github.com/fuadoglu/eve/issues/18) |
| EVE-010.3 | Paralel booking/block/hold testləri | EVE-010.2 | [#18](https://github.com/fuadoglu/eve/issues/18) |
| EVE-011.1 | Rezervasiya create RPC və initial receipt | EVE-009.3, EVE-010.3 | [#19](https://github.com/fuadoglu/eve/issues/19) |
| EVE-011.2 | Qısa form/detail və server balance | EVE-011.1 | [#19](https://github.com/fuadoglu/eve/issues/19) |
| EVE-011.3 | Retry/validation mobil E2E | EVE-011.2 | [#19](https://github.com/fuadoglu/eve/issues/19) |
| EVE-012.1 | Tarix/qiymət və eyni sahibdə move | EVE-010.3, EVE-011.3 | [#20](https://github.com/fuadoglu/eve/issues/20) |
| EVE-012.2 | Giriş/çıxış/ləğv/no-show transitions | EVE-012.1 | [#20](https://github.com/fuadoglu/eve/issues/20) |
| EVE-012.3 | Placement tarixçə və permission regressiyası | EVE-012.2 | [#20](https://github.com/fuadoglu/eve/issues/20) |
| EVE-013.1 | Bu gün projection və prioritet sıra | EVE-009.3, EVE-011.3, EVE-012.3 | [#21](https://github.com/fuadoglu/eve/issues/21) |
| EVE-013.2 | Agenda/ay və ev/sahib filtrləri | EVE-013.1 | [#21](https://github.com/fuadoglu/eve/issues/21) |
| EVE-013.3 | Readiness və interval query ölçümü | EVE-013.2 | [#21](https://github.com/fuadoglu/eve/issues/21) |
| EVE-014.1 | Rent/deposit/refund immutable ledger | EVE-011.3, EVE-012.3 | [#22](https://github.com/fuadoglu/eve/issues/22) |
| EVE-014.2 | Pul sheet və qalıq/artıq ödəniş | EVE-014.1 | [#22](https://github.com/fuadoglu/eve/issues/22) |
| EVE-014.3 | Refund/rounding/idempotency sınağı | EVE-014.2 | [#22](https://github.com/fuadoglu/eve/issues/22) |
| EVE-015.1 | Commission basis və rounding | EVE-014.3 | [#23](https://github.com/fuadoglu/eve/issues/23) |
| EVE-015.2 | Realtor collected/transferred/offset | EVE-015.1 | [#23](https://github.com/fuadoglu/eve/issues/23) |
| EVE-015.3 | Net istiqamət və double-income sınağı | EVE-015.2 | [#23](https://github.com/fuadoglu/eve/issues/23) |
| EVE-016.1 | Expense proposal və allocation | EVE-014.3, EVE-008.3 | [#24](https://github.com/fuadoglu/eve/issues/24) |
| EVE-016.2 | Approve/payment/recurring draft UI | EVE-016.1 | [#24](https://github.com/fuadoglu/eve/issues/24) |
| EVE-016.3 | Sum/cross-owner/paid-state sınağı | EVE-016.2 | [#24](https://github.com/fuadoglu/eve/issues/24) |
| EVE-017.1 | Kontakt və task state müqaviləsi | EVE-008.3, EVE-009.3 | [#25](https://github.com/fuadoglu/eve/issues/25) |
| EVE-017.2 | Scoped link və WhatsApp fallback | EVE-017.1 | [#25](https://github.com/fuadoglu/eve/issues/25) |
| EVE-017.3 | Prefetch/revoke/scope mənfi sınağı | EVE-017.2 | [#25](https://github.com/fuadoglu/eve/issues/25) |
| EVE-018.1 | Reservation cleaning upsert/readiness | EVE-012.3, EVE-017.3 | [#26](https://github.com/fuadoglu/eve/issues/26) |
| EVE-018.2 | Outbox/cron/dedupe və quiet hours | EVE-018.1 | [#26](https://github.com/fuadoglu/eve/issues/26) |
| EVE-018.3 | Retry/timezone/gecikmə sınağı | EVE-018.2 | [#26](https://github.com/fuadoglu/eve/issues/26) |
| EVE-019.1 | Otaq/əşya və standart şablon | EVE-006.3, EVE-009.3 | [#27](https://github.com/fuadoglu/eve/issues/27) |
| EVE-019.2 | İcazəli copy və import preview | EVE-019.1 | [#27](https://github.com/fuadoglu/eve/issues/27) |
| EVE-019.3 | Duplicate/import tenant testləri | EVE-019.2 | [#27](https://github.com/fuadoglu/eve/issues/27) |
| EVE-020.1 | Daily context və turnover events | EVE-018.3, EVE-019.3 | [#28](https://github.com/fuadoglu/eve/issues/28) |
| EVE-020.2 | Snapshot/side/revision müqaviləsi | EVE-020.1 | [#28](https://github.com/fuadoglu/eve/issues/28) |
| EVE-020.3 | Eyni gündə iki təhvil immutable sınağı | EVE-020.2 | [#28](https://github.com/fuadoglu/eve/issues/28) |
| EVE-021.1 | Token landing və ad/tərəf konteksti | EVE-017.3, EVE-020.3, EVE-022.3 | [#29](https://github.com/fuadoglu/eve/issues/29) |
| EVE-021.2 | Otaq yoxlaması və server autosave | EVE-021.1 | [#29](https://github.com/fuadoglu/eve/issues/29) |
| EVE-021.3 | Foto/səs fallback və offline truthful sınağı | EVE-021.2 | [#29](https://github.com/fuadoglu/eve/issues/29) |
| EVE-022.1 | Upload intent/quota rezervi | EVE-006.3, EVE-008.3 | [#30](https://github.com/fuadoglu/eve/issues/30) |
| EVE-022.2 | MIME/finalize/private serving | EVE-022.1 | [#30](https://github.com/fuadoglu/eve/issues/30) |
| EVE-022.3 | Revoke/EXIF/SSRF/orphan testləri | EVE-022.2 | [#30](https://github.com/fuadoglu/eve/issues/30) |
| EVE-023.1 | Guide blokları və locale draft | EVE-009.3, EVE-022.3 | [#31](https://github.com/fuadoglu/eve/issues/31) |
| EVE-023.2 | Publish/safety-private təsnifatı | EVE-023.1 | [#31](https://github.com/fuadoglu/eve/issues/31) |
| EVE-023.3 | Sabit QR export və kamera testi | EVE-023.2 | [#31](https://github.com/fuadoglu/eve/issues/31) |
| EVE-024.1 | Public strict DTO və content preview | EVE-009.3, EVE-022.3 | [#32](https://github.com/fuadoglu/eve/issues/32) |
| EVE-024.2 | Owner visibility/noindex/OG | EVE-024.1 | [#32](https://github.com/fuadoglu/eve/issues/32) |
| EVE-024.3 | HTML/JSON/media PII sızma testi | EVE-024.2 | [#32](https://github.com/fuadoglu/eve/issues/32) |
| EVE-025.1 | Available nights/departures projection | EVE-010.3, EVE-024.3 | [#33](https://github.com/fuadoglu/eve/issues/33) |
| EVE-025.2 | Date interval quote/copy UX | EVE-025.1 | [#33](https://github.com/fuadoglu/eve/issues/33) |
| EVE-025.3 | Stale cache/range/checkout-edge sınağı | EVE-025.2 | [#33](https://github.com/fuadoglu/eve/issues/33) |
| EVE-026.1 | Plan catalog və same-owner order lines | EVE-006.3, EVE-008.3, EVE-003.2 | [#34](https://github.com/fuadoglu/eve/issues/34) |
| EVE-026.2 | Calendar anchor və period application | EVE-026.1 | [#34](https://github.com/fuadoglu/eve/issues/34) |
| EVE-026.3 | Trial/leap/ay sonu/plan keçid sınağı | EVE-026.2 | [#34](https://github.com/fuadoglu/eve/issues/34) |
| EVE-027.1 | Payriff hosted checkout adapter | EVE-026.3, EVE-003.2 | [#35](https://github.com/fuadoglu/eve/issues/35) |
| EVE-027.2 | Verified inbox/reconcile transaction | EVE-027.1 | [#35](https://github.com/fuadoglu/eve/issues/35) |
| EVE-027.3 | Forgery/replay/out-of-order sandbox | EVE-027.2 | [#35](https://github.com/fuadoglu/eve/issues/35) |
| EVE-028.1 | Owner billing/renewal və toplu order | EVE-027.3, EVE-014.3, EVE-017.3, EVE-023.3, EVE-024.3 | [#36](https://github.com/fuadoglu/eve/issues/36) |
| EVE-028.2 | Module entitlement/read-only davranışı | EVE-028.1 | [#36](https://github.com/fuadoglu/eve/issues/36) |
| EVE-028.3 | Expiry/safety/task-window regressiyası | EVE-028.2 | [#36](https://github.com/fuadoglu/eve/issues/36) |
| EVE-029.1 | Scoped export və təhlükəsiz fayl | EVE-014.3, EVE-016.3, EVE-020.3, EVE-027.3 | [#37](https://github.com/fuadoglu/eve/issues/37) |
| EVE-029.2 | Operator/support/reasoned audit | EVE-029.1 | [#37](https://github.com/fuadoglu/eve/issues/37) |
| EVE-029.3 | PII/secret/CSV injection yoxlaması | EVE-029.2 | [#37](https://github.com/fuadoglu/eve/issues/37) |
| EVE-030.1 | Birləşmiş E2E/security/performance | EVE-001.3, EVE-002.3, EVE-003.3, EVE-004.3, EVE-005.3, EVE-006.3, EVE-007.3, EVE-008.3, EVE-009.3, EVE-010.3, EVE-011.3, EVE-012.3, EVE-013.3, EVE-014.3, EVE-015.3, EVE-016.3, EVE-017.3, EVE-018.3, EVE-019.3, EVE-020.3, EVE-021.3, EVE-022.3, EVE-023.3, EVE-024.3, EVE-025.3, EVE-026.3, EVE-027.3, EVE-028.3, EVE-029.3 | [#38](https://github.com/fuadoglu/eve/issues/38) |
| EVE-030.2 | DB+media restore və rollback drill | EVE-030.1 | [#38](https://github.com/fuadoglu/eve/issues/38) |
| EVE-030.3 | Release evidence və handoff gate | EVE-030.2 | [#38](https://github.com/fuadoglu/eve/issues/38) |

## Xarici gate-lər

EXT03 SMTP EVE-007.3; EXT04/05 Payriff EVE-027.3; EXT09 real istifadəçi EVE-002.3. Bunlar müstəqil scaffold/schema/UI işini bloklamır, amma aid acceptance və release Done sayıla bilməz.
