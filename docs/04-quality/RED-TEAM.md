# Red-team risk reyestri

Bu, sənədlər üzrə üç müstəqil baxışın sintezidir: UX, security/data, delivery. Tətbiq penetration testi deyil. **Riskin sənəddə həlli implementasiyada bağlandığını bildirmir.**

Səviyyə: P0 kritik data/pul bütövlüyü; P1 əsas axın/təhlükəsizlik; P2 orta UX/istismar. P0/P1 açıq ikən production buraxılışı yoxdur.

| Risk | Səviyyə | Hücum/səhv | Məcburi nəzarət | Sübut |
|---|---|---|---|---|
| RT01 | P0 | Bir owner/manager digər tenant-a girir | Property capability+RLS+composite FK | AT04–06 |
| RT02 | P0 | Eyni tarix iki qonağa satılır | Unified occupancy exclusion və transaction lock | AT07–10 |
| RT03 | P0 | Forged/replay Payriff müddəti artırır | Server verify+unique apply+reconcile | AT26–27 |
| RT04 | P1 | Daily manager hidden finance export görür | Ayrı finance capability, API/storage test | AT06 |
| RT05 | P1 | Public cavab dolu/blok səbəbi və PII verir | Allowlist DTO, RSC/OG audit | AT23–24 |
| RT06 | P1 | noindex məxfilik kimi qəbul edilir | Public data açıq sayılır, private token ayrıdır | AT21–24 |
| RT07 | P1 | Scanner magic linki sərf edir | Explicit confirm, replay/prefetch test | AT03 |
| RT08 | P1 | Revoked manager köhnə session-la yazır | Cari membership hər request-də | AT05 |
| RT09 | P1 | Task GET qəbul/completion edir | Safe GET, explicit idempotent POST | AT15–16 |
| RT10 | P1 | Token başqa işin foto/məlumatını açır | Resource+side scope, hash, expiry, revoke | AT19–21 |
| RT11 | P1 | Eyni gündə təhvil cavabları overwrite olur | Day/event/side/revision ayrılığı | AT17–19 |
| RT12 | P1 | Adsız/hüquqsuz cavab şəxsiyyət və zərər sübutu sayılır | Claimed identity, manual qərar, immutable history | AT12, AT18 |
| RT13 | P1 | Deposit gəlir, realtor transferi ikinci gəlir sayılır | Ayrı ledger növləri və server math | AT11–14 |
| RT14 | P1 | Offline saxta uğur və ikiqat qeyd | Server ack, idempotency, truthful autosave | AT30 |
| RT15 | P1 | Subscription expiry safety təlimatını bağlayır | Published safety read-only qalır | AT21, AT28 |
| RT16 | P1 | Cache/log/upload/backup dolayı sızma | Private no-store, redaction, private bucket, restore | AT02, AT23, AT32–33 |
| RT17 | P2 | Hər gün boş ev overdue inventar task-ı verir | Context ≠ required task | AT17 |
| RT18 | P2 | “Hamısı yaxşı” əvvəlcədən təsdiqlənir | Otaq görünür, explicit confirm, unable seçimi | AT19, AT29 |
| RT19 | P2 | Bildiriş spamı və timezone xətası | Dedupe, quiet hours, Bakı local_date | AT36 |
| RT20 | P1 | Repo docs/PR işi test olunmuş kod kimi göstərir | Status/evidence, branch review, gate | AT34, DoD |

## Bağlanma qaydası

Issue-da risk ID, attack fixture, affected commit, real test, reviewer və nəticə göstərilir. “Nəzərə alındı” bağlanma sübutu deyil. Residual risk sahibə aydın yazılır. Provider dəstəyi və hüquqi qərar olmadıqda implementasiya agenti təxminlə release gate-i keçmir.

## Sənədləşmə zamanı bağlanan ziddiyyətlər

- Şifrə/login ayrı registration axını ləğv; vahid email flow.
- Finance visibility rezervasiya qiyməti ilə qarışdırılmır.
- Gündəlik inventar cavabının unique açarı yalnız tarix deyil.
- QR safety-ni 7 gün sonra bağlama təklifi son qərarla əvəz edildi.
- WhatsApp delivery/read iddiası çıxarıldı.
- Bir əmlakdan digər sahibin əmlakına paid reservation move qadağan edildi.
- Bir neçə sahibin ümumi mənfəəti bir rəqəmdə göstərilmir.
- Vaxtdan asılı partial exclusion predicate əvəzinə explicit expired hold cleanup+lock seçildi.
