# Məlumat modeli və DB invariantları

R02–12. Bu məntiqi schema-dır; executable migrations M1-də yazılacaq. UUID əsas identifikator, timestamp UTC, local_date Asia/Baku tarixi, pul bigint/integer qəpik, currency AZN.

## Əsas cədvəllər

| Cədvəl | Əsas sahələr / məhdudiyyət |
|---|---|
| profiles | user_id(auth FK), display_name?, phone?, locale; rol sütunu yoxdur |
| owner_accounts | id, owner_user_id UNIQUE; bir şəxsin sahiblik tenant-ı |
| properties | id, owner_account_id, name, area, settings, version, archived_at |
| property_memberships | property_id,user_id UNIQUE; daily/full; revoked_at |
| manager_invites | normalized_email, owner_account_id, token_hash, expires_at,status |
| invite_properties | invite_id,property_id,permission; cross-tenant FK qadağası |
| contacts | id,owner_account_id,name,phone,service_type,private_note |
| contact_properties | contact_id,property_id; eyni owner constraint |
| reservations | id,owner_account_id,property_id,guest_name,phone?,dates,times,status,total_minor,version |
| occupancy | property_id,owner_account_id,source_id,source_kind,date_range,active,expires_at? |
| rent_entries | id,reservation_id,property_id,owner_account_id,type,amount_minor,custodian,original_id?,actor_id |
| realtor_accounts | contact_id,property_id/reservation scope,commission_kind,basis,settlement events |
| expenses | id,owner_account_id,category,total_minor,approval,payment_status,actor |
| expense_allocations | expense_id,property_id,amount_minor; sum=expense.total |
| expense_payments | expense_id,amount_minor,date,actor; approved amount-dan artıq deyil |
| tasks | id,property_id,reservation_id?,kind,title,due_at,assignee_contact_id?,state,version |
| rooms | id,property_id,name,position |
| inventory_items | id,room_id,property_id,name,quantity,unit,status,version,min_stock? |
| inspection_days | id,property_id,local_date UNIQUE(property_id,local_date) |
| inspection_events | id,day_id,property_id,handover_key; bir gündə çox hadisə |
| inspection_snapshots | event_id,inventory_version,snapshot_json; başlanğıcda immutable |
| inspection_submissions | id,event_id,side,revision,claimed_name,actor_user_id?,state |
| inspection_answers | submission_id,snapshot_item_id,count?,condition,note?,media_ref? |
| guides | id,property_id,stable_slug,classification,guidance_kind |
| guide_versions | guide_id,locale,version,blocks,published_at; draft ayrı |
| public_pages | property_id,slug UNIQUE,published_version,enabled,show_price/dates/map |
| access_links | id,token_hash UNIQUE,resource_type,resource_id,side?,scopes,expires_at,revoked_at |
| media_assets | id,property_id,classification,bucket,key,mime,size,status |
| trial_claims | owner_account_id UNIQUE,property_id,started_at,ends_at |
| subscriptions | property_id UNIQUE,current_end,anchor,status; provider state-dən ayrı |
| subscription_periods | property_id,order_line_id UNIQUE,starts_at,ends_at,plan |
| billing_orders | id,owner_account_id,currency,amount_minor,state,provider_order_id UNIQUE |
| billing_order_lines | order_id,property_id,plan,price_minor,entitlement_applied_at |
| payment_events | provider,event_key UNIQUE,payload_redacted,verification_state |
| idempotency_keys | actor_scope,key,request_hash,result_ref; UNIQUE(actor_scope,key) |
| outbox | id,event_kind,resource_id,dedupe_key UNIQUE,attempts,next_attempt_at,status |
| audit_events | actor,capability,resource,redacted_diff,request_id,created_at |
| support_requests | owner/user,category,message,status; token/secret qəbul etmir |

## Tenant sərhədi

properties üçün UNIQUE(id,owner_account_id). Child cədvəllər (property_id,owner_account_id) kompozit FK ilə bağlanır. Reservation-a bağlanan entry/task üçün reservation_id + property_id + owner_account_id eyni tuple olmalıdır. Expense allocation və contact mapping eyni sahibi keçə bilməz. User göndərdiyi owner_account_id ilə qərar vermir.

Membership helper-lər current authenticated user və cari DB membership-dən istifadə edir. JWT-də “manager=true” icazə sübutu deyil. RLS köməkçi policy recursion test olunur.

## Rezervasiya toqquşması

PostgreSQL daterange [check_in,check_out), GiST exclusion: property_id bərabər və active date_range overlap ola bilməz. btree_gist extension M1-də konfiqurasiya edilir. Confirmed, hold və manual block bir occupancy cədvəlindədir ki, ayrı cədvəllərdən yan keçmə olmasın.

expires_at < now() kimi dəyişən zaman partial index predicate-də istifadə edilmir. Əvəzinə hər write property lock götürür, expired hold occupancy-ni inactive edir, sonra insert/update edir. Cron də eyni yolu istifadə edir. Keçid və property move bir transaction; deadlock üçün lock-lar UUID sırası ilə alınır.

Reservation cancelled/completed early-release keçidi occupancy ilə eyni transaction-da yenilənir. Snapshot/finance əlaqələri səssiz başqa property-yə köçürülmür.

## Pul invariantları

amount_minor > 0; sıfır quote xüsusi flag ilə, entry sıfır deyil. Refund/reversal original event və qalıq refundable amount ilə yoxlanır. Deposit rent ledger category-dən ayrıdır. Expense allocation sum deferred transaction trigger və ya RPC commit yoxlaması ilə təmin edilir. Payment applied unique order_line və provider event ilə bir dəfədir.

Realtorun collected rent entry-si ilə owner-a settlement entry-si fərqli növdür; settlement yeni customer receipt deyil. Cash flow ilə accrual profitability fərqli projection-dır.

## İnventar invariantları

inspection_day tək günlük konteksdir, cavabların unique açarı deyil. Event-side-revision unikal; hər tərəfin bir açıq draft-ı var. Completed submission overwrite edilmir. Correction yeni revision yaradır və original_id ilə bağlanır.

Inventarın daimi say/vəziyyəti check form tamamlananda avtomatik dəyişmir; səlahiyyətli update ayrı audit hadisəsidir. Token context property/event/side-i müəyyən edir, request body bunu dəyişə bilməz.

## Status və silinmə

Soft archive ev və əlaqəli metadata üçün; maliyyə append/reversal, completed inspection immutable. Hüquqi silinmə request-i ayrıca retention prosesidir, “archive” deyil. Audit PII minimum saxlayır. Backup ilə media bərpa uyğunluğu RUNBOOK-da yoxlanılır.

## Fixture

İki sahib A/B, hərəsində iki ev; menecer M A1 daily/B1 full, A2/B2-yə icazəsiz; owner A həm B2-də manager ola bilən ayrıca test. Expired membership, expired subscription, paid trial, same-day turnovers, cancelled reservation, missing guide locale və storage access fixtures məcburidir.
