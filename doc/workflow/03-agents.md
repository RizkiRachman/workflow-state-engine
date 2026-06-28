<!-- omit from toc -->

# Part C — Agent Integration Matrix

> See [doc/workflow/README.md](../workflow/README.md) for index.

This part maps all 11 agents to their contract states, plugins, MCPs, and skills. It also documents the toolkit data flow, agent pipeline, and cross-reference table for every concept in the orchestration system.

## C1. Full 11-Agent × 3-Dimension Table

| Agent | Contract States | Plugins | Key MCPs | Skills to Load | Usage Pattern |
|---|---|---|---|---|---|
| **tech-lead** | all 10 | opencode-notify, opencode-goal-plugin, @openspoon/subtask2 | gitnexus, graphify, lean-ctx, postgres, firecrawl | orchestration-template, brainstorming, writing-plans, executing-plans, doubt-driven-dev, spec-driven-dev, subagent-driven-dev, adaptive-solver | `/skill orchestration-template` → load contract → delegate → score → persist |
| **system-analyst** | INIT, PLAN, PLAN_SCORED | @zenobius/opencode-skillful, opencode-websearch-cited | gitnexus, graphify, lean-ctx, context7, postgres, firecrawl | system-analyst, business-analyst, brainstorming, writing-plans, doubt-driven-dev, spec-driven-dev, software-developer | `/skill system-analyst` → impact analysis → plan → populate outputs.plan |
| **developer** | EXECUTE, EXECUTE_SCORED | @morphllm/opencode-morph-plugin, opencode-worktree | gitnexus, lean-ctx, firecrawl | subagent-driven-dev, test-driven-dev, java-developer, software-developer, simplify | Load plan from contract → TDD → implement → test → commit |
| **developer-fixer** | all 10 | @morphllm/opencode-morph-plugin, opencode-worktree | gitnexus, lean-ctx | java-developer, simplify, subagent-driven-dev | impact → scoped edit → verify |
| **developer-explorer** | all 10 | @morphllm/opencode-morph-plugin, @zenobius/opencode-skillful | gitnexus, graphify, lean-ctx, context7, firecrawl | gitnexus-exploring, systematic-debugging | query/context → explore → report |
| **developer-librarian** | all 10 | opencode-websearch-cited, @zenobius/opencode-skillful | context7, firecrawl, gh_grep, websearch | firecrawl-search | firecrawl_search → context7_query → synthesize |
| **developer-council** | all 10 | (none) | lean-ctx, gitnexus, graphify | (multi-LLM consensus) | council_session → consensus → report |
| **developer-observer** | all 10 | (none) | lean-ctx, firecrawl | firecrawl-scrape, systematic-debugging, verification-before-completion | firecrawl_parse → analyze → report |
| **software-architect** | INIT, PLAN, PLAN_SCORED | @zenobius/opencode-skillful | gitnexus, graphify, lean-ctx, context7, firecrawl | system-analyst, systematic-debugging, brainstorming, software-developer | architecture review → tradeoffs → ADR |
| **quality-analyst** | REVIEW, REVIEW_SCORED | @zenobius/opencode-skillful | gitnexus, lean-ctx, postgres, firecrawl | code-review-and-quality, qa-expert, security-expert, devops-expert, java-developer | Read code → review 6 dimensions → produce findings report |
| **quality-analyst-learner** | REVIEW_SCORED, COMPLETE | @zenobius/opencode-skillful | gitnexus, lean-ctx, firecrawl | verification-before-completion, software-developer, firecrawl-knowledge-ingest | Post-exec analysis → extract lessons → persist knowledge_updates[] |

## C2. Agent Profiles

- **tech-lead**: Orchestrator — delegates, scores, drives state machine. Highest privilege: read/write all contract fields.
- **system-analyst**: Planner — analyzes, traces, produces specs/plans. Read-only: never writes code.
- **developer**: Builder — implements plan step by step, writes tests alongside code. Full write access.
- **developer-fixer**: Bounded fixer — fast, scoped edits for well-defined bugs. Minimal context, fast turnaround.
- **developer-explorer**: Codebase explorer — queries gitnexus/graphify to understand unfamiliar code. Read-only.
- **developer-librarian**: External researcher — web search, docs lookup, library research. Read-only.
- **developer-council**: Consensus engine — multi-LLM deliberation for high-stakes decisions. Read-only.
- **developer-observer**: Visual analyst — images, PDFs, diagrams. Read-only.
- **software-architect**: Architecture advisor — tradeoffs, system-level debugging, YAGNI. Read-only.
- **quality-analyst**: Reviewer — code quality, security, performance, DB, DevOps operability. Read-only.
- **quality-analyst-learner**: Post-exec learner — extracts lessons, persists knowledge_updates[]. Read-only.

## C3. Toolkit Data Flow

### Data Flow Steps

```
1. User request
       │
2. tech-lead creates contract envelope
       │  (session/{branch}/contract.json → lean-ctx knowledge)
       ▼
3. Envelope stored: lean-ctx ctx_knowledge remember key="orchestration-contract"
       │
4. tech-lead delegates: task({subagent_type: "system-analyst", prompt: "..."})
       │
5. Subagent reads envelope: lean-ctx ctx_knowledge recall --query "orchestration-contract"
       │
6. Subagent uses usage/<tool>.md for tool guidance
   Subagent loads skills/<name>/SKILL.md for skill instructions
       │
7. Subagent returns result (output structure depends on phase — plan, code, or report)
       │
8. tech-lead scores → updates envelope → persists → delegates next agent
       │
9. Loop: PLAN → EXECUTE → REVIEW → COMPLETE (or BLOCKED → retry)
```

**Step detail**:
- **Step 2-3**: The envelope is persisted as a JSON object under `lean-ctx ctx_knowledge` key `orchestration-contract`. It includes state, session metadata, requirements, decisions, scoring, retry info, outputs, and metrics.
- **Step 4-5**: Delegation uses OpenCode's subagent task mechanism. The subagent loads the envelope at session start (pre-flight protocol in all agent instruction files).
- **Step 6**: Tools and skills are loaded on-demand. Usage guides at `usage/*.md` cover tool-specific workflows (gitnexus, lean-ctx, firecrawl, postgres, etc.). Skills at `skills/*/SKILL.md` cover methodology (writing-plans, tdd, code-review, etc.).
- **Step 8-9**: The orchestrator runs the scoring pipeline after every delegation. If PASS, advances state. If RETRY, re-delegates with issues. If BLOCKED, escalates to user.

### Agent Pipeline

```
                     agent.md (instructions[0])
                           │
                 ┌─────────┼─────────────┐
                 ▼         ▼             ▼
          tech-lead   system-analyst   developer   quality-analyst
          (orchestrator) (planner)     (builder)   (reviewer)
                 │         │             │           │
                 └─────────┴─────────────┴───────────┘
                           │
                    usage/*.md
                    (guides loaded as needed)
```

The pipeline shows the hierarchy: `agent.md` is loaded by every agent at session start. Agents delegate down the pipeline (tech-lead → system-analyst → developer → quality-analyst), with usage guides loaded on demand by any agent.

### Folder → Workflow Mapping

```
├── agent.md                → Instructions[0] — loaded by EVERY agent at session start
├── agents/                 → Agent definitions loaded by opencode.json
├── skills/                 → Loaded on-demand via skill({name: "skill-name"})
├── usage/                  → Loaded on-demand when agent encounters an unfamiliar tool
├── contract/               → Contract templates (contract.template.json, contract.schema.json, state.template.md, superpowers-contract.json)
├── rules/                  → rules.json — state machine transitions + scoring thresholds
├── config/                 → Plugin config files referenced by opencode.json
└── doc/                    → Planning/reporting documents (never loaded automatically)
```

This mapping shows what each directory contributes at runtime. `contract/` provides immutable templates. `session/{branch}/` (not shown) holds live state. `rules/` provides the state machine definition. `config/` holds plugin configuration (vibeguard, dcp, opencode-skillful). `doc/` holds planning documents that are never auto-loaded.

### Tool Selection by Phase

| Phase | Agent | Primary Tools | Skills Loaded |
|---|---|---|---|
| INIT → PLAN | tech-lead → system-analyst | gitnexus_impact, gitnexus_query, context, graphify | brainstorming, writing-plans, doubt-driven-dev |
| PLAN_SCORED | tech-lead | lean-ctx (scoring), lean-ctx (persist) | spec-driven-dev (SDD gate) |
| EXECUTE | developer | lean-ctx (read/edit), gitnexus (impact) | java-developer, test-driven-dev, simplify (ponytail) |
| EXECUTE_SCORED | tech-lead | lean-ctx (scoring) | doubt-driven-dev (DDD gate), over-engineering check |
| REVIEW | quality-analyst | lean-ctx (read), gitnexus (impact), postgres (DB) | code-review-and-quality, qa-expert, security-expert, over-engineering check |
| REVIEW_SCORED | tech-lead | lean-ctx (scoring + persist) | verification-before-completion |
| COMPLETE | quality-analyst-learner | lean-ctx (knowledge), gitnexus (detect) | verification-before-completion, software-developer |

### Cross-Reference Table

| Concept | Definition | Configured In | Loaded By |
|---|---|---|---|
| Envelope | Shared session state | `session/{branch}/contract.json` | lean-ctx knowledge recall |
| State machine | Legal transitions | `rules/rules.json` | tech-lead (enforced in prompt) |
| Scoring | PASS/RETRY/BLOCKED | `rules/rules.json` | tech-lead (scoring pipeline) |
| Agents | Role definitions | `opencode.json` + `agents/*.md` | OpenCode at startup |
| Skills | Extensible behaviors | `skills/*/SKILL.md` | On-demand via skill() tool |
| Tools | MCP capabilities | `opencode.json` mcp section | OpenCode MCP client |
| Usage guides | How-to references | `usage/*.md` | On-demand via lean-ctx read |
| Ponytail | Frugality + debt convention | `usage/ponytail.md`, `agent.md §5`, `skills/simplify/SKILL.md` | On-demand via skill() |
| Plugins | Env vars, config files | `config/*.json`, `opencode.json` plugins | OpenCode at startup |
| Governance | Rules, constraints, safety | `agents/_governance.md` | All agents at session start |
| Contract schema | Envelope structure | `contract/contract.schema.json` | validate-contract.sh at every transition |
| Session archive | Per-branch snapshots | `session/{branch}/` | scripts/snapshot-contract.sh |
| Audit-observability | State tracking, score analytics | `skills/audit-observability/SKILL.md` | On-demand via skill() |

## C4. Companion Skills Registry Pattern

Some meta-skills (like `java-developer`) act as **registries** that link to specialized companion skills. This pattern enables lazy-loading of domain-specific knowledge without bloating the core skill.

### How It Works

```
Agent loads /skill java-developer
       ↓
java-developer/SKILL.md contains "Companion Skills" table
       ↓
Agent sees: "Need JPA patterns? Load /skill jpa-hibernate-patterns"
       ↓
Agent loads companion skill on-demand (39-line reference stub)
       ↓
Companion skill points to canonical source (e.g., piomin/claude-ai-spring-boot)
```

### Structure

| Layer | Location | Purpose | Size |
|-------|----------|---------|------|
| **Meta-skill** | `skills/java-developer/SKILL.md` | Core patterns + companion registry table | ~467 lines |
| **Companion skill** | `skills/jpa-hibernate-patterns/SKILL.md` | Reference stub with source URL + when-to-use | ~39 lines |
| **Canonical source** | GitHub repo (external) | Full implementation guidance | Varies |

### Companion Skills (22 total, linked from java-developer)

| Category | Skills |
|----------|--------|
| **Framework** | `spring-boot-enterprise`, `spring-boot-4x`, `restart-spring-boot` |
| **Language** | `java-streams`, `java-optional`, `java-code-quality`, `java-design-patterns`, `java-logging-patterns`, `jspecify-nullability` |
| **Database** | `jpa-hibernate-patterns`, `jooq-best-practices`, `postgres-table-design`, `pgvector-search`, `postgres-text-search` |
| **Testing** | `mutation-testing`, `coverage-kover-gradle`, `ralph-coverage`, `gradle-test-runner`, `jdb-debugger` |
| **Workflow** | `commit`, `rebase-commit`, `spec` |

### Benefits

- **Token-efficient**: Agent loads only the companion skill it needs (39 lines vs 467 lines)
- **Source attribution**: Each companion links to canonical jvmskills.com repo
- **Discoverable**: Registry table in meta-skill shows all available companions
- **Maintainable**: Add/remove companions without touching core skill

### Source Repositories

All companion skills reference canonical sources from [jvmskills.com](https://jvmskills.com):
- [piomin/claude-ai-spring-boot](https://github.com/piomin/claude-ai-spring-boot) — Spring Boot, JPA, code quality, design patterns, logging
- [martinfrancois/java-streams-skill](https://github.com/martinfrancois/java-streams-skill) — Streams API
- [martinfrancois/java-optionals-skill](https://github.com/martinfrancois/java-optionals-skill) — Optional patterns
- [sivaprasadreddy/sivalabs-agent-skills](https://github.com/sivaprasadreddy/sivalabs-agent-skills) — Spring Boot 4.x, JSpecify
- [timescale/pg-aiguide](https://github.com/timescale/pg-aiguide) — PostgreSQL design, pgvector, text search
- [jvm-skills/jvm-skills](https://github.com/jvm-skills/jvm-skills) — jOOQ, mutation testing, Kover, workflow skills
- [brunoborges/jdb-agentic-debugger](https://github.com/brunoborges/jdb-agentic-debugger) — JDB debugging

---

[workflow-shield]: https://img.shields.io/badge/Workflow-Orchestration-blue?style=for-the-badge
