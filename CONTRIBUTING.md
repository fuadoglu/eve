# Töhfə və icra qaydası

Əvvəl [AGENTS.md](AGENTS.md), [sənəd indeksi](docs/INDEX.md) və [GitHub iş axını](docs/05-delivery/GITHUB-WORKFLOW.md) oxunur.

Sənədlər, PR/issue izahları Azərbaycan dilindədir; kod identifikatorları və API enum-ları ingiliscədir. Məhsul qərarı dəyişirsə DECISIONS, modul spec və acceptance eyni PR-də yenilənir.

Issue → Ready → ayrı branch/worktree → draft PR → test/review → squash merge. Secret/PII commit edilmir. Real test olmayan “passed” yazılmır. App Node.js versiyası `.nvmrc`-də, pnpm versiyası `package.json`-ın `packageManager` sahəsində pinlənib.

İlkin scaffold yoxlaması: `pnpm install --frozen-lockfile`, `pnpm test:env`, `pnpm typecheck`, `pnpm build`. Bunlar hazırda yalnız scaffold və env kontraktını sübut edir; auth, DB/RLS və məhsul axını hazır olduğunu göstərmir. CI həmin əmrləri və aşağıdakı sənəd yoxlamalarını təmiz checkout-da işə salır.

Documentation link yoxlaması: node scripts/docs-check.mjs. Bu yalnız sənəd link/ID bütövlüyünü yoxlayır, tətbiq keyfiyyətini yox.


## Faktiki sənəd yoxlamaları

1. Node 22+ ilə `node scripts/docs-check.mjs`.
2. `node scripts/generate-traceability.mjs`; generator diff-i PR-də review edilir.
3. `node scripts/verify-contracts.mjs`.
4. Python venv açıb `python -m pip install -r scripts/requirements-docs.txt`, sonra `python scripts/validate-schemas.py`.
5. `node scripts/test-prototype.mjs`.

Son üçü müqavilə/prototip yoxlamasıdır; işləyən tətbiq, provider və real cihaz UX testi deyil. Browser QA mümkün deyilsə səbəb evidence-də açıq qalır. Yeni contract əməliyyatı say artırmaq üçün deyil, mövcud məhsul axınını tam təsvir etmək üçün əlavə olunur.
