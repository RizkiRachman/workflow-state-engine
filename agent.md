# Goods Price Comparison Service — Agent Toolkit

**Java 21 + Spring Boot 3.4 · Hexagonal architecture per service · Event-driven between services**

Single source of truth for all AI agents. Reference skills and usage guides for depth. This file is `instructions[0]` — loaded by every agent at session start.

---

## 1. Project Overview

### Stack
- **Java 21** — records, sealed classes, pattern matching, text blocks, `List.of()`, `Stream.toList()`
- **Spring Boot 3.4** — `@Async`, `@TransactionalEventListener`, `@Service`, `@Component`
- **Maven** — multi-module structure (single-module currently, 8 service packages)
- **Build gates**: Spotless (Google Java Style), SpotBugs, PMD CPD, ArchUnit (7 rules)
- **Test**: JUnit 5, H2 in-memory (`@ActiveProfiles("test")`), Flyway disabled in tests
- **External dep**: `goods-price-comparison-api:1.3.0` from GitHub Packages (requires `~/.m2/settings.xml` with GitHub token)

### Architecture (Hexagonal)
```
application/          (pure Java — no Spring/JPA)
├── domain/model/     — @Builder @Getter @Setter, zero JPA
├── domain/service/   — implements *InPort
├── port/in/          — driving ports (*InPort)
├── port/out/         — driven ports (*RepositoryPort, *EventOutPort)
└── exception/        — domain exceptions

infrastructure/       (adapters)
├── adapter/web/      — REST controllers, DTO mappers
├── adapter/persistence/ — JPA entities, repositories, entity mappers
├── adapter/event/    — event publishers/listeners
└── handler/event/    — @Async @TransactionalEventListener handlers
```
- 8 service domains: `receipt`, `price`, `product`, `store`, `llm`, `shopping`, `alert`, `system`
- Each owns its tables. No cross-service table queries.
- Events via Spring `ApplicationEvent` + `@Async` + `@TransactionalEventListener(AFTER_COMMIT)`

### Build & Verify
```bash
mvn spotless:apply               # Format (Google Java Style)
mvn test                         # Tests + ArchUnit only
mvn verify                       # Full gate: tests + ArchUnit + Spotless + SpotBugs + PMD CPD
mvn verify -P security-check     # + OWASP dependency scan
./scripts/check-conventions.sh   # Custom conventions
```

### Data Shapes
| Shape | Package | Type | Annotations |
|-------|---------|------|-------------|
| API DTO | `infrastructure/adapter/web/dto/` | `record` | Jackson if needed |
| Domain Model | `application/domain/model/` | class | `@Builder @Getter @Setter` |
| JPA Entity | `infrastructure/adapter/persistence/entity/` | class | `@Entity @Table` |
| Port Interface | `application/port/in\|out/` | interface | none |
| Domain Service | `application/domain/service/` | class | `@Service` |
| Repository | `infrastructure/adapter/persistence/` | class | `@Component` |

### Writing Order (Mandatory)
1. Port interface (`*InPort`, `*RepositoryPort`)
2. Domain service (implements `*InPort`)
3. Mapper (domain ↔ DTO, domain ↔ entity)
4. Adapter (orchestration via ports + mappers)
5. Constants (`AppConstants`, `ErrorCodes`, `ErrorMessageConstants`)
6. Events (`*EventOutPort`, `*EventAdapter`, handler)
7. Tests (unit + ArchUnit)

---

## 2. Toolkit Architecture

### Why `toolkit/`?

AI agents scatter config across `.opencode/`, `.claude/`, `CLAUDE.md`, `AGENTS.md`, `STATE.md`. `toolkit/` solves this by keeping **everything in one place**.

### How Symlinks Work
```
.opencode/                toolkit/             (source of truth)
   ├── agents ──symlink──► agents/             11 agent .md files
   ├── skills ──symlink──► skills/             27 skill directories
   ├── rules ──symlink──► rules/               rules.json (state machine)
   ├── orchestration ─symlink─► template/      contract.json, superpowers-contract.json, state.md
   ├── planning ──symlink──► doc/planning/     Planning docs
   ├── reports ──symlink──► doc/reports/       Analysis reports
   ├── usage ──symlink──► toolkit/usage/       14 tool usage guides
   └── config ──symlink──► toolkit/config/     Plugin configs
```
You reference `.opencode/` paths — OpenCode resolves symlinks to `toolkit/`.

> Symlink diagram also documented in [README.md §"How it works"](../README.md#how-it-works).

### Directory Tree
```
toolkit/
├── agent.md           ← THIS FILE (instructions[0])
├── README.md          ← Toolkit overview (diagram, badges)
├── agents/            ← 11 agent instruction files
├── config/            ← Plugin configs (vibeguard, opencode-skillful)
├── doc/               ← Planning docs, project.md, gap analyses
├── rules/             ← rules.json (state machine, scoring)
├── skills/            ← 27 skill directories (java-developer, gitnexus/, etc.)
├── template/          ← contract.json, superpowers-contract.json, state.md
├── usage/             ← 14 tool usage guides (one per tool group)
└── setup.sh           ← Bootstrap: creates all .opencode/ → toolkit/ symlinks
```

### Fresh Clone Setup
```bash
bash toolkit/setup.sh    # Creates all symlinks
```

---

## 3. Agent Reference — 11 Agents

> Full agent instruction files at `toolkit/agents/` (symlinked to `.opencode/agents/`). Each file defines role, MCPs, skills, and post-flight protocol.

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

See [`toolkit/doc/workflow.md`](./doc/workflow.md) for the canonical state machine, scoring pipeline, gates, and validation rules.

---

## 4. Tool Usage Reference

Full how-to guides live in `toolkit/usage/` (15 guides: lean-ctx, gitnexus, firecrawl, postgres, etc.). Load them on demand via `lean-ctx ctx_read --path "toolkit/usage/<tool>.md"`.

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

### Implementation (Spec-Driven Development — SDD)

1. Write port interface (`*InPort`, `*RepositoryPort`) — defines the contract
2. Write domain service — implements `*InPort`, pure logic
3. Write mapper — converts between layers
4. Write adapter — orchestrates ports + mappers
5. Write constants — no magic strings
6. Write events — `*EventOutPort` → `*EventAdapter` → handler
7. Write tests — unit + ArchUnit

Use **Doubt-Driven Development (DDD)** when uncertain: delegate to `@explorer` to validate assumptions before committing to a design. Skill: `doubt-driven-development`.

### Before Commit (Post-Flight Protocol)

| # | Step | Tool |
|---|------|------|
| 1 | Impact verify | `gitnexus_impact` |
| 2 | Change detect | `gitnexus_detect_changes` |
| 3 | Knowledge persist | `lean-ctx ctx_knowledge remember` |
| 4 | Graphify sync | `lean-ctx ctx_shell` `bash scripts/gitnexus-analyze.sh` |
| 5 | STATE.md | `ctx_edit` |
| 6 | Session save | `ctx_session save` |

Exceptions: docs-only changes skip 1, 2, 4. Config-only skip 1, 2.

### Complex Tasks (Orchestration Template)

See [orchestration-template skill](../skills/orchestration-template/SKILL.md) and [`toolkit/doc/workflow.md`](./doc/workflow.md) for the full orchestration protocol.

---

## 6. Non-Negotiable Rules

### Git Safety
- **Never push to `main` or `master`** — always PR
- **Never force push** (`--force`, `-f`)
- **Never merge PRs** or auto-approve reviews
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

### Architecture Rules (Enforced by ArchUnit)
1. `application/` MUST NOT import `infrastructure/`
2. Domain models: `@Builder @Getter @Setter` only — zero JPA annotations
3. Ports return **nullable**, never `Optional<T>`
4. **NO** `@ManyToOne`, `@OneToMany`, `@OneToOne`, `@ManyToMany`, `@JoinColumn` — FKs are primitives
5. Domain services: `@Service` annotation
6. Repository adapters: `@Component` annotation
7. Events fire only after transaction commit (`@TransactionalEventListener(AFTER_COMMIT)`)

### Formatting
- **Always run `mvn spotless:apply`** before committing — Google Java Style enforced

### Exception Handling
- Domain services: throw `NotFoundException` (static factories) — never return `null`
- Web adapters: throw `IllegalArgumentException` for invalid inputs
- Mappers: only acceptable `return null` (for null input safety)
- `GlobalExceptionHandler`: `NotFoundException` → 404, `IllegalArgumentException` → 400, else → 500

### Communication
- Explain tradeoffs, not just decisions
- Admit unknowns. Be token-efficient: concise, no filler, no full-file dumps
- Return only what was asked

---

## 7. Skills Reference

All skills at `.opencode/skills/` (symlinked from `toolkit/skills/`). Use `/skill <name>` for deep dives. Each skill directory contains a `SKILL.md` with full guidance.

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
| `spec-driven-development` | Write spec first, implement after |
| `subagent-driven-development` | Delegate bounded work to specialized subagents |
| `systematic-debugging` | Structured root cause analysis |
| `test-driven-development` | Red/green/refactor cycle |
| `orchestration-template` | Contract-based multi-agent orchestration |
| `code-review-and-quality` | Review checklists, quality metrics |
| `simplify` | Reduce complexity without changing behavior |
| `gitnexus-{exploring,impact,debug,refactor,cli,guide}` | GitNexus-specific workflows |
| `firecrawl-*` (30 skills in `~/.agents/skills/`) | Web search, scraping, crawling, monitoring |

*Last updated: 2026-06-16. If you modify conventions, workflows, or config, update this file.*

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **goods-price-comparison-service** (4928 symbols, 10961 relationships, 300 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

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
| `gitnexus://repo/goods-price-comparison-service/context` | Codebase overview, check index freshness |
| `gitnexus://repo/goods-price-comparison-service/clusters` | All functional areas |
| `gitnexus://repo/goods-price-comparison-service/processes` | All execution flows |
| `gitnexus://repo/goods-price-comparison-service/process/{name}` | Step-by-step execution trace |

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
