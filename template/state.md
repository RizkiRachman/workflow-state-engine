# STATE — Workflow State Engine

## Current Focus
Agent orchestration — REVIEW phase. All 15 files rewritten: agent.md (full rewrite), 11 agent files (path fixes + goods-price-comparison removal), doc/workflow.md (23 path fixes), setup.sh (8 path fixes), README.md (content removal). Ready for quality-analyst review.

## Completed
- [2026-06-17] **agent.md full rewrite**: Removed Java 21/Spring Boot/Maven/hexagonal/ArchUnit/build gates. Added state machine, scoring pipeline, orchestration flow, root-level structure. All toolkit/ paths → root-level. All goods-price-comparison → workflow-state-engine.
- [2026-06-17] **11 agent files path fixes + content removal**: tech-lead, system-analyst, developer, developer-fixer, quality-analyst, quality-analyst-learner, developer-explorer, developer-librarian, developer-observer, developer-council, software-architect. All toolkit/ refs removed. Goods-price-comparison examples replaced with generic orchestration examples.
- [2026-06-17] **Batch 3 path fixes**: doc/workflow.md (23 toolkit/ fixes), setup.sh (8 fixes), README.md (content removal + agent.md cross-ref).
- [2026-06-17] **F3 — Notify stub expanded**: 23-line placeholder → 75-line full usage guide. Added trigger table, platform support, troubleshooting, advanced config with suppression keys.
- [2026-06-17] **G1 — Pre-flight checks in setup.sh**: Added validation for bash ≥4, git, node, lean-ctx, opencode-skillful config. Hard failures for critical deps, warnings for optional. Also fixed syntax errors in earlier edit (missing `fi`, `cmd`→`command`).
- [2026-06-17] **G2 — Prerequisites section in README.md**: Added tool requirements table (bash, git, node, lean-ctx, java, maven, docker) with minimum versions and verification commands.
- [2026-06-17] **Security audit round 2 (full toolkit scan)**: Fixed C1-C5 (memory-mcp dead refs, graphify deny conflicts), M1-M6 (developer-council permissions, firecrawl deny on developer, outdated commands in agent.md), N1-N4 (frontmatter honesty). 11+ issues resolved.
- [2026-06-17] **Toolkit architecture deep analysis**: Overall health scored 6.5/10, gap report exported with P0/P1/P2 recommendations.
- [2026-06-17] **Fix A-E + Security Round 2**: write/glob/list/webfetch/morph_edit/memory_*/firecrawl_*/task denied per-agent.
- [2026-06-17] **Agent path corrections**: Replaced npx gitnexus analyze with bash scripts/gitnexus-analyze.sh (8 files, 10 occurrences). Cleaned up memory-mcp dead refs.
