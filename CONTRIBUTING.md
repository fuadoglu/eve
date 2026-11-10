# Töhfə və icra qaydası

Əvvəl [AGENTS.md](AGENTS.md), [sənəd indeksi](docs/INDEX.md) və [GitHub iş axını](docs/05-delivery/GITHUB-WORKFLOW.md) oxunur.

Sənədlər, PR/issue izahları Azərbaycan dilindədir; kod identifikatorları və API enum-ları ingiliscədir. Məhsul qərarı dəyişirsə DECISIONS, modul spec və acceptance eyni PR-də yenilənir.

Issue → Ready → ayrı branch/worktree → draft PR → test/review → squash merge. Secret/PII commit edilmir. Real test olmayan “passed” yazılmır. App scaffold olmadığı üçün quraşdırma əmrləri hazırda vəd edilmir; M1 bunları təsdiqləyir.

Documentation link yoxlaması: node scripts/docs-check.mjs. Bu yalnız sənəd link/ID bütövlüyünü yoxlayır, tətbiq keyfiyyətini yox.
