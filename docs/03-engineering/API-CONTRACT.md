# API və əməliyyat müqaviləsi

**Normativ maşın müqaviləsi:** [openapi.json](openapi.json), OpenAPI 3.1.0. JSON OpenAPI-nin standart formatıdır; ayrıca YAML nüsxəsi saxlanılmır ki, iki mənbə ayrılmasın. Bu sənəd implementasiya təlimatıdır, işlək server deyil.

## Oxuma qaydası

Hər operationId üçün request/response sahələri, required, tip, format, limit, enum və əlavə sahə qadağası openapi.json-da müəyyənləşir. Bu mətn əsas semantikanı və bütün endpoint-lərin xəritəsini saxlayır. Server Action olsa belə eyni domain əməliyyatını çağırır; ikinci biznes qaydası yaratmır.

Hər əməliyyatda x-requirements tələb ID-lərini, x-capability səlahiyyəti, x-entitlement abunə rejimini göstərir. UI-da düyməni gizlətmək yoxlama deyil. Bütün server və RLS/storage sərhədləri eyni məntiqə uyğun olmalıdır.

## Ümumi transport müqaviləsi

| Mövzu | Qayda |
|---|---|
| Prefix | Eyni origin /api/v1 |
| Uğur | {data, meta:{request_id, version?}}; resource version ayrıca DTO-da |
| Xəta | {error:{code,message,field_errors?,request_id}}; raw SQL/provider cavabı yoxdur |
| ID | UUID; public slug və bearer token ayrı, təsadüfi və qeyri-ardıcıl |
| Pul | Integer qəpik, AZN, 0…9007199254740991; pul hadisəsi >0 |
| Vaxt | Timestamp ISO-8601 UTC; local_date Asia/Baku; gecələmə [check_in,check_out) |
| Form validasiyası | Client rahatlıq üçündür; server və DB məcburidir |
| Mutasiya | Same-origin/CSRF yoxlaması; tətbiq route-u arbitrary origin-dən yazı qəbul etmir |
| İdempotentlik | Auth/provider istisna, bütün domain write-da Idempotency-Key; eyni key/fərqli payload 409 |
| Versiya | Dəyişiklikdə expected_version; köhnə versiya 409, səssiz overwrite yoxdur |
| Pagination | Cursor, limit default30/max100; əməliyyatda fərqli limit varsa schema əsasdır |
| Calendar | Auth interval max93 gün; public horizon bugün+12 ay və max366 gün |

İdempotency key actor+operation üzrə scope olunur. Eyni actor/key/payload retry əvvəlki nəticəni verir. Eyni key digər actor üçün məlumat açıqlamır. 24 saatlıq replay cache maliyyə/event/order-line unikal tətbiq invariantını əvəz etmir; həmin invariant daimi qalır. Create üçün client owner_id/actor_id qəbul edilmir. Server bunları sessiya və səlahiyyətli property-dən çıxarır.

### Versiya istisnası

Yeni guide locale ilk dəfə yazılanda expected_version=0 qəbul edilir; yalnız locale mövcud deyilsə. Mövcud locale üçün faktiki >=1 versiya tələb olunur. Digər update-lərdə 0 istifadə edilmir. Create endpoint-ləri olmayan resource version-u tələb etmir.

## Giriş və scoped authorization

- SessionCookie OpenAPI-də tətbiqin məntiqi cookie sərhədidir. Supabase actual cookie adları adapterdə map olunur; DTO ilə access/refresh token qaytarılmır. Cookie imkanları test olunmadan HttpOnly zəmanəti yazılmır.
- Browser /s/{token} səhifəsi POST /link-session ilə tokeni resource-scoped eve_scope cookie-sinə dəyişir. Bu görünməz auth bootstrap-dır, task qəbul/completion yaratmır. Sonrakı scoped API-lər cookie və path token hash-inin uyğunluğunu tələb edir. OpenAPI security-də anonymous fallback yoxdur. Etibarsız/bitmiş keçid 410-dur.
- Scope resource, event-side və media aidiyyətini müəyyənləşdirir; body-də property_id/actor_id ilə dəyişdirilə bilməz. Token səhifələri no-store/no-referrer-dir.
- GET task/inspection/reservation/order vəziyyətini dəyişmir. Cookie bootstrap domain hadisəsi kimi qəbul/completion yaratmır.
- Session və scoped cookie endpoint-lərində CSRF/origin müdafiəsi var; tokenlər log/analytics-ə düşmür.

## Abunə rejimləri

| x-entitlement | Mənası |
|---|---|
| active | Ev trialing və ya active; current capability ayrıca yoxlanır |
| read_only | Əvvəlki səlahiyyət sərhədində expired ev də oxunur; export ayrıca capability tələb edir |
| exempt | Giriş, hesab, dəstək, billing, revoke kimi abunədən asılı olmayan əməliyyat; authorization qalır |
| existing_link_window | Əvvəl yaradılmış task/inspection/guest keçidi öz expiry və write window-u daxilində; yeni iş yaratmır |
| public_enabled | Public təqdimat aktiv və abunə uyğun; dates/price/map switch-i ayrıca yoxlanır |
| published_safety_or_active | Safety_public əvvəl dərc olunubsa read-only qalır; general_public üçün aktiv abunə qaydası tətbiq edilir |

## Həssas əməliyyat semantikası

### Rezervasiya

Create reservation+occupancy+initial receipt+outbox-u bir transaction-da yaradır. Hold expiry transaction daxilində yenidən yoxlanır; cron gecikməsi correctness-i pozmur. free_stay=true olmadan 0 quote qəbul edilmir. Giriş/çıxış vaxtı evdən hazır gəlir; check_out check_in-dən böyükdür. Təsdiqlənmiş gecələrə overlap DB constraint ilə rədd edilir.

Tarix/qiymət redaktəsi PATCH /reservations/{id}; ev dəyişməsi yalnız POST /reservations/{id}/move-dur. Move eyni owner daxilində source və target reservation.write hüququ tələb edir. Yeni immutable placement yaranır; əvvəlki receipt, task, inspection snapshot köhnə placement-də qalır. Source-only menecer current reservation və destination qonaq məlumatını görə bilmir. Girişdən sonra ev dəyişməsi təsdiqlənmiş state qaydasına tabedir; server frontend-dən kənar yoxlayır.

Cancel/no_show avtomatik pul qaytarmır və komissiyanı sıfırlamır. financial_decision yalnız cancel/no_show üçün verilə bilər: original receipt ID və məbləğlə rent_refunds/deposit_returns eyni transaction-da yazılır, commission_keep_minor yalnız owner/full finance.manage tələb edir. DB-də alınan pul/depozit/komissiya hadisəsi varsa financial_decision məcburidir; omission 422-dir. Pulu dəyişməmək üçün açıq mode=keep_as_is təsdiqi verilir; zədə forması avtomatik deposit allocation deyil. Erkən checkout planı dəyişmir; release_remaining_days yalnız actual checkout qeydi olan completed rezervasiyada ayrıca tarix/qiymət təsdiqi tələb edir və state completed qalır.

### Pul və xərclər

rent_receipt, rent_refund, deposit_receipt, deposit_return, deposit_to_rent/deposit_to_damage və reversal ayrı növlərdir. Refund/reversal original_id və real refundable limit tələb edir. deposit_to_rent/deposit_to_damage/reversal owner/full hüququ tələb edir; daily yalnız icazəli qonaq pul əməliyyatlarını edir. Realtor settlement customer receipt deyil. Expense allocations eyni owner və cəmi amount_minor-a bərabərdir. Daily xərc təklif edir; owner/full təsdiqləyir. Ödənilib seçimi təsdiqsiz təklifi paid kimi hesabatlaşdırmır.

### İnventar

Snapshot otaq/əşya siyahısının həmin andakı dəyişməz nüsxəsidir. Verən/alan ayrı submission-dır. saveAnswers yalnız öz tərəfinin draft-ını versiya ilə dəyişir. complete bütün otaqların explicit ok/problems/unable cavabını yoxlayır; tamamlanmış cavabı overwrite etmir. Correction yeni revision yaradır. Fayllar həmin tokenin property/event tərəfinə bağlıdır.

### Payriff

PayriffInbound providerin final xarici payload schema-sı deyil: EXT05 açıq olduğundan onun istisnası additionalProperties=true ilə ayrıca işarələnib. Bütün digər domain object-lər allowlist-dir. Endpoint adapter müqaviləsi təsdiqlənənədək production-da disabled qalır. Hadisəni qəbul etmək payment/entitlement uğuru deyil. Merchant/order/amount/currency/status serverdən yoxlanır; browser success URL paid təyin etmir. İmza sahəsi və native status enum-u uydurulmur.

### Media və guide

Draft guide blokları media_id saxlayır; public/scoped oxuma cavabları RenderedGuideBlock daxilində yalnız səlahiyyətli MediaRef verir. Public guide guest_private blok qəbul etmir. Medianın faktiki mime/ölçü/quota yoxlaması finalize mərhələsindədir; upload intent artıq media yayımlandı demək deyil. Public availability yalnız available_nights və valid_departures verir, qeyri-boş günün səbəbini yox.

## Xəta davranışı

| HTTP / code | UX və server davranışı |
|---|---|
| 400/422 VALIDATION_ERROR | Sahə xəta mətnləri, daxil edilən məlumat saxlanır |
| 401 UNAUTHENTICATED | Yenidən email girişi; private cache təmizlənir |
| 403 ENTITLEMENT_REQUIRED/FORBIDDEN | Səlahiyyət və ya abunə; başqa tenant resursunda neytral404 |
| 404 NOT_FOUND | Yoxdur və ya istifadəçidən gizlidir |
| 409 DATE_CONFLICT | Yenilənmiş uyğunluq göstərilir; seçilən tarix itmir |
| 409 VERSION_CONFLICT | Son versiyanı göstər; overwrite etmə |
| 409 IDEMPOTENCY_MISMATCH | Yeni request key yaratmadan payload dəyişdirildiyi bildirilir |
| 410 LINK_EXPIRED | Keçid bitib/ləğv edilib; owner və ya qonaq məlumatı açıqlanmır |
| 429 RATE_LIMITED | Retry-After saniyə ilə; limitsiz avtomatik retry yoxdur |
| 503 PROVIDER_UNAVAILABLE | Uğur göstərilmir; order pending qalır və reconcile mümkündür |

## Tam endpoint xəritəsi

| Metod və yol | operationId | Capability / abunə | Request → data schema |
|---|---|---|---|
| POST /auth/email-link | requestEmailLink | anonymous.email_link / exempt | EmailLinkInput → EmailLinkResult |
| POST /auth/confirm | confirmEmailLink | anonymous.email_confirm / exempt | ConfirmInput → SessionResult |
| POST /auth/logout | logoutCurrentSession | session.manage / exempt | EmptyInput → Ack |
| POST /auth/logout-all | logoutAllSessions | session.manage / exempt | EmptyInput → Ack |
| GET /me | getProfile | profile.read / exempt | — → Profile |
| PATCH /me | updateProfile | profile.manage / exempt | ProfilePatch → Profile |
| GET /properties | listProperties | property.read / read_only | — → PropertyPage |
| POST /properties | createProperty | owner / exempt | PropertyCreate → Property |
| GET /properties/{id} | getProperty | property.read / read_only | — → Property |
| PATCH /properties/{id} | updateProperty | property.manage / active | PropertyPatch → Property |
| POST /properties/{id}/archive | archiveProperty | owner / exempt | VersionInput → Property |
| POST /properties/{id}/restore | restoreProperty | owner / exempt | VersionInput → Property |
| GET /properties/{id}/memberships | listMemberships | owner / read_only | — → MembershipPage |
| POST /properties/{id}/memberships | inviteManager | owner / active | MembershipCreate → MembershipPage |
| PATCH /properties/{id}/memberships/{user} | updateMembership | owner / active | MembershipPatch → Membership |
| DELETE /properties/{id}/memberships/{user} | revokeMembership | owner / exempt | VersionInput → Ack |
| POST /invites/accept | acceptManagerInvite | session.manage / exempt | InviteAccept → MembershipPage |
| GET /contacts | listContacts | contact.read / read_only | — → ContactPage |
| POST /contacts | createContact | contact.manage / active | ContactCreate → Contact |
| PATCH /contacts/{id} | updateContact | contact.manage / active | ContactPatch → Contact |
| DELETE /contacts/{id} | archiveContact | contact.manage / active | VersionInput → Ack |
| GET /today | getToday | property.read / read_only | — → Today |
| GET /calendar | getCalendar | property.read / read_only | — → Calendar |
| GET /reservations | listReservations | reservation.read / read_only | — → ReservationPage |
| POST /reservations | createReservation | reservation.write / active | ReservationCreate → Reservation |
| GET /reservations/{id} | getReservation | reservation.read / read_only | — → Reservation |
| PATCH /reservations/{id} | updateReservation | reservation.write / active | ReservationPatch → Reservation |
| POST /reservations/{id}/transition | transitionReservation | reservation.write / active | ReservationTransition → Reservation |
| POST /blocks | createBlock | reservation.write / active | BlockCreate → Block |
| PATCH /blocks/{id} | updateBlock | reservation.write / active | BlockPatch → Block |
| DELETE /blocks/{id} | removeBlock | reservation.write / active | VersionInput → Ack |
| GET /reservations/{id}/money | listRentEntries | rent.read / read_only | — → RentEntryPage |
| POST /reservations/{id}/money | createRentEntry | rent.write / active | RentEntryCreate → RentEntry |
| GET /reservations/{id}/realtor-balance | getRealtorBalance | rent.read / read_only | — → RealtorBalance |
| POST /reservations/{id}/realtor-settlements | recordRealtorSettlement | finance.manage / active | SettlementInput → RealtorSettlement |
| GET /properties/{id}/finance | getFinanceSummary | finance.read / read_only | — → FinanceSummary |
| GET /expenses | listExpenses | finance.read / read_only | — → ExpensePage |
| POST /expenses | createExpense | expense.propose / active | ExpenseCreate → Expense |
| PATCH /expenses/{id} | updateExpense | expense.propose / active | ExpensePatch → Expense |
| POST /expenses/{id}/approve | approveExpense | finance.manage / active | VersionInput → Expense |
| POST /expenses/{id}/reject | rejectExpense | finance.manage / active | ReasonInput → Expense |
| POST /expenses/{id}/payments | recordExpensePayment | finance.manage / active | ExpensePaymentInput → Expense |
| POST /recurring-expenses | createRecurringExpense | finance.manage / active | RecurringExpenseCreate → RecurringExpense |
| PATCH /recurring-expenses/{id} | updateRecurringExpense | finance.manage / active | RecurringExpensePatch → RecurringExpense |
| GET /tasks | listTasks | task.read / read_only | — → TaskPage |
| POST /tasks | createTask | task.manage / active | TaskCreate → Task |
| GET /tasks/{id} | getTask | task.read / read_only | — → Task |
| PATCH /tasks/{id} | updateTask | task.manage / active | TaskPatch → Task |
| POST /tasks/{id}/transition | transitionTask | task.manage / active | TaskTransitionInput → Task |
| POST /tasks/{id}/confirm | confirmTask | task.manage / active | VersionInput → Task |
| POST /tasks/{id}/share-link | createTaskShareLink | task.manage / active | TaskShareInput → ShareLinkResult |
| POST /access-links | createScopedLink | link.manage / active | ShareLinkInput → ShareLinkResult |
| DELETE /access-links/{id} | revokeScopedLink | owner / exempt | EmptyInput → Ack |
| GET /s/{token}/task | readScopedTask | link.task.read / existing_link_window | — → ScopedTask |
| POST /s/{token}/accept | acceptScopedTask | link.task.accept / existing_link_window | ScopedAcceptInput → ScopedTask |
| POST /s/{token}/report-done | reportScopedTaskDone | link.task.report_done / existing_link_window | ScopedTaskDoneInput → ScopedTask |
| GET /properties/{id}/inventory | getInventory | inventory.read / read_only | — → Inventory |
| POST /properties/{id}/rooms | createRoom | inventory.manage / active | RoomCreate → Room |
| PATCH /rooms/{id} | updateRoom | inventory.manage / active | RoomPatch → Room |
| DELETE /rooms/{id} | archiveRoom | inventory.manage / active | VersionInput → Ack |
| POST /properties/{id}/inventory-items | createInventoryItem | inventory.manage / active | InventoryItemCreate → InventoryItem |
| PATCH /inventory-items/{id} | updateInventoryItem | inventory.manage / active | InventoryItemPatch → InventoryItem |
| DELETE /inventory-items/{id} | archiveInventoryItem | inventory.manage / active | VersionInput → Ack |
| POST /properties/{id}/inventory-copy | copyInventory | inventory.manage / active | InventoryCopyInput → Inventory |
| POST /properties/{id}/inventory-template | applyInventoryTemplate | inventory.manage / active | TemplateApplyInput → Inventory |
| POST /inspection-events | createInspectionEvent | inventory.manage / active | InspectionEventCreate → InspectionEvent |
| GET /inspection-events/{id} | getInspectionEvent | inventory.read / read_only | — → InspectionEvent |
| POST /inspection-events/{id}/corrections | createInspectionCorrection | inventory.manage / active | InspectionCorrectionInput → InspectionEvent |
| GET /s/{token}/answers | readScopedInspection | link.inspection.read / existing_link_window | — → ScopedInspection |
| POST /s/{token}/answers | saveScopedInspection | link.inspection.write / existing_link_window | InspectionAnswersInput → ScopedInspection |
| POST /s/{token}/complete | completeScopedInspection | link.inspection.complete / existing_link_window | InspectionCompleteInput → ScopedInspection |
| POST /media/upload-intent | createUploadIntent | media.write / active | UploadInput → UploadIntent |
| POST /media/{id}/finalize | finalizeMedia | media.write / active | EmptyInput → MediaAsset |
| DELETE /media/{id} | removeMedia | media.write / active | VersionInput → Ack |
| POST /s/{token}/media/upload-intent | createScopedUpload | link.media.write / existing_link_window | ScopedUploadInput → UploadIntent |
| POST /s/{token}/media/{id}/finalize | finalizeScopedUpload | link.media.write / existing_link_window | EmptyInput → MediaAsset |
| GET /properties/{id}/guides | listGuides | guide.read / read_only | — → GuidePage |
| POST /guides | createGuide | guide.manage / active | GuideCreate → Guide |
| PATCH /guides/{id} | updateGuide | guide.manage / active | GuidePatch → Guide |
| GET /guides/{id}/locales/{locale} | getGuideLocale | guide.read / read_only | — → GuideLocale |
| PUT /guides/{id}/locales/{locale} | saveGuideLocale | guide.manage / active | GuideLocaleInput → GuideLocale |
| POST /guides/{id}/publish | publishGuideLocale | guide.manage / active | GuidePublishInput → GuideLocale |
| POST /guides/{id}/qr | exportGuideQR | guide.read / read_only | EmptyInput → QRResult |
| GET /properties/{id}/public-settings | getPublicSettings | owner / read_only | — → PublicSettings |
| PATCH /properties/{id}/public-settings | updatePublicSettings | owner / active | PublicSettingsPatch → PublicSettings |
| POST /properties/{id}/public-settings/rotate | rotatePublicSlug | owner / exempt | VersionInput → PublicSettings |
| PUT /properties/{id}/public-content | savePublicContent | property.manage / active | PublicContentInput → PublicProperty |
| GET /public/properties/{slug} | readPublicProperty | public.published.read / public_enabled | — → PublicProperty |
| GET /public/properties/{slug}/availability | readPublicAvailability | public.availability.read / public_enabled | — → Availability |
| POST /public/properties/{slug}/quote | quotePublicStay | public.quote / public_enabled | QuoteInput → Quote |
| GET /public/guides/{slug} | readPublicGuide | public.guide.read / published_safety_or_active | — → PublicGuide |
| GET /s/{token}/guest-guide | readGuestGuide | link.guest_guide.read / existing_link_window | — → GuestGuide |
| GET /billing/catalog | getBillingCatalog | owner / exempt | — → BillingCatalog |
| GET /properties/{id}/subscription | getSubscription | owner / read_only | — → Subscription |
| POST /billing/orders | createBillingOrder | owner / exempt | OrderCreate → BillingOrder |
| GET /billing/orders/{id} | getBillingOrder | owner / exempt | — → BillingOrder |
| POST /billing/payriff/events | receivePayriffEvent | provider.verify / exempt | PayriffInbound → PayriffAck |
| POST /billing/orders/{id}/reconcile | reconcileBillingOrder | owner / exempt | VersionInput → BillingOrder |
| POST /imports/preview | previewImport | import.manage / active | ImportPreviewInput → ImportPreview |
| POST /imports/{id}/commit | commitImport | import.manage / active | ImportCommitInput → ImportPreview |
| POST /exports | createExport | export.scoped / read_only | ExportInput → ExportJob |
| GET /exports/{id} | getExport | export.scoped / read_only | — → ExportJob |
| POST /support | createSupportRequest | session.manage / exempt | SupportCreate → SupportRequest |
| GET /notifications | listNotifications | session.manage / exempt | — → NotificationPage |
| POST /notifications/{id}/read | markNotificationRead | session.manage / exempt | VersionInput → Notification |
| GET /me/notification-preferences | getNotificationPreferences | profile.read / exempt | — → NotificationPreferences |
| PATCH /me/notification-preferences | updateNotificationPreferences | profile.manage / exempt | NotificationPreferencesPatch → NotificationPreferences |
| POST /me/push-subscriptions | registerPushSubscription | session.manage / exempt | PushSubscriptionInput → Ack |
| GET /properties/{id}/audit | getPropertyAudit | audit.read / read_only | — → AuditPage |
| GET /operator/health | getOperatorHealth | operator.allowlisted / exempt | — → OperatorHealth |
| POST /operator/orders/{id}/review | reviewOperatorOrder | operator.allowlisted / exempt | OperatorOrderReview → BillingOrder |
| POST /reservations/{id}/move | moveReservationProperty | reservation.write_both_properties / active | ReservationMoveInput → Reservation |
| GET /media/{id}/access | getMediaAccess | media.read / read_only | — → MediaAccess |
| GET /s/{token}/media/{id}/access | getScopedMediaAccess | link.media.read / existing_link_window | — → MediaAccess |
| GET /public/guide-indexes/{slug} | readPublicGuideIndex | public.guide.read / published_safety_or_active | — → PublicGuideIndex |
| POST /link-session | exchangeScopedLink | anonymous.link_exchange / existing_link_window | LinkSessionInput → LinkSessionResult |

## Maşın yoxlamasının qəbul şərtləri

1. OpenAPI 3.1 validator bütün sənədi qəbul edir.
2. Bütün local $ref hədəfləri mövcuddur; operationId unikal, path parametrləri declared və required-dır.
3. Domain request/response object-lərində əlavə sahə qəbul edilmir; Payriff raw adapter istisnası açıqdır.
4. Nümunə payload-ların valid/invalid gözləntiləri JSON Schema validator ilə yoxlanır.
5. Runtime mərhələsində eyni kontrakt API/RPC integration testinə bağlanır. Sənəd schema-sının keçməsi işləyən server, RLS, Payriff və ya real mobil UX sübutu deyil.

Bu revision-da müqavilə tamamlanıb; executable API və provider adapter implementasiyası EVE task-ları ilə ayrıca icra edilir.


## API → DB sahə müqaviləsi

[field-bindings.json](field-bindings.json) ad dəyişmələrini, string limitlərini, canonical enum-ları və derived/association sahələrini müəyyən edir. `node scripts/verify-contracts.mjs` bu əlaqələri schema və data dictionary-yə qarşı yoxlayır. Private scoped media yalnız hər fetch-də cari link/placement/səlahiyyət yoxlayan proxy URL-dən verilir; direct signed read URL qaytarılmır. Move/cancel/no_show köhnə guest-private linklərini atomik bağlayır.
