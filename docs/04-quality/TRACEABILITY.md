# Tələb → ekran → müqavilə → task → test

Maşın mənbəyi: [traceability.json](traceability.json). API/data/test dəyişəndə bu xəritə yenilənir; yoxlayıcı köhnəlmiş əməliyyat və cədvəl əlaqəsini rədd edir. Sadəcə ID-nin mövcudluğunu yoxlamaqla kifayətlənmir.

| Tələb | Ekranlar | API / cədvəl sayı | Parent task | Qəbul |
|---|---|---|---|---|
| R01 — Şifrəsiz giriş | UI01, UI02, UI03, UI18 | 7 / 1 | EVE-003, EVE-007 | AT01, AT02, AT03 |
| R02 — Tenant və çox ev | UI06, UI07, UI16 | 6 / 2 | EVE-006, EVE-008 | AT04, AT05, AT06 |
| R03 — Çoxsahibli menecer | UI06, UI07, UI16 | 8 / 4 | EVE-006, EVE-008 | AT04, AT05, AT06 |
| R04 — Rezervasiya və təqvim | UI04, UI05, UI08 | 11 / 6 | EVE-010, EVE-011, EVE-012, EVE-013 | AT07, AT08, AT09, AT10 |
| R05 — Kirayə pul uçotu | UI07, UI08 | 9 / 7 | EVE-011, EVE-014, EVE-015 | AT11, AT12, AT13 |
| R06 — Xərclər | UI07, UI09 | 9 / 4 | EVE-016 | AT14 |
| R07 — Tapşırıq və paylaşım | UI09, UI12 | 22 / 6 | EVE-017, EVE-018 | AT15, AT16 |
| R08 — Hazırlıq və təmizlik | UI04, UI07, UI09 | 5 / 2 | EVE-012, EVE-013, EVE-018 | AT10, AT16 |
| R09 — İnventar və təhvil | UI10, UI11 | 26 / 13 | EVE-019, EVE-020, EVE-021 | AT12, AT17, AT18, AT19 |
| R10 — Çoxdilli QR təlimatı | UI13, UI15 | 19 / 5 | EVE-022, EVE-023 | AT20, AT21, AT28 |
| R11 — Public təqdimat | UI14 | 11 / 4 | EVE-024, EVE-025 | AT08, AT22, AT23, AT24 |
| R12 — Ev üzrə SaaS abunə | UI06, UI17 | 10 / 7 | EVE-008, EVE-026, EVE-027, EVE-028 | AT25, AT26, AT27, AT28, AT32 |
| R13 — Mobil UX və sürət | UI01, UI04, UI05, UI06, UI08, UI09, UI11, UI12, UI14, UI15 | 116 / 0 | EVE-002, EVE-009, EVE-030 | AT29, AT30, AT31 |
| R14 — Audit, export və istismar | UI18, UI19 | 6 / 3 | EVE-029, EVE-030 | AT32, AT33, AT34 |
| R15 — İlkin quraşdırma və import | UI06, UI10, UI18 | 7 / 2 | EVE-019, EVE-029 | AT35 |
| R16 — Bildirişlər | UI04, UI18 | 8 / 4 | EVE-018 | AT15, AT36 |

## Oxuma nümunəsi

R09 → UI10/UI11 → inventory/inspection API əməliyyatları → data dictionary-də R09 cədvəlləri → EVE-019–021 və onların .1/.2/.3 paketləri → AT17–19. Dəqiq operationId və cədvəl adları JSON xəritəsindədir.

UI və task əlaqəsi insan tərəfindən review edilir; avtomatik hesablama biznes mənasının doğruluğunu təkbaşına sübut etmir. Acceptance nəticələri ayrıca evidence-dədir.
