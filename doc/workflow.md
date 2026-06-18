<!-- omit from toc -->

# Orchestration Contract & State Machine

> **Contract template**: `contract/contract.template.json`
> **State machine rules**: `rules/rules.json`

The orchestration contract is the shared JSON envelope that tracks every task from start to finish. It is the single source of truth for what phase we are in, decisions made, scoring results, and retry state.

[![Doc][workflow-shield]][workflow-url]

---

## Part A — Fundamentals

This part covers the core orchestration mechanics: state machine transitions, contract envelope structure, and the mandatory read→activity→write protocol that governs every delegation cycle.

### A1. State Machine Diagram + Transitions

```
INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE
                                                                                       ↓
                                                                                  BLOCKED
```

#### Transitions

| Transition | Gate | Description |
|---|---|---|
| INIT → PLAN | Task starts | Envelope created with state=INIT, delegate to system-analyst |
| PLAN → PLAN_SCORED | Scoring pipeline | Score ≥ 70 → PASS, 50-69 → RETRY, <50 → BLOCKED |
| PLAN_SCORED → EXECUTE | Score ≥ 70 | Plus SDD spec gate: spec must be approved |
| EXECUTE → EXECUTE_SCORED | Scoring pipeline | Same scoring thresholds |
| EXECUTE_SCORED → REVIEW | Score ≥ 70 | Delegate to quality-analyst |
| REVIEW → REVIEW_SCORED | Scoring pipeline | Verdict: PASS/BLOCK/FLAG |
| REVIEW_SCORED → COMPLETE | Score ≥ 70 | All gates passed, ship ready |
| Any → BLOCKED | Score < 50 or attempt ≥ 3 | Escalated to user |

Source of truth: `rules/rules.json` §state_machine.transitions.

### A2. Contract Envelope Structure

The envelope is stored in lean-ctx knowledge as `orchestration-contract`. File: `contract/contract.template.json`. Full schema at `contract/contract.schema.json`.

```json
{
  "state": "PLAN_SCORED",
  "session": {
    "task_id": "task-slug",
    "branch": "feature/20260616-task",
    "created_at": "2026-06-16T10:00:00Z"
  },
  "requirements": {
    "goal": "What we're building",
    "scope": {
      "included": ["files in scope"],
      "excluded": ["out of scope"],
      "parallel_eligible": false
    }
  },
  "decisions": {
    "architecture": "key decisions",
    "design": "design choices"
  },
  "governance": {
    "constraints": ["rules to follow"],
    "enforced_by": "agent-type"
  },
  "score": {
    "rules": { "pass": 5, "fail": 0, "deduction": 0, "subtotal": 100 },
    "judge": { "score": 85, "rationale": "...", "missing_items": [] },
    "combined": 85,
    "verdict": "PASS"
  },
  "retry": {
    "attempt": 0,
    "current_phase": "plan",
    "issues": []
  },
  "outputs": {
    "plan": "plan document path",
    "execute": "implementation summary",
    "review": "review findings"
  },
  "metrics": {
    "cost_tokens": 15000,
    "elapsed_ms": 450000,
    "agents_used": ["system-analyst"],
    "phases_completed": ["plan:2026-06-16T10:05:00Z"]
  },
  "lessons_learned": [
    "What went well",
    "What went wrong",
    "What to change next time"
  ]
}
```

### A3. Contract Read/Write Protocol

The contract is the single source of truth. Every delegation starts by reading the contract (lean-ctx ctx_knowledge recall). Every delegation ends by writing back (lean-ctx ctx_knowledge remember). This read→activity→write cycle is mandatory for every phase.

**Pre-flight enforcement**: Before any work begins, the delegating agent (tech-lead) loads the contract via `lean-ctx ctx_knowledge recall --key "orchestration-contract" --mode "exact"`. If found → extract decisions.*, governance.*, retry.issues[]. If not found → create fresh from contract.template.json. This ensures crash recovery and cross-session resumption.

| Phase | Reads from Contract | Activity | Writes to Contract | Delegated To |
|---|---|---|---|---|
| INIT→PLAN | requirements.*, governance.*, retry.issues[] | Delegate system design & plan | state: PLAN, session.*, scope.* | system-analyst |
| PLAN→PLAN_SCORED | outputs.plan, scope.* | Score plan (+ SDD spec) | state: PLAN_SCORED, score.*, decisions.* | tech-lead |
| PLAN_SCORED→EXECUTE | score.*, decisions.*, outputs.plan | Implement per spec | state: EXECUTE, governance.mode: spec | developer |
| EXECUTE→EXECUTE_SCORED | outputs.code_changes[], outputs.test_results | Score implementation | state: EXECUTE_SCORED, score.* | tech-lead |
| EXECUTE_SCORED→REVIEW | score.*, outputs.* | Code quality review | state: REVIEW | quality-analyst |
| REVIEW→REVIEW_SCORED | outputs.agent_reports[] | Score review findings | state: REVIEW_SCORED, score.*, outputs.score_summary | tech-lead |
| REVIEW_SCORED→COMPLETE | score.*, outputs.* | Ship, learn, persist | state: COMPLETE, lessons_learned[], metrics.* | quality-analyst-learner |
| At BLOCKED | retry.issues[], retry.cur_phase | Escalate, persist | state: BLOCKED, retry.escalation_trace[], retry.attempt+1 | tech-lead |

---

## Part B — Lifecycle Walkthrough

This part walks through each phase of the state machine end-to-end, documents the BLOCKED escalation path, and shows where gates (DDD, SDD, Ponytail) fire during the lifecycle.

### B1. Phase-by-Phase Walkthrough

#### B1a. INIT → PLAN [Gate: DDD]

- **Reads**: requirements.* (goal, constraints, acceptance criteria), governance.*, retry.issues[]
- **Delegates to**: @system-analyst (architecture analysis + implementation plan)
- **Gate**: DDD fires here — tech-lead asks "What assumptions am I making about scope and constraints?" before delegating. If the task is complex (>3 files, cross-service, >30 min estimate), DDD may recommend expanding scope or requesting user clarification.
- **Activity**: System-analyst runs gitnexus_impact on all affected symbols, traces execution flows, produces a structured plan with dependency graph, risk assessment, rollback strategy, task breakdown, and edge case analysis.
- **Outputs**: state=PLAN, session.* (task_id, branch, created_at), scope.* (included paths, excluded paths, parallel_eligible) populated
- **Scoring threshold**: n/a (always advances to PLAN_SCORED for scoring)
- **Writes back**: contract.outputs.plan (full plan document), contract.decisions.* (architecture decisions made during planning)

#### B1b. PLAN → PLAN_SCORED

- **Reads**: outputs.plan, scope.*, requirements.*
- **Delegates to**: @tech-lead (scoring pipeline — self-scored, not subagent)
- **Activity**: Run Tier 1 rule checks (schema valid, permissions, blast radius, writing order, over-engineering, required fields) → Tier 2 LLM-as-Judge (requirements fulfillment, governance compliance, completeness, edge cases) → Tier 3 combined verdict
- **Outputs**: state=PLAN_SCORED, score.* (rules subtotal, judge score, combined score, verdict), decisions.* (any refinements)
- **Gate**: Score ≥ 70 → PASS advances to EXECUTE. 50-69 → RETRY — re-delegate to system-analyst with issues[]. <50 → BLOCKED.
- **SDD gate trigger**: If score ≥ 70, SDD spec gate fires at the next transition. The plan is ready for spec-driven implementation.

#### B1c. PLAN_SCORED → EXECUTE [Gate: SDD]

- **Reads**: score.* (proves ≥70), decisions.* (approved architecture), outputs.plan (full spec to implement from)
- **Gate**: SDD fires here — mandatory spec approval before any code is written. The plan must be in Given/When/Then format (or equivalent formal specification) before execution begins:
  1. System-analyst produces a spec with Given/When/Then
  2. Spec is scored (≥ 70 required) — if <70, revise spec
  3. Developer implements FROM the spec — every AC-N maps to at least one test
  4. Tests validate the spec — "Done When" conditions define exit criteria
  *Exempted for*: trivial bug fixes (1 file, <30 lines), config-only changes, documentation.
- **Delegates to**: @developer (implementation per spec, TDD cycle)
- **Writes back**: state=EXECUTE, governance.mode: spec, governance.current_guidance (any execution direction from orchestrator)

#### B1d. EXECUTE → EXECUTE_SCORED [Gate: Ponytail]

- **Reads**: outputs.plan (task breakdown, dependency graph), decisions.* (approved architecture, coding standard)
- **Gate**: Ponytail fires before ANY code is written — run the 6-rung frugality ladder:
  1. Does this need to exist? → skip it (YAGNI)
  2. Standard library does it? → use it
  3. Native platform feature? → use it
  4. Already-installed dependency? → use it
  5. Can this be one line? → one line
  6. Only then: minimum code that works

  Intentional shortcuts are marked with `ponytail:` comments documenting the ceiling and upgrade path:
  ```java
  // ponytail: global lock, wont scale past 10 concurrent. Upgrade: ConcurrentHashMap + stripe locks
  ```
  The scoring pipeline includes a SIMPLICITY_001 rule (HIGH severity) that detects unnecessary abstractions, unused deps, and over-engineered patterns. An `over_engineering_deduction: 15` applies in Tier 1 when YAGNI violations are detected.

- **Delegates to**: @developer (implement per spec, Writing Order: port → service → mapper → adapter → constants → events → tests)
- **Activity**: TDD cycle per task (red → green → refactor), gitnexus_impact before every edit, tests alongside code
- **Outputs**: outputs.code_changes[] (files_created, files_modified), outputs.test_results (test_count, pass, fail)
- **Writes back**: state=EXECUTE_SCORED

#### B1e. EXECUTE_SCORED → REVIEW [Gate: DDD]

- **Reads**: outputs.code_changes[], outputs.test_results, outputs.plan (for scope comparison)
- **Delegates to**: @tech-lead (scoring pipeline — self-scored)
- **Gate**: DDD fires here — "What would I criticize about my own code?" Tech-lead runs an adversarial self-review before delegating to quality-analyst. If DDD reveals gaps, they are flagged in risks_introduced[] for the reviewer.
- **Activity**: Score implementation (Tier 1 → Tier 2 → Tier 3). Pass ≥ 70 advances to REVIEW.
- **Writes back**: state=REVIEW, score.* (updated with implementation score)

#### B1f. REVIEW → REVIEW_SCORED [Gate: Ponytail]

- **Reads**: score.* (proves ≥70), outputs.* (code_changes, test_results, risks_introduced[])
- **Delegates to**: @quality-analyst (code quality review — 6 dimensions)
- **Gate**: Ponytail fires here — quality-analyst runs the Over-Engineering Check alongside the standard review:
  - Is every abstraction justified? Any YAGNI violations?
  - Could stdlib or existing deps replace any custom code?
  - Any unnecessary indirection (factories, interfaces with one impl, over-abstracted patterns)?
  - Are there `ponytail:` debt comments with documented ceilings and upgrade paths?
  - Could any file be eliminated entirely?
  - Are any new dependencies avoidable?
- **Activity**: Review 6 dimensions — correctness, design, security, performance, database (if applicable), DevOps operability
- **Outputs**: outputs.agent_reports[] with findings per dimension, outputs.review_verdict (PASS/BLOCK/FLAG)
- **Writes back**: state=REVIEW_SCORED

#### B1g. REVIEW_SCORED → COMPLETE

- **Reads**: outputs.agent_reports[], score.*, outputs.code_changes[], outputs.test_results
- **Delegates to**: @tech-lead (score review findings) + @quality-analyst-learner (post-exec analysis)
- **Activity**: Score review (Tier 1 → Tier 2 → Tier 3). Score ≥ 70 → COMPLETE. Quality-analyst-learner extracts lessons, identifies patterns and gotchas, persists knowledge_updates[] to lean-ctx ctx_knowledge.
- **Outputs**: state=COMPLETE, lessons_learned[], metrics.* (cost_tokens, elapsed_ms, agents_used, phases_completed), knowledge_updates[]
- **Writes back**: Full envelope to lean-ctx, archive snapshot via scripts/snapshot-contract.sh

#### DDD Gate Firing Summary

Doubt-Driven Development (DDD) subjects non-trivial decisions to adversarial review. It fires at 6 points across the lifecycle:

1. **B1a** (INIT→PLAN) — "What assumptions am I making about scope and constraints?" Before delegating to system-analyst, the tech-lead challenges the task framing.
2. **B1e** (EXECUTE_SCORED→REVIEW) — "What would I criticize about my own code?" Before review, the tech-lead runs an adversarial self-review of the implementation.
3. **Before commit** — "What did I miss?" Developer runs DDD on every non-trivial change before committing (branches, cross-service calls, shared state modifications).
4. **After review** — "Did the reviewer find what I expected?" After quality-analyst review, the tech-lead compares DDD predictions against actual findings.
5. **At BLOCKED** — "What assumption was wrong?" Every BLOCKED event triggers a root-cause challenge to avoid repeating the same failure.

DDD triggers when: code introduces >2 branches (if/else, switch, try/catch), calls cross-module boundaries, modifies shared state, or sits in a hot path or transaction. Load via `/skill doubt-driven-development`.

### B2. BLOCKED State: Escalation & Resume

When state becomes BLOCKED, all agents must follow this strict escalation protocol before any retry attempt:

1. **Immediate stop** — Do NOT continue execution. All agents halt. Any in-flight work is discarded.
2. **Persist last state** — Save envelope with `state=BLOCKED`, populate `retry.issues[]`, append to `retry.escalation_trace[]`:
   ```json
   {
     "phase": "PLAN|EXECUTE|REVIEW",
     "blocked_at": "ISO-8601",
     "reason": "Summary of why blocked",
     "issues": ["issue1", "issue2"],
     "attempt": 1
   }
   ```
   The escalation trace is an append-only array — each BLOCKED event adds a new entry. This preserves full escalation history across retry cycles.
3. **Escalate to user** — Summarize blockers: `"I hit BLOCKED at ${phase}. Issues: ${issues}. Please review."`
4. **Wait for user response** — No polling loop. The orchestrator waits for user input. User may: adjust scoring threshold, provide fix guidance, override to continue, or discard the task entirely.
5. **Resume from INIT** — User response triggers BLOCKED→INIT transition. A fresh envelope is created for the retry. Previous `retry.issues[]` and `retry.escalation_trace[]` are preserved for context — the retry learns from past failures.
6. **Max 3 retries** — If the same phase blocks 3 times (checked via `retry.attempt`), permanent BLOCKED. User must explicitly override with `retry.override: true` to continue.

**Timeout guard**: If scoring pipeline exceeds `scoring.timeout_ms` (default: 30s), treat as scoring failure and set state=BLOCKED with issue `scoring_timeout`.

**DDD at BLOCKED**: DDD fires on every BLOCKED event — "What assumption was wrong?" This question feeds into the retry guidance and helps avoid repeating the same failure pattern.

### B3. Learning Loop (Lessons → Knowledge)

After every COMPLETE transition, the quality-analyst-learner extracts lessons from the session and persists them to the knowledge base. This creates a closed learning loop:

1. **Extract lessons** — quality-analyst-learner reads outputs.*, score.*, retry.issues[] from the completed envelope
2. **Identify patterns** — What went well? What went wrong? What to change next time? What gotchas were discovered?
3. **Persist knowledge** — Write to lean-ctx ctx_knowledge with category (architecture, testing, governance) and key patterns
4. **Feed forward** — The next session's pre-flight protocol recalls recent patterns, so lessons from session N influence session N+1

The `lessons_learned[]` array in the contract envelope captures the raw output. The quality-analyst-learner transforms this into structured knowledge_updates[] that are persisted to the knowledge graph for cross-session learning.

---

## Part C — Agent Integration Matrix

This part maps all 11 agents to their contract states, plugins, MCPs, and skills. It also documents the toolkit data flow, agent pipeline, and cross-reference table for every concept in the orchestration system.

### C1. Full 11-Agent × 3-Dimension Table

| Agent | Contract States | Plugins | Key MCPs | Skills to Load | Usage Pattern |
|---|---|---|---|---|---|
| **tech-lead** | all 8 | opencode-notify, opencode-goal-plugin, @openspoon/subtask2 | gitnexus, graphify, lean-ctx, postgres, firecrawl | orchestration-template, brainstorming, writing-plans, executing-plans, doubt-driven-dev, spec-driven-dev, subagent-driven-dev, adaptive-solver | `/skill orchestration-template` → load contract → delegate → score → persist |
| **system-analyst** | INIT, PLAN, PLAN_SCORED | @zenobius/opencode-skillful, opencode-websearch-cited | gitnexus, graphify, lean-ctx, context7, postgres, firecrawl | system-analyst, business-analyst, brainstorming, writing-plans, doubt-driven-dev, spec-driven-dev, software-developer | `/skill system-analyst` → impact analysis → plan → populate outputs.plan |
| **developer** | EXECUTE, EXECUTE_SCORED | @morphllm/opencode-morph-plugin, opencode-worktree | gitnexus, lean-ctx, firecrawl | subagent-driven-dev, test-driven-dev, java-developer, software-developer, simplify | Load plan from contract → TDD → implement → test → commit |
| **developer-fixer** | all 8 | @morphllm/opencode-morph-plugin, opencode-worktree | gitnexus, lean-ctx | java-developer, simplify, subagent-driven-dev | impact → scoped edit → verify |
| **developer-explorer** | all 8 | @morphllm/opencode-morph-plugin, @zenobius/opencode-skillful | gitnexus, graphify, lean-ctx, context7, firecrawl | gitnexus-exploring, systematic-debugging | query/context → explore → report |
| **developer-librarian** | all 8 | opencode-websearch-cited, @zenobius/opencode-skillful | context7, firecrawl, gh_grep, websearch | firecrawl-search | firecrawl_search → context7_query → synthesize |
| **developer-council** | all 8 | (none) | lean-ctx, gitnexus, graphify | (multi-LLM consensus) | council_session → consensus → report |
| **developer-observer** | all 8 | (none) | lean-ctx, firecrawl | firecrawl-scrape, systematic-debugging, verification-before-completion | firecrawl_parse → analyze → report |
| **software-architect** | INIT, PLAN, PLAN_SCORED | @zenobius/opencode-skillful | gitnexus, graphify, lean-ctx, context7, firecrawl | system-analyst, systematic-debugging, brainstorming, software-developer | architecture review → tradeoffs → ADR |
| **quality-analyst** | REVIEW, REVIEW_SCORED | @zenobius/opencode-skillful | gitnexus, lean-ctx, postgres, firecrawl | code-review-and-quality, qa-expert, security-expert, devops-expert, java-developer | Read code → review 6 dimensions → produce findings report |
| **quality-analyst-learner** | REVIEW_SCORED, COMPLETE | @zenobius/opencode-skillful | gitnexus, lean-ctx, firecrawl | verification-before-completion, software-developer, firecrawl-knowledge-ingest | Post-exec analysis → extract lessons → persist knowledge_updates[] |

### C2. Agent Profiles

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

### C3. Toolkit Data Flow

#### Data Flow Steps

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

#### Agent Pipeline

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

#### Folder → Workflow Mapping

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

#### Tool Selection by Phase

| Phase | Agent | Primary Tools | Skills Loaded |
|---|---|---|---|
| INIT → PLAN | tech-lead → system-analyst | gitnexus_impact, gitnexus_query, context, graphify | brainstorming, writing-plans, doubt-driven-dev |
| PLAN_SCORED | tech-lead | lean-ctx (scoring), lean-ctx (persist) | spec-driven-dev (SDD gate) |
| EXECUTE | developer | lean-ctx (read/edit), gitnexus (impact) | java-developer, test-driven-dev, simplify (ponytail) |
| EXECUTE_SCORED | tech-lead | lean-ctx (scoring) | doubt-driven-dev (DDD gate), over-engineering check |
| REVIEW | quality-analyst | lean-ctx (read), gitnexus (impact), postgres (DB) | code-review-and-quality, qa-expert, security-expert, over-engineering check |
| REVIEW_SCORED | tech-lead | lean-ctx (scoring + persist) | verification-before-completion |
| COMPLETE | quality-analyst-learner | lean-ctx (knowledge), gitnexus (detect) | verification-before-completion, software-developer |

#### Cross-Reference Table

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

---

## Part D — Scoring & Governance

This part defines how every delegation is scored across 3 tiers, what validation gates can block transitions, and the governance rules that constrain all agent behavior.

### D1. Scoring Pipeline

The scoring pipeline runs after every delegation (PLAN, EXECUTE, REVIEW phases). It produces a combined verdict that determines whether the state advances, retries, or blocks. The scoring pipeline is self-scored by tech-lead — no subagent is involved.

```
Tier 1 — Rule-Based Checks (tool calls, no LLM)
  Start at 100. Deduct:
  - Schema valid?          -15  (validate-contract.sh)
  - Permissions violated?  -40  (governance check)
  - Blast radius safe?     -40  if HIGH/CRITICAL (gitnexus_impact)
  - Writing order correct? -15  if wrong order per AGENTS.md
  - Over-engineering?      -15  if YAGNI violated (SIMPLICITY_001 rule)
  - Required fields?       -15  (envelope completeness)

  If subtotal < 70 → skip Tier 2, use subtotal as combined

Tier 2 — LLM-as-Judge (if Tier 1 ≥ 70)
  Score 0-100:
  - Fulfills requirements?  0-40  (matches acceptance criteria)
  - Follows governance?     0-30  (compliance with _governance.md)
  - Completeness?           0-20  (all tasks done, tests written)
  - Edge cases covered?     0-10  (nulls, errors, boundaries)

Tier 3 — Combined Verdict
  ≥ 70  → PASS   → advance state
  50-69 → RETRY  → re-delegate with issues; max 3 attempts
  < 50  → BLOCKED → escalate to user
```

**SIMPLICITY_001 rule**: Detects unnecessary abstractions, unused deps, and over-engineered patterns. An `over_engineering_deduction: 15` applies when YAGNI violations are found. This rule is checked both at scoring time (Tier 1) and during code review (Ponytail Over-Engineering Check).

See `rules/rules.json` §scoring for threshold values and rule configuration.

### D2. Validation Gates (block_on)

These gates are enforced at every state transition. If any gate triggers, the transition is BLOCKED regardless of score.

| Criterion | Threshold | Action |
|---|---|---|
| Test failures | > 3 | BLOCKED |
| Score drop (between phases) | > 30 points drop | BLOCKED — regression alert |
| Compile errors | > 1 | BLOCKED |
| Code-reviewer verdict | BLOCK (from quality-analyst) | BLOCKED |
| Schema validation failure | Any failure | BLOCKED — -15 Tier 1 deduction |
| Blast radius HIGH/CRITICAL | Unacknowledged | BLOCKED — -40 Tier 1 deduction |

Source of truth: `rules/rules.json` §scoring.validation_gates. All threshold values are configured there; modify that file, not this document.

### D3. Governance

Reference: `agents/_governance.md`

The shared governance document defines rules all agents must follow:

- **Permission boundaries** — what each agent role may and may not do (e.g., read-only agents never write code)
- **Communication rules** — token efficiency, trade-off transparency, admission of unknowns
- **Escalation rules** — when to escalate to the orchestrator or user (BLOCKED state, confidence < 3/5, uncovered risk)
- **Quality gates** — minimum scoring thresholds (≥70), validation criteria per phase
- **Safety constraints** — never push to main/master, never force push, never edit without gitnexus_impact

Agents source their governance rules from this file at session start. The orchestrator enforces governance compliance during Tier 2 scoring (0-30 points). When adding a new agent, add a governance section to `agents/_governance.md` with agent-specific rules, then reference it in the agent's instruction file.

---

## Part E — Operations & Reference

This part covers operational procedures (post-flight protocol, session lifecycle), tooling (audit observability, conventions scripts), and reference material (GitNexus flows, JSON Schema).

### E1. Post-Flight Protocol

This 8-step protocol runs before every commit. It verifies impact, persists knowledge, archives session state, and re-indexes code intelligence. Execute all 8 steps unless exceptions apply.

| # | Step | Tool | Exceptions |
|---|---|---|---|
| 0 | Validate contract | `bash scripts/validate-contract.sh --file session/{branch}/contract.json --score` | — |
| 1 | Impact verify | `gitnexus_impact` | Docs-only skip |
| 2 | Change detect | `gitnexus_detect_changes` | Docs-only skip |
| 3 | Knowledge persist | `lean-ctx ctx_knowledge remember` | — |
| 4 | Session archive | `bash scripts/snapshot-contract.sh --snapshot-only` | — |
| 5 | Save conversation | `lean-ctx ctx_session save` | — |
| 6 | Re-index GitNexus | `bash scripts/gitnexus-analyze.sh` | Docs-only skip |
| 7 | Re-index Graphify | `graphify --update 2>/dev/null \|\| true` | Docs-only skip |

#### Pre-Flight Protocol (Session Start)

Every agent runs this protocol at session start, before any work:

| # | Step | Tool |
|---|------|------|
| 1 | Load orchestration envelope | lean-ctx ctx_knowledge recall --key "orchestration-contract" |
| 2 | Read session state | lean-ctx ctx_read session/{branch}/state.md |
| 3 | Read project vision | lean-ctx ctx_read PROJECT.md |
| 4 | Recall recent patterns | lean-ctx ctx_knowledge recall --query "architecture" |
| 5 | Re-index if stale (>1 hour) | bash scripts/gitnexus-analyze.sh |
| 6 | Check graph stats | graphify_graph_stats |
| 7 | Load relevant skills | /skill matching domain |

**One-shot alias**: `save session` = all 8 post-flight steps. Always run the full protocol — partial saves lose audit trail, break resumption, or leave stale indexes.

### E2. Session Lifecycle

Every orchestration session persists its contract state to the `session/` directory for cross-session traceability and safe resumption.

#### Directory Layout

```
contract/                    ← Contract templates (immutable)
  contract.template.json
  contract.schema.json
  state.template.md
  superpowers-contract.json

session/                     ← Live state + historical archive
  state.md                   ← Append-only log of ALL state transitions
  index.md                   ← Master branch index (one row per branch)
  {branch-name}/
    contract.json
    contract.schema.json
    state.md
    superpowers-contract.json
```

#### Lifecycle Protocol

| Event | Action |
|---|---|
| **Session start** | Read git branch → check `session/{branch}/` exists → if yes, resume from there (load state, decisions, outputs); if no, init fresh from `contract/` templates |
| **State transition** | Update `session/{branch}/contract.json` → snapshot via `scripts/snapshot-contract.sh` |
| **Session end** (COMPLETE/BLOCKED) | Final snapshot → append summary to `session/state.md` → update `session/index.md` |
| **Branch switch** | Snapshot current branch first → checkout new branch → load `session/NEW/{branch}/` if exists, else init fresh |

The `session/state.md` is an append-only chronological log — every state transition creates a new entry with timestamp, phase, score, and summary. This provides a durable audit trail for every session.

#### Snapshot Command

```bash
bash scripts/snapshot-contract.sh --summary "State: ${STATE} — brief description"   # Full snapshot
bash scripts/snapshot-contract.sh --snapshot-only                                      # Files-only (skip index updates)
bash scripts/snapshot-contract.sh --dry-run --verbose                                  # Preview without changes
```

#### Verification

```bash
ls -la session/                                    # state.md, index.md, branch dirs
cat session/state.md                               # Chronological log
cat session/index.md                               # All branches with status
ls session/{branch-name}/                          # 4 contract files
```

#### Why Per-Branch Archival Matters

Without per-branch snapshots, contract files get overwritten when switching branches or resuming sessions. The `session/` archive preserves:
- **Audit trail**: `session/state.md` grows monotonically — every state transition, every decision, every blocker
- **Safe resume**: `session/{branch}/contract.json` is the exact state from last session — no reconstruction needed
- **Discoverability**: `session/index.md` shows all branches with their status at a glance

### E3. Audit-Observability

Reference: `skills/audit-observability/SKILL.md`. Load: `skill({name: "audit-observability"})`.

Three pillars of orchestration observability:

**1. State Contract Transitions** — Tracks every envelope state change: `INIT → PLAN → PLAN_SCORED → ... → COMPLETE` or `BLOCKED`. Records transition timestamps and duration, score at transition time, which agent triggered the transition, escalation events and retry count. Useful for detecting stalled workflows, infinite retry loops, or unexpected state regressions.

**2. Score Analytics** — Aggregates scoring pipeline results over time: Tier 1 (rule-based) subtotals per phase, Tier 2 (LLM-as-judge) scores and rationales, combined verdict distribution (PASS / RETRY / BLOCKED), score trends (improving, degrading, or oscillating), and blast radius penalty frequency. Score analytics feed into the metrics.* contract fields.

**3. Cross-Service Consistency Enforcement** — Validates that all services, agents, and components adhere to the shared contract: envelope schema compliance across all agents, uniform scoring criteria application, consistent state machine rule interpretation, and contract field naming and type consistency.

### E4. Conventions Checking

Five scripts maintain code quality, architecture conventions, and contract integrity. All are integrated into CI and should be run before commit.

**`scripts/validate-contract.sh`** — Seven-step envelope validation: JSON validity, required fields, state enum validation, nested field structure, content quality scoring, field-level ACL enforcement, and transition validation against rules/rules.json. Enforces the contract envelope integrity at every state change.

```bash
bash scripts/validate-contract.sh --file session/{branch}/contract.json --score
```

A validation failure triggers a Tier 1 scoring deduction of 15 points and may BLOCK the transition.

**`scripts/check-conventions.sh`** — Project-wide conventions check: JSON Schema compliance of `session/{branch}/contract.json`, file and directory structure conventions, naming patterns and project layout rules, and scoring pipeline configuration consistency. Run before any PR.

```bash
scripts/check-conventions.sh
```

**`scripts/scan-ponytail-debt.sh`** — Scans the codebase for `ponytail:` debt comments and generates a technical debt report. For each shortcut: file and line number, ceiling (what limit the shortcut imposes), upgrade path (how to fix it properly). Feeds into the SIMPLICITY_001 scoring rule — unresolved ponytail debt with no documented upgrade path may trigger an `over_engineering_deduction` in Tier 1.

```bash
scripts/scan-ponytail-debt.sh
```

**`scripts/detect-parallel-conflicts.sh`** — Detects overlapping file modifications from parallel agents. Accepts file lists or unified diffs. Required when `scope.parallel_eligible` is true to prevent conflicting writes.

```bash
bash scripts/detect-parallel-conflicts.sh --file1 /tmp/a.txt --file2 /tmp/b.txt
```

**`scripts/persist-contract.sh`** — Atomic envelope persistence via temp-file + rename pattern with optional score injection. Prevents partial writes that could corrupt the contract envelope.

```bash
bash scripts/persist-contract.sh --file session/{branch}/contract.json --inject-score 85
```

#### Ponytail Debt Convention

Intentional shortcuts are marked with `ponytail:` comments documenting the ceiling and upgrade path:

```java
// ponytail: global lock, wont scale past 10 concurrent. Upgrade: ConcurrentHashMap + stripe locks
```

Each ponytail comment must document: why the shortcut exists (constraint), what limit it imposes (ceiling), and how to fix it properly (upgrade path). The `scripts/scan-ponytail-debt.sh` script generates a technical debt report from these markers. Unresolved ponytail debt with no documented upgrade path triggers a SIMPLICITY_001 rule deduction of 15 points in Tier 1 scoring.

See `usage/ponytail.md` for full reference, or `agent.md §5` for the 6-rung frugality ladder in context.

### E5. GitNexus Execution Flows

GitNexus indexes the codebase as a knowledge graph. Current index stats: 1675 symbols, 1666 relationships, 0 execution flows.

**0 execution flows registered**: GitNexus auto-detects execution flows when entry points are annotated. Currently no orchestration paths are mapped as GitNexus processes. All lifecycle paths (INIT→PLAN→…→COMPLETE) are documented in Part A but not yet machine-annotated.

**Future work** — Add GitNexus execution flow annotations to:
- **Orchestration lifecycle**: INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE
- **Scoring pipeline**: Delegation → Tier 1 rules → Tier 2 LLM judge → Tier 3 verdict → state transition
- **Escalation flow**: BLOCKED → persist → user intervention → resume with retry guidance

When flows are annotated, use `gitnexus_query({query: "orchestration flow"})` for step-by-step traces or read `gitnexus://repo/workflow-state-engine/process/{name}` for a specific flow.

See `skills/gitnexus/` for the full annotation guide.

### E6. JSON Schema Reference

Full schema: `contract/contract.schema.json`. Validate against any envelope:

```bash
bash scripts/validate-contract.sh --file session/{branch}/contract.json --score
```

The JSON Schema defines: required envelope structure for all fields (state, session, requirements, decisions, scoring, retry, outputs, metrics), valid state values and allowed transitions, type constraints (string, number, array, object) with field descriptions, and optional/required status per field. A validation failure triggers a Tier 1 scoring deduction of 15 points.

All agents should validate their envelope mutations against the schema before persisting. The orchestrator enforces schema compliance at every transition via Tier 1 rule checks.

---

[workflow-shield]: https://img.shields.io/badge/Workflow-Orchestration-blue?style=for-the-badge
[workflow-url]: #
