# Vercel Skills — AI Agent Skill Package Manager Analysis

**Source:** https://github.com/vercel-labs/skills
**Analyzed:** 2026-06-17
**Stars:** 1.1k ★
**License:** Apache 2.0
**Status:** 🟡 BACKLOG

---

## What It Is

An `npx skills` CLI for installing, managing, and discovering AI agent skills. Skills are npm-packaged directories with a `SKILL.md` convention — publishable to **skills.sh** registry and installable via `npx skills <agent> install <skill>`.

Currently supports: Claude Code, Cursor, Windsurf, Cline, VS Code (Cline/Copilot), GitHub Copilot, and soon OpenCode.

## Core Architecture

- **skills.sh** — web registry (search, discover, deploy)
- **npm packages** — each skill is an npm package with a `SKILL.md` in root
- **CLI (`npx skills`)** — install, list, search, remove
- **Agent detection** — auto-detects which agent is running, places files in correct location
- **`npx skills init`** — creates a new skill scaffold
- **`npx skills deploy`** — publishes to skills.sh

## Skill Format Convention

```
my-skill/
  SKILL.md        # markdown instructions loaded by agent
  package.json    # npm metadata (name, description, keywords)
  instructions/   # (optional) additional instruction files
  prompts/        # (optional) reusable prompt templates
  .cursor/rules/  # (optional) Cursor-specific rule format
  .windsurf/rules/# (optional) Windsurf-specific rule format
```

## Cross-Agent Portability

The key innovation: same skill, different file locations per agent.

| Agent | Skill File Location |
|-------|-------------------|
| Claude Code | `CLAUDE.md` or project root rules |
| Cursor | `.cursor/rules/` |
| Windsurf | `.windsurf/rules/` |
| Cline | `.clinerules/` |
| GitHub Copilot | `.github/copilot-instructions.md` |
| OpenCode | `.opencode/rules/` (skills.sh support pending) |

## Registry Features (skills.sh)

- Search by keyword, agent type, popularity
- One-click deploy from GitHub
- Versioned releases
- `npx skills <agent> search <query>`
- `npx skills <agent> info <skill>`

---

## Gap Analysis vs Our Stack

### What We Already Have

| Our Asset | Coverage |
|-----------|----------|
| 35 skills in `skills/` dir | Yes — but no package/registry format |
| 11 agents in `agents/` dir | Yes — but no cross-agent portability |
| `SKILL.md` convention | Yes — already use this format |
| Plugin install via `opencode.json` | Partial — no `npx skills` CLI support |

### What We are Missing

| Gap | Priority | Effort | Target |
|-----|----------|--------|--------|
| **Cross-Agent Portability** | 🟡 P2 | Medium — multi-agent placements per skill | `skills/` directory convention |
| **skills.sh Registry** | 🟢 P3 | High — needs infra, skills.sh is 3rd-party | Not our problem, but publish there |
| **Skill Package Format** | 🟢 P3 | Low — add `package.json` + `instructions/` to skills | `skills/<name>/` |
| **`npx skills` CLI support** | 🟢 P3 | Low — just ensure metadata matches | `package.json` per skill |
| **Skill Discovery (search/install)** | 🟢 P3 | Low — lean-ctx knowledge already serves this |

### Skills Complementarity

Many Vercel-labs skills overlap with ours. Key differentiators:

| Vercel Skill | Our Equivalent | Gap in Ours |
|-------------|---------------|-------------|
| `system-analyst` | `system-analyst` skill | Close match — ours is more detailed |
| `testing` | `qa-expert` + `test-driven-development` | Vercel's is more generic |
| `security` | `security-expert` | Vercel's is broader, ours is deeper |
| `gitnexus` | `gitnexus-*` skills (6 skills) | Vercel has none — we lead here |
| `firecrawl-*` | `firecrawl-*` (30+ skills) | Vercel has none — we lead here |
| `docker` | `devops-expert` | Vercel's is docker-specific, ours is broader |

---

## Recommended Actions

### ✅ Do Now — Publish our skills to skills.sh

Add `package.json` to each skill dir with correct metadata. Then `npx skills deploy`.

### 🟡 Next — Adopt cross-agent placement format

Each skill directory should know which agents it targets and where to install.

### 🟡 Next — Add `instructions/` and `prompts/` subdirs to each skill

Refine the skill directory convention beyond just `SKILL.md`.

### 🟢 Later — Add skill discovery to lean-ctx knowledge

Index all skill metadata so agents can search/discover skills via knowledge queries.

---

## Relationships

- `skills/` — all 35 skill directories
- `agents/` — all 11 agent instruction files
- `doc/reports/toolkit-architecture-gap-analysis-2026-06-17.md` — broader toolkit gaps
- `doc/gap/duplication-analysis.md` — overlapping instruction files
- `contract/superpowers-contract.json` — skill plugin configuration

---

*Move to `tasks/planning/` when ready to begin implementation.*