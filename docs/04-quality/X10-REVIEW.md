# X10 düşüncə və review çərçivəsi

“X10THINK” burada on ayrı baxışla qərar keyfiyyətini artıran layihə metodudur; ayrıca məhsul, elmi sertifikat və ya avtomatik keyfiyyət zəmanəti deyil. Daxili düşüncə protokolu deyil, komandanın yoxlaya biləcəyi nəticə cədvəlidir.

| Baxış | Sual | Eve qərarı | Sübut |
|---|---|---|---|
| 1. Məhsul | Sahib hansı işi görür? | 3 əsas ekran, təkrar məlumat girişi yoxdur | R01–16 |
| 2. Sadəlik | Hansı addımı silə bilərik? | Kontekstli +, opsional sahələr, hazır şablon | UI04–12 |
| 3. Mobil ergonomika | Bir əllə və klaviatura ilə olur? | 44 px target, sticky safe area, agenda | AT29 |
| 4. Data doğruluğu | Eyni vaxtda nə baş verir? | Occupancy constraint, version, idempotency | AT07–10 |
| 5. İcazə | Yanlış şəxs nə görə bilər? | Property capability+RLS, public DTO | AT04–06, AT23 |
| 6. Pul | Dublikat/geri qaytarma necədir? | Ayrı SaaS/rent ledger, integer, reversal | AT11–14, AT27 |
| 7. Real həyat | Verən/alan ayrı vaxtda doldurur? | Event-side snapshot və ayrı submission | AT17–19 |
| 8. Davamlılıq | Şəbəkə/provider işləməsə? | Truthful pending, outbox, reconcile, restore | AT30, AT33 |
| 9. İcra | Agentlər bir-birini pozur? | Müqavilə əvvəl, fayl ownership, integrator | AGENTS |
| 10. İstismar | Problem necə görünür və düzəlir? | Audit, alert, status, rollback runbook | AT32–34 |

## Hər milestone sonunda cavab

Nə sadələşdi? Hansı invariant DB-də qorunur? Mobil istifadəçi harada ilişdi? Hansı test faktiki işləmədi? Hansı risk qaldı? Növbəti mərhələni nə bloklayır?

Bu cavablar milestone issue-da qısa nəticə kimi saxlanılır. Yeni funksiya yalnız istifadəçi dəyəri və mövcud scope-a təsiri əsaslandırıldıqda əlavə edilir.
