# API və əməliyyat müqaviləsi

R01–16. Bu sənəd normativ endpoint dizaynıdır, hazır endpoint və OpenAPI generatoru deyil. M0/M1-də OpenAPI 3.1 YAML buna uyğun yaradılmalı, schema lint və contract test CI-a daxil edilməlidir. Server Actions UI wrapper ola bilər, domain əməliyyatını ayrıca uydurmamalıdır.

## Ümumi qaydalar

- Prefix /api/v1; JSON; IDs UUID; money integer minor AZN.
- Auth server session-dən. Mutation eyni origin + CSRF müdafiəsi + JSON content type yoxlaması.
- Hər write request idempotency key və update üçün expected_version qəbul edir.
- Eyni key/eyni payload eyni nəticəni verir; eyni key/fərqli payload 409.
- Uğur: {data,meta:{request_id,version?}}.
- Xəta: {error:{code,message,field_errors?,request_id}}; raw SQL/provider secret çıxmır.
- Pagination cursor+limit, max 100. Calendar max 93 günlük authenticated interval; public availability max 12 aylıq horizon.
- Həssas olmayan health endpoint auth bypass-ına çevrilmir.

| Kod | Davranış |
|---|---|
| 400/422 | Sahə validasiyası; form dəyərləri saxlanır |
| 401 | Sessiya yoxdur/bitib; neytral giriş |
| 403 | Capability və ya entitlement çatmır; səlahiyyətsiz resursda 404 siyasəti |
| 404 | Mövcud deyil və ya gizlidir |
| 409 DATE_CONFLICT | Uyğunluq dəyişib; təqvimi yenilə |
| 409 VERSION_CONFLICT | Son məlumatı göstər, overwrite etmə |
| 409 IDEMPOTENCY_MISMATCH | Açar başqa payload üçün istifadə olunub |
| 410 LINK_EXPIRED | Neytral expired/revoked keçid |
| 429 | Rate limit, Retry-After |
| 503 | Müvəqqəti service/provider xətası; saxta uğur yoxdur |

## Endpoint xəritəsi

| Metod / yol | Capability | Əsas kontrakt |
|---|---|---|
| POST /auth/email-link | anonymous rate-limited | email, allowed_redirect; həmişə neytral cavab |
| POST /auth/logout-all | authenticated | bütün refresh session-ları ləğv; cari access TTL izahı |
| GET/POST /properties | user / owner | yalnız oxuna bilən evlər; create owner tenant-dan |
| PATCH /properties/{id} | property.manage | expected_version + allowlisted fields |
| POST /properties/{id}/memberships | owner | email/invite, daily/full; user_id/client owner etibarsızdır |
| DELETE /properties/{id}/memberships/{user} | owner | membership revoke dərhal |
| GET /calendar | property.read | property IDs, from/to; hər ID ayrı yoxlanır |
| POST /reservations | reservation.write | property_id, dates, guest, quote, initial_receipt? |
| PATCH /reservations/{id} | reservation.write | expected_version; tarix/qiymət/move transactional |
| POST /reservations/{id}/transition | reservation.write | action,expected_version,financial_decision? |
| POST /reservations/{id}/money | rent.write | amount_minor,kind,custodian,original_id? |
| GET /properties/{id}/finance | finance.read | owner/full; daily rədd edilir |
| POST /expenses | expense.propose/approve | allocation,amount_minor,category; proposed/approved server qərarı |
| POST /expenses/{id}/approve | finance.manage | allocations üzrə tam hüquq |
| POST /tasks | task.manage | property,title,due_at,contact? |
| POST /tasks/{id}/share-link | task.manage | resource-scoped link; actual sent deyil |
| POST /tasks/{id}/confirm | task.manage | reported_done → completed |
| POST /inspection-events | inventory.manage | property,date,handover_key; idempotent snapshot |
| GET/POST /s/{token}/answers | link scope | snapshot answer update; actor/property body-dən alınmır |
| POST /s/{token}/complete | link scope | version,room confirmations; immutable finalize |
| POST /s/{token}/accept | task.accept | explicit action; GET mutate etmir |
| POST /s/{token}/report-done | task.complete | note/media/expense proposal; owner confirmation ayrı |
| POST /media/upload-intent | media.write or scoped link | mime,size,class; short-lived upload |
| POST /media/{id}/finalize | eyni scope | faktiki file yoxlanması; sonra istifadəyə açılır |
| PUT /guides/{id}/locales/{locale} | guide.manage | safe blocks,draft version |
| POST /guides/{id}/publish | guide.manage | classification invariant; safety/private ayrı |
| PATCH /properties/{id}/public-settings | owner | enable,show_dates/price/map,rotate |
| GET /public/properties/{slug} | published | safe PublicPropertyDTO |
| GET /public/properties/{slug}/availability | public enabled+dates | available_nights,valid_departures,horizon; səbəb yoxdur |
| POST /public/properties/{slug}/quote | public enabled+price | dates; qiymət təxminidir, rezervasiya yaratmır |
| POST /billing/orders | owner | property IDs+plan; məbləğ server kataloqundan |
| POST /billing/payriff/events | provider verified | inbox; status verification; duplicate no-op |
| GET /billing/orders/{id} | owner | pending/verified/active, sanitized failure |
| POST /imports/preview | owner/full scoped | CSV/XLSX, schema,size, mapping |
| POST /imports/{id}/commit | eyni capability | approved preview hash; transactional batch |
| POST /exports | owner/full scope | tenant-safe async file; private short URL |

## Public DTO allowlist

id (public identifier), name, area_label, published_description, published_media, amenities, room/bed/guest counts, rules, default_times, enabled quote/map fields, supported_locales. owner ID, phone/email, reservation IDs, internal address, guide-private blocks yoxdur.

## Misal: reservation create

Request: property_id, check_in="2026-11-12", check_out="2026-11-15", total_minor=30000, guest_name, status="confirmed", initial_receipt={amount_minor:10000,kind:"rent",custodian:"owner"}.

Server evi, capability, entitlement və overlap yoxlayır. Reservation+occupancy+receipt+outbox atomik yaranır. Response reservation summary və balance=20000. Request retry yeni receipt yaratmır.

## OpenAPI icra qapısı

Hər endpoint request/response/error schema, auth və capability qeyd etməlidir. OpenAPI-dən runtime/client types uyğundur. Contract tests real route/RPC ilə davranışı yoxlayır; schema daxilində yazılan nümunəni yenidən assert etmək kifayət deyil.
