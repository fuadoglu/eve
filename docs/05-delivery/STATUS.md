# Faktiki icra vəziyyəti

Tarix: 2026-11-11 (Asia/Baku). Mərhələ: **icra üçün genişləndirilmiş sənəd və müqavilə təhvili**.

## Mövcud artefaktlar

- Azərbaycan dilində məhsul, qərar, əməliyyat, maliyyə, paylaşım və təhlükəsizlik müqavilələri.
- Hər endpoint üçün request/response/security metadata olan OpenAPI 3.1 JSON.
- Cədvəl/sütun/constraint/RLS/retention data dictionary və API→DB field bindings.
- Status keçidləri, versiyalanmış konfiqurasiya, 16 tələb üzrə izləmə matrisi.
- UI01–19 kliklənən sənəd prototipi və dəqiq forma axınları.
- 30 parent GitHub issue daxilində 90 atomik iş paketi, dependency və external gate fərqi.
- 36 ətraflı Given/When/Then qəbul ssenarisi; Codex multiagent müqaviləsi.
- Müstəqil security/delivery sənəd red-team baxışı və düzəliş reyestri.
- Sənəd, kontrakt, schema və demo smoke script-ləri, GitHub Actions konfiqurasiyası.

## Faktiki yoxlama

Yerli Node/Python runtime artıq əlçatandır. Sənəd linkləri, müqavilə bütövlüyü, asılılıq qrafı, OpenAPI/JSON Schema və demo smoke real icra edilir. Son çıxışlar və source hash-ləri [evidence](../04-quality/evidence/contracts.json)-dədir. Remote CI nəticəsi ayrıca yoxlanılır; config-in mövcudluğu yaşıl run demək deyil.

Prototip smoke-u 71 assertion ilə VM/fake-DOM yoxlamasıdır. Cloud browser workspace localhost-a qoşula bilmədiyindən screenshot/layout QA keçilmiş sayılmır. Real cihaz və 5 iştirakçılı usability testi hələ aparılmayıb.

## Hələ tamamlanmayan icra

- Production tətbiqi, executable SQL migrations/RLS, real API route-ları.
- Supabase/SMTP/Payriff/Vercel faktiki canlı konfiqurasiyası və provider sandbox sınaqları.
- Tətbiq integration/E2E/security/performance testləri, DB+media restore və rollback.
- Native GitHub Milestones, branch ruleset və required-check aktivliyinin təsdiqi.
- Hüquqi retention/refund/məxfilik mətnlərinin təsdiqi və production deploy.

## Növbəti iş

Codex əvvəl müqavilə validatorlarını işlədib hazır artefaktları audit edir; onları sıfırdan yenidən yazmır. [CODEX-START](CODEX-START.md) və [WORK-PACKAGES](WORK-PACKAGES.md) ilə M0-dakı real istifadə/provider qapıları ayrılır, müstəqil M1 scaffold/schema işi davam edir. İmplementasiya taskları sübut və merge olmadan Done işarələnmir.
