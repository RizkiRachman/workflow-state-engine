<!-- omit from toc -->
# Workflow State Engine -- Orchestration Toolkit

[![Project Status](https://img.shields.io/badge/status-active-brightgreen?style=for-the-badge)](https://github.com/RizkiRachman/workflow-state-engine)
[![GitHub](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github)](https://github.com/RizkiRachman/workflow-state-engine)

**Contract-driven state machine orchestration engine for AI agent workflows.** A shared JSON envelope (`contract/contract.json`) drives an 8-state state machine that coordinates 11 specialized AI agents across planning, execution, and review phases. Built for multi-agent orchestration with three-tier scoring, cross-session learning, and audit-grade observability.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Tech Stack

- **Language**: Markdown, JSON, Shell
- **Framework**: None -- doc-driven orchestration toolkit
- **Architecture**: Contract-driven state machine (agents/ -> skills/ -> contract/)
- **Storage**: `contract/contract.json` (shared envelope) + `ctx_knowledge` (cross-session persistence)
- **API Spec**: `contract/contract.schema.json` (canonical envelope schema)
- **Validation**: Shell scripts (`scripts/check-conventions.sh`, `scripts/scan-ponytail-debt.sh`, `scripts/validate-toolkit.sh`) + CI (`.github/workflows/governance.yml`)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Core Concepts

| Concept | Description |
|---------|-------------|
| **Shared JSON Envelope** | `contract/contract.json` -- single source of truth for state, decisions, scoring, and outputs across all agents |
| **State Machine** | 8 states: `INIT -> PLAN -> PLAN_SCORED -> EXECUTE -> EXECUTE_SCORED -> REVIEW -> REVIEW_SCORED -> COMPLETE` (+ `BLOCKED` escalation) |
| **Scoring Pipeline** | Three-tier: Rule-based checks (Tier 1) -> LLM-as-Judge (Tier 2) -> Combined Verdict of PASS / RETRY / BLOCKED (Tier 3) |
| **Scoring Thresholds** | PASS >= 70, RETRY 50-69 (max 3 attempts), BLOCKED < 50 |
| **11 Agent Types** | Orchestrator (tech-lead), planners (system-analyst, software-architect), implementers (developer, developer-fixer), reviewers (quality-analyst, quality-analyst-learner), support (developer-explorer, developer-librarian, developer-council, developer-observer) |
| **36 Skill Directories** | Runnable skills including java-developer, system-analyst, writing-plans, spec-driven-development, test-driven-development, brainstorming, qa-expert, security-expert, devops-expert, and more |
| **Cross-Session Learning** | Lessons, patterns, and gotchas persisted via `ctx_knowledge` -- survives session restarts and spans branches |
| **Frugality Ladder (Ponytail)** | YAGNI -> stdlib -> platform -> existing deps -> one line -> minimum code. Intentional shortcuts marked with `ponytail:` comments |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Getting Started

```bash
git clone https://github.com/RizkiRachman/workflow-state-engine.git
cd workflow-state-engine
bash setup.sh                    # bootstrap: create all .opencode/ -> root-level symlinks
```

Then load with OpenCode. The orchestrator (tech-lead agent) reads `contract/contract.json` on start. See [`doc/workflow.md`](workflow.md) for the full state machine and scoring reference.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Architecture

The toolkit is organized as a **3-layer framework** of agents, skills, and contracts:

- **`agents/` (11 agents)** -- Specialized instruction files defining role, state machine access, MCP permissions, and post-flight protocol. The tech-lead orchestrator delegates to planners, implementers, and reviewers in a spec-driven development (SDD) flow: Plan -> Spec Gate -> Execute -> Review -> Ship.

- **`skills/` (36 directories)** -- Runnable skill libraries providing deep guidance per domain. Each skill directory contains a `SKILL.md` with workflows, conventions, and quality gates. Loaded on demand via `/skill` when a task matches the skill's domain.

- **`contract/` (shared envelope)** -- `contract.json` is the single source of truth that persists state transitions, decisions, scoring results, token budgets, and audit logs across sessions. `contract.schema.json` is the canonical API schema. Cross-session memory lives in `ctx_knowledge` for durable pattern learning.

- **Before-Commit Protocol** -- Every session runs: impact verify (`gitnexus_impact`) -> change detect (`gitnexus_detect_changes`) -> knowledge persist (`ctx_knowledge remember`) -> graphify sync -> `contract/state.md` update -> session save (all 6 systems).

- **Doubt-Driven Development (DDD)** -- Non-trivial decisions get a fresh-context adversarial review before they stand. Used for correctness-critical, high-stakes, or unfamiliar-code decisions.

- **Spec-Driven Development (SDD)** -- Tasks crossing >3 files, multiple services, or estimated >30 min require GWT-format specs written before implementation begins. Specs are cross-examined via DDD before coding starts.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Reference Links

| Resource | Description |
|----------|-------------|
| [`agent.md`](../agent.md) | Main orchestrator instructions -- loaded by every agent at session start |
| [`doc/workflow.md`](workflow.md) | Canonical state machine, scoring pipeline, gates, and validation rules |
| [`doc/skill-conventions.md`](skill-conventions.md) | Skill authoring conventions |
| [`contract/contract.json`](../contract/contract.json) | Orchestration envelope (shared state) |
| [`contract/contract.schema.json`](../contract/contract.schema.json) | Envelope JSON Schema |
| [`rules/rules.json`](../rules/rules.json) | State machine transitions and scoring rules |
| [`scripts/check-conventions.sh`](../scripts/check-conventions.sh) | Convention validation |
| [`scripts/scan-ponytail-debt.sh`](../scripts/scan-ponytail-debt.sh) | Ponytail debt scanner |
| [`scripts/validate-toolkit.sh`](../scripts/validate-toolkit.sh) | Full toolkit validation |