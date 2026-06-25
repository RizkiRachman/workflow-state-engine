<!-- omit from toc -->

# Workflow State Engine — Orchestration Toolkit

**Contract-driven state machine orchestration engine for AI agent workflows.**

State machine: `INIT → PLAN → PLAN_SCORED → PONYTAIL_CHECK → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE`

Single source of truth for all AI agents. Reference skills and usage guides for depth. This file is `instructions[0]` — loaded by every agent at session start.

[![Contributors][contributors-shield]][contributors-url] [![Forks][forks-shield]][forks-url] [![Stargazers][stars-shield]][stars-url] [![Issues][issues-shield]][issues-url] [![License][license-shield]][license-url]

<a id="readme-top"></a>

## Table of Contents
1. [1. Project Overview](#1-project-overview)
2. [2. Framework Architecture](#2-framework-architecture)
3. [3. Agent Reference — 11 Agents](#3-agent-reference--11-agents)
4. [4. Tool Usage Reference](#4-tool-usage-reference)
5. [5. Development Workflow](#5-development-workflow)
6. [6. Non-Negotiable Rules](#6-non-negotiable-rules)
7. [7. Skills Reference](#7-skills-reference)
8. [8. Session Lifecycle Protocol](#8-session-lifecycle-protocol)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## 1. Project Overview

### Core Concepts

| Concept | Description |
|---------|-------------|
| **Shared JSON Envelope** | `session/{branch}/contract.json` — single source of truth for state, decisions, outputs, scoring |
| **State Machine** | 9 states + BLOCKED: agents transition through the workflow via the envelope |
| **Scoring Pipeline** | Three-tier scoring after every delegation (rule checks → LLM-as-judge → combined verdict) |
| **Ponytail Gate** | Ponytail debt check between PLAN_SCORED and EXECUTE via pre-commit-ponytail.sh |
| **Agent Delegation** | Orchestrator delegates to specialized agents (system-analyst, developer, quality-analyst) |
| **Cross-Session Learning** | Lessons, patterns, gotchas persisted via `ctx_knowledge` |

### State Machine Transitions

```
INIT → PLAN → PLAN_SCORED → PONYTAIL_CHECK → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE
                              ↘                ↘                ↘
                          BLOCKED (score < 50 or retry ≥ 3)
                                ↘
                          User intervention → retry with guidance
```

| Transition | Gate | Condition |
|-----------|------|-----------|
| INIT → PLAN | Session created | Always |
| PLAN → PLAN_SCORED | Plan produced | Always |
| PLAN_SCORED → PONYTAIL_CHECK | Ponytail gate | Score ≥ 70 |
| PONYTAIL_CHECK → EXECUTE | Ponytail scan | Debt items ≤ max_debt_items |
| EXECUTE → EXECUTE_SCORED | Implementation done | Always |
| EXECUTE_SCORED → REVIEW | Code review | Score ≥ 70 |
| REVIEW → REVIEW_SCORED | Review done | Always |
| REVIEW_SCORED → COMPLETE | All gates pass | Score ≥ 70 |
| Any → BLOCKED | Escalation | Score < 50 or retry ≥ 3 |

### Scoring Pipeline (Three-Tier)

1. **Tier 1 — Rule-Based Checks**: Schema valid (-15), permissions violated (-40), blast radius HIGH (-40), writing order wrong (-15), required fields missing (-15). Subtotal ≥ 70 → Tier 2.
2. **Tier 2 — LLM-as-Judge**: Scores 0-100 on requirements fulfillment (0-40), governance compliance (0-30), completeness (0-20), edge cases (0-10).
3. **Tier 3 — Combined Verdict**: PASS (≥70), RETRY (50-69, max 3 attempts), BLOCKED (<50).

### Architecture

```
agents/     → 11 agent instruction files (tech-lead, developer, quality-analyst, etc.)
skills/     → 29 skill directories (system-analyst, writing-plans, spec-driven-dev, etc.)
contract/   → contract.json, superpowers-contract.json, state.md
rules/      → rules.json (state machine transitions, scoring thresholds)
doc/        → workflow.md, project.md, gap analysis, state-history.md
usage/      → 15 tool usage guides (lean-ctx, gitnexus, firecrawl, etc.)
config/     → Plugin configs (vibeguard, opencode-skillful)
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 2. Framework Architecture

### Root-Level Structure

This project keeps its toolkit at the project root for direct access. No nested `toolkit/` directory:

```
.opencode/                  (symlinks resolve to root-level source)
   ├── agents/ ──symlink──► agents/         11 agent .md files
   ├── skills/ ──symlink──► skills/         29 skill directories
   ├── rules/  ──symlink──► rules/          rules.json (state machine)
   ├── orchestration/ ──symlink──► contract/   contract.template.json, contract.schema.json, state.template.md, superpowers-contract.json
   ├── planning/ ──symlink──► doc/planning/    Planning docs
   ├── reports/ ──symlink──► doc/reports/   Analysis reports
   ├── usage/   ──symlink──► usage/         15 tool usage guides
   └── config/  ──symlink──► config/        Plugin configs
```

You reference `.opencode/` paths — OpenCode resolves symlinks to root-level source.

### Directory Tree

```
├── agent.md           ← THIS FILE (instructions[0])
├── AGENTS.md          ← GitNexus code intelligence (loaded at session start)
├── README.md          ← Project overview (diagram, badges)
├── agents/            ← 11 agent instruction files
├── config/            ← Plugin configs (vibeguard, opencode-skillful)
├── doc/               ← Planning docs, workflow.md, gap analyses
├── rules/             ← rules.json (state machine, scoring)
├── skills/            ← 29 skill directories (java-developer, gitnexus/, spec-driven-dev, etc.)
├── contract/          ← contract.template.json, contract.schema.json, state.template.md, superpowers-contract.json
├── usage/             ← 15 tool usage guides (one per tool group)
└── setup.sh           ← Bootstrap: creates all .opencode/ → root-level symlinks
```

### Fresh Clone Setup

```bash
bash setup.sh    # Creates all .opencode/ → root-level symlinks
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 3. Agent Reference — 11 Agents

> Full agent instruction files at `agents/` (symlinked to `.opencode/agents/`). Each file defines role, MCPs, skills, and post-flight protocol.

### Orchestrator

| Agent | Role | Key MCPs | Access | Contract States | Skills | File |
|-------|------|----------|--------|----------------|--------|------|
| **tech-lead** | Delegates, scores, drives state machine | lean-ctx, gitnexus, graphify, firecrawl | Read-Write | `*` (all) | orchestration-template, release-plan | `agents/tech-lead.md` |

### Planning Agents (read-only)

| Agent | Role | Key MCPs | Access | Contract States | Skills | File |
|-------|------|----------|--------|----------------|--------|------|
| **system-analyst** | Architecture specs, impact analysis, detailed plans | lean-ctx, gitnexus, graphify | Read-only | `INIT`, `PLAN`, `PLAN_SCORED` | system-analyst, business-analyst, writing-plans | `agents/system-analyst.md` |
| **software-architect** | Architecture trade-offs, simplification, YAGNI | gitnexus, graphify, firecrawl | Read-only | `INIT`, `PLAN`, `PLAN_SCORED` | system-analyst, java-developer | `agents/software-architect.md` |

### Implementation Agents (read/write)

| Agent | Role | Key MCPs | Access | Contract States | Skills | File |
|-------|------|----------|--------|----------------|--------|------|
| **developer** | Full implementation: ports → services → adapters → tests | lean-ctx, gitnexus, morph | Read-Write | `EXECUTE`, `EXECUTE_SCORED` | java-developer, software-developer, spec-driven-development | `agents/developer.md` |
| **developer-fixer** | Fast bounded fixes, scoped edits only | lean-ctx, morph, gitnexus | Read-Write | `*` (all) | java-developer, simplify | `agents/developer-fixer.md` |

### Quality Agents (read-only)

| Agent | Role | Key MCPs | Access | Contract States | Skills | File |
|-------|------|----------|--------|----------------|--------|------|
| **quality-analyst** | Code review, security, DevOps, DB perf | lean-ctx, gitnexus, postgres | Read-only | `REVIEW`, `REVIEW_SCORED` | qa-expert, security-expert, code-review-and-quality | `agents/quality-analyst.md` |
| **software-architect** | Architecture review, tech debt assessment | gitnexus, graphify | Read-only | `INIT`, `PLAN`, `PLAN_SCORED` | system-analyst, java-developer | `agents/software-architect.md` |
| **quality-analyst-learner** | Post-execution: extract lessons, gotchas, patterns | lean-ctx, gitnexus | Read-only | `REVIEW_SCORED`, `COMPLETE` | — | `agents/quality-analyst-learner.md` |

### Support Agents (read-only)

| Agent | Role | Key MCPs | Access | Contract States | Skills | File |
|-------|------|----------|--------|----------------|--------|------|
| **developer-explorer** | Fast codebase search, find definitions/usage | lean-ctx, gitnexus, firecrawl | Read-only | `*` (all) | gitnexus-exploring | `agents/developer-explorer.md` |
| **developer-librarian** | External docs research, API references | firecrawl, context7, gh_grep, websearch | Read-only | `*` (all) | firecrawl-search, firecrawl-scrape | `agents/developer-librarian.md` |
| **developer-council** | Multi-LLM consensus for high-stakes decisions | gitnexus, graphify, council_session | Read-only | `*` (all) | — | `agents/developer-council.md` |
| **developer-observer** | Visual/PDF/diagram analysis (requires vision model) | lean-ctx, firecrawl-parse | Read-only | `*` (all) | — | `agents/developer-observer.md` |

### Lane Name Mapping
| Lane | Agent | subagent_type |
|------|-------|---------------|
| `@explorer` | developer-explorer | `developer-explorer` |
| `@librarian` | developer-librarian | `developer-librarian` |
| `@fixer` | developer-fixer | `developer-fixer` |
| `@council` | developer-council | `developer-council` |
| `@observer` | developer-observer | `developer-observer` |

### Agent State Machine

See [`doc/workflow.md`](./doc/workflow.md) for the canonical state machine, scoring pipeline, gates, and validation rules.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 4. Tool Usage Reference

Full how-to guides live in `usage/` (15 guides: lean-ctx, gitnexus, firecrawl, postgres, etc.). Load them on demand via `lean-ctx ctx_read --path "usage/<tool>.md"`.

### 4.1 Quick Reference

| Tool | What It Does | Guide |
|------|-------------|-------|
| **lean-ctx** | File reads, shell, search, edit, knowledge persistence, sessions | `usage/lean-ctx.md` |
| **GitNexus** | Impact analysis, code query, blast radius, safe rename | `usage/gitnexus.md` |
| **Graphify** | Knowledge graph, community discovery, PR impact | `usage/graphify.md` |
| **Firecrawl** | Web search, scraping, crawling, PDF parse, monitoring | `usage/firecrawl.md` |
| **PostgreSQL** | DB queries, schema inspection, performance analysis | `usage/postgres.md` |
| **Context7** | Library/framework docs lookup | `usage/context7.md` |
| **Web Search** | Grounded search (citations) + semantic search (Exa) | `usage/websearch.md` |
| **gh_grep** | Code patterns from 1M+ public GitHub repos | `usage/gh-grep.md` |
| **Morph** | morph_edit, warpgrep codebase & GitHub search | `usage/morph.md` |

### 4.2 Plugins

| Plugin | What It Does | Guide |
|--------|-------------|-------|
| **DCP** | Context pruning, deduplication, token budget enforcement | `usage/dcp.md` |
| **VibeGuard** | Redacts secrets, credentials, PII before LLM send | `usage/vibeguard.md` |
| **Model Fallback** | Auto failover between LLM models on API error/rate-limit | `usage/model-fallback.md` |
| **Notify** | In-app notifications for long-running tasks | `usage/notify.md` |
| **Worktree** | Git worktree TUI management for isolated coding lanes | `usage/worktree.md` |

### 4.3 Tool Comparison Matrix

| Task | Best Tool | Why |
|------|-----------|-----|
| **Check blast radius before editing** | `gitnexus_impact` | Knowledge graph tracks callers/importers at d=1/d=2/d=3 depths |
| **Explore unfamiliar code flows** | `gitnexus_query` | Returns process-grouped execution flows ranked by relevance |
| **Broader codebase exploration** | `graphify_query_graph` | BFS/DFS traversal across communities, finds concept relationships |
| **Find core abstractions** | `graphify_god_nodes` | Most connected symbols in the graph (hubs) |
| **Read/edit files** | `lean-ctx ctx_read`/`ctx_edit` | Cached reads (~13 tok), safe search-and-replace edits |
| **Shell commands** | `lean-ctx ctx_shell` | Compressed output, 95+ patterns, replaces bash |
| **Persist decisions/knowledge** | `lean-ctx ctx_knowledge remember` | Cross-session persistence with embeddings |
| **Save/resume sessions** | `lean-ctx ctx_session` | Survives OpenCode restarts |
| **Code review / DB analysis** | `postgres_pg_*` | Schema inspection, query analysis, performance review |
| **External library research** | `context7_query_docs` | Official docs lookups with code examples |
| **Web search / scraping** | `firecrawl_search`/`scrape` | Full page extraction, JS-rendered SPAs supported |
| **Code examples from GitHub** | `warpgrep_github_search` | Implementation patterns from 1M+ public repos |
| **Large/scattered file edits** | `morph_edit` | Partial-file merge, handles whitespace-sensitive changes better than exact-string replacement |
| **Multi-model consensus** | `council_session` | Fresh-context adversarial review for high-stakes decisions |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 5. Development Workflow

### Branching Strategy (MANDATORY)

- **Never work on `main`**. Create a feature branch first.
- Naming: `feature/<YYYYMMDD>-<description>` or `bugfix/<YYYYMMDD>-<description>`
- Enforcement: `ctx_shell git branch --show-current` — if `main`, STOP.
- Exception: docs/config-only changes with explicit user approval.

### Before Any Edit

```
1. git switch -c feature/<YYYYMMDD>-<description>    # create branch
2. gitnexus_impact({target: "symbol", direction: "upstream"})   # blast radius
3. If HIGH/CRITICAL → warn user before proceeding
```

### Frugality Ladder (Ponytail — Before Every Code Decision)

Run this ladder in order before writing ANY code:

```
1. Does this need to exist?       → skip it (YAGNI)
2. Standard library does it?      → use it
3. Native platform feature?       → use it
4. Already-installed dependency?  → use it
5. Can this be one line?          → one line
6. Only then: minimum code that works
```

**Rules:** No unsolicited abstractions. No new deps if avoidable. Deletion > addition. Boring > clever. Fewest files possible. Mark intentional shortcuts with `ponytail:` comments (see `skills/simplify/SKILL.md` for convention details).

**Not sacrificed:** Input validation at trust boundaries, data-loss error handling, security, accessibility, anything explicitly requested. Non-trivial logic leaves ONE runnable check (assert-based, no framework).

### Orchestration Flow (Spec-Driven Development — SDD)

1. **Discuss phase** — 5-lens check: Business, System, Dev, QA, DevOps. Clarify requirements.
2. **Plan phase** — Delegate to @system-analyst: impact analysis, edge cases, implementation plan.
3. **Spec gate** (if >3 files, cross-service, or >30 min) — Write GWT-format specs. Cross-examine via DDD.
4. **Execute phase** — Delegate to @developer: implement plan step by step, write tests alongside code.
5. **Review phase** — Delegate to @quality-analyst: code quality, security, performance, DevOps operability.
6. **Verify loop** — Run build commands, check conventions.
7. **Ship** — Resolve issues, confirm deploy safety, run post-flight protocol.

Use **Doubt-Driven Development (DDD)** when uncertain: spawn a fresh-context adversarial reviewer to cross-examine non-trivial decisions before they stand.

### Before Commit (Post-Flight Protocol)

| # | Step | Tool |
|---|------|------|
| **0** | Validate contract | `bash scripts/validate-contract.sh --file session/{branch}/contract.json --score` |
| 1 | Impact verify | `gitnexus_impact` |
| 2 | Change detect | `gitnexus_detect_changes` |
| 3 | Knowledge persist | `lean-ctx ctx_knowledge remember` |
| 4 | Graphify sync | `lean-ctx ctx_shell` `bash scripts/gitnexus-analyze.sh` |
| 5 | STATE.md | `ctx_edit` |
| 6 | Session save (complete) | See **Save Session Protocol** below

**Pre-flight**: `bash scripts/validate-contract.sh --file session/{branch}/contract.json --score` (score < 70 = BLOCKED)
**Parallel conflict check**: `bash scripts/detect-parallel-conflicts.sh --file1 /tmp/a.txt --file2 /tmp/b.txt`
**Atomic persist**: `bash scripts/persist-contract.sh --file session/{branch}/contract.json --inject-score 85` |

Exceptions: docs-only changes skip 1, 2, 4. Config-only skip 1, 2.

### Save Session Protocol

When the user says "save session" or a phase completes, save to **ALL** systems:

```bash
# 1. Persist orchestration envelope to lean-ctx knowledge
lean-ctx ctx_knowledge remember key orchestration-contract value "<JSON>"

# 2. Update session/{branch}/state.md — append completed work items

# 3. Archive snapshot to session/ (contract files + state log + index)
bash scripts/snapshot-contract.sh --snapshot-only

# 4. Save conversation context (survives OpenCode restart)
lean-ctx ctx_session save

# 5. Re-index GitNexus code intelligence
bash scripts/gitnexus-analyze.sh

# 6. Re-index Graphify knowledge graph (if graphify-out/ exists)
graphify --update 2>/dev/null || true
```

**One-shot alias**: `save session` = all 6 steps above. Always run the full protocol — partial saves lose audit trail, break resumption, or leave stale indexes.

### Update All States (Post-Merge / Branch Switch)

After merging PRs or switching branches, synchronize all state systems:

```bash
# 1. Re-index GitNexus code intelligence
bash scripts/gitnexus-analyze.sh

# 2. Re-index Graphify knowledge graph
graphify --update 2>/dev/null || true

# 3. Snapshot contract state (session/{branch}/ → archive)
bash scripts/snapshot-contract.sh

# 4. Save conversation context (survives OpenCode restart)
lean-ctx ctx_session save
```

**One-shot alias**: `update all states` = all 4 steps. The post-merge git hook auto-runs steps 1, 3, and the session index sync — manually run step 2 (graphify) if semantic data changed.

### Session Lifecycle Protocol

Every orchestration session persists contract state to the `session/` directory for cross-session traceability and safe resumption.

#### Directory Layout

```
session/
├── state.md              ← Append-only chronological state log
├── index.md              ← Branch index (status per branch)
├── main/                 ← Per-branch snapshot for main
│   ├── contract.json
│   ├── contract.schema.json
│   ├── state.md
│   └── superpowers-contract.json
├── feature/<name>/       ← Per-feature-branch snapshots
```

#### Lifecycle Protocol

| Event | Action |
|-------|--------|
| **Session start** | Read git branch → check `session/{branch}/` exists → if yes, resume from snapshot; if no, init fresh from `contract/` templates |
| **State transition** | Update `session/{branch}/contract.json` → snapshot to `session/{branch}/` via `scripts/snapshot-contract.sh` |
| **Session end** (COMPLETE/BLOCKED) | Final snapshot → append summary to `session/state.md` → update `session/index.md` |
| **Branch switch** | Snapshot current → checkout new → load `session/NEW/` if exists |

#### Snapshot Command Reference

```bash
scripts/snapshot-contract.sh                # Full snapshot: copy files + update state.md + index.md
scripts/snapshot-contract.sh --snapshot-only  # Copy files only (skip state.md/index.md updates)
scripts/snapshot-contract.sh --summary "State: ${STATE} — description"  # Custom entry
scripts/snapshot-contract.sh --dry-run --verbose  # Preview without changes
scripts/snapshot-contract.sh --branch feature/my-branch  # Override branch detection
```

#### Why It Matters

Without per-branch archival, contract files get overwritten when switching branches or resuming sessions. The `session/` archive preserves:
- **Audit trail**: `session/state.md` grows monotonically — every state transition, every decision, every blocker
- **Safe resume**: `session/{branch}/contract.json` is the exact state from last session — no reconstruction needed
- **Discoverability**: `session/index.md` shows all branches with their status at a glance

### Complex Tasks (Orchestration Template)

See [orchestration-template skill](.opencode/skills/orchestration-template/SKILL.md) and [`doc/workflow.md`](./doc/workflow.md) for the full orchestration protocol.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 6. Non-Negotiable Rules

### Git Safety
- **Never push to `main` or `master`** — always PR
- **Never force push** (`--force`, `-f`)
- **Never merge PRs** or auto-approve reviews
- **Never directly approve PRs** — PRs require at least 1 reviewer who is not the author; no self-approve, no direct merge without review
- **Never commit secrets, credentials, tokens, `.env` files**
- **Never modify CI/CD, git config, or GitHub settings** without asking

### Code Safety
- **Never edit without `gitnexus_impact`** — run impact analysis first
- **Never commit without `gitnexus_detect_changes`** — verify scope
- **Never rename with find-and-replace** — use `gitnexus_rename`
- **Ignore HIGH/CRITICAL impact warnings** = governance violation

### Shell Safety
- **Always use `lean-ctx ctx_shell`** — never `bash` or `snip` (both denied in permissions)
- `bash` and `snip` trigger permission prompts and block automation

### Communication
- Explain tradeoffs, not just decisions
- Admit unknowns. Be token-efficient: concise, no filler, no full-file dumps
- Return only what was asked

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 7. Skills Reference

All skills at `.opencode/skills/` (symlinked from `skills/`). Use `/skill <name>` for deep dives. Each skill directory contains a `SKILL.md` with full guidance.

| Skill | When to Load |
|-------|-------------|
| `java-developer` | Java 21 idioms, anti-patterns, quality gates |
| `software-developer` | Full-stack conventions, clean code, SOLID |
| `system-analyst` | Architecture evaluation, dependency mapping |
| `business-analyst` | Requirements gathering, acceptance criteria |
| `brainstorming` | Divergent thinking for exploring solution spaces |
| `qa-expert` | Test strategy, coverage analysis, regression prevention |
| `receiving-code-review` | Act on review feedback with technical rigor |
| `requesting-code-review` | Submit code for structured review |
| `security-expert` | Vulnerability assessment, secure coding, compliance |
| `devops-expert` | CI/CD, containerization, deployment |
| `executing-plans` | Execute implementation plans step by step |
| `release-plan` | PR templates, commit conventions, release process |
| `token-optimize` | Efficient token usage, batch operations |
| `verification-before-completion` | Verify success criteria before marking complete |
| `writing-plans` | Create structured implementation plans |
| `humanizer` | Remove AI writing patterns from output |
| `doubt-driven-development` | Validate assumptions before committing to design |
| `adaptive-solver` | Meta-cognitive uncertainty resolution — structured loop for ambiguity, low confidence, or failed attempts |
| `spec-driven-development` | Write spec first, implement after |
| `subagent-driven-development` | Delegate bounded work to specialized subagents |
| `systematic-debugging` | Structured root cause analysis |
| `test-driven-development` | Red/green/refactor cycle |
| `orchestration-template` | Contract-based multi-agent orchestration |
| `audit-observability` | State contract audit trail, orchestration observability, score analytics, cross-service consistency |
| `code-review-and-quality` | Review checklists, quality metrics |
| `simplify` | Reduce complexity without changing behavior |
| `gitnexus-{exploring,impact,debug,refactor,cli,guide}` | GitNexus-specific workflows |
| `firecrawl-*` (30 skills in `~/.agents/skills/`) | Web search, scraping, crawling, monitoring |

*Last updated: 2026-06-18. If you modify conventions, workflows, or config, update this file.*

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **workflow-state-engine** (1675 symbols, 1666 relationships, 0 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> Index stale? Run `bash scripts/gitnexus-analyze.sh` from the project root.

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows. For regression review, compare against the default branch: `detect_changes({scope: "compare", base_ref: "main"})`.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `query({query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `context({name: "symbolName"})`.

## Never Do

- NEVER edit a function, class, or method without first running `impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit changes without running `detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/workflow-state-engine/context` | Codebase overview, check index freshness |
| `gitnexus://repo/workflow-state-engine/clusters` | All functional areas |
| `gitnexus://repo/workflow-state-engine/processes` | All execution flows |
| `gitnexus://repo/workflow-state-engine/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->

[contributors-shield]: https://img.shields.io/github/contributors/RizkiRachman/workflow-state-engine?style=for-the-badge
[contributors-url]: https://github.com/RizkiRachman/workflow-state-engine/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/RizkiRachman/workflow-state-engine?style=for-the-badge
[forks-url]: https://github.com/RizkiRachman/workflow-state-engine/network/members
[stars-shield]: https://img.shields.io/github/stars/RizkiRachman/workflow-state-engine?style=for-the-badge
[stars-url]: https://github.com/RizkiRachman/workflow-state-engine/stargazers
[issues-shield]: https://img.shields.io/github/issues/RizkiRachman/workflow-state-engine?style=for-the-badge
[issues-url]: https://github.com/RizkiRachman/workflow-state-engine/issues
[license-shield]: https://img.shields.io/github/license/RizkiRachman/workflow-state-engine?style=for-the-badge
[license-url]: https://github.com/RizkiRachman/workflow-state-engine/blob/main/LICENSE
