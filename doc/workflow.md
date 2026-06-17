<!-- omit from toc -->

# Orchestration Contract & State Machine

> **Contract template**: `contract/contract.json`
> **State machine rules**: `rules/rules.json`

The orchestration contract is the shared JSON envelope that tracks every task from start to finish. It's the single source of truth for what phase we're in, decisions made, scoring results, and retry state.

[![Doc][workflow-shield]][workflow-url]

<a id="readme-top"></a>

## Table of Contents
1. [State Machine](#state-machine)
2. [Contract Envelope](#contract-envelope)
3. [Scoring Pipeline (after each delegation)](#scoring-pipeline-after-each-delegation)
4. [Validation Gates (block_on)](#validation-gates-block_on)
5. [DDD Gate (Doubt-Driven Development)](#ddd-gate-doubt-driven-development)
6. [SDD Gate (Spec-Driven Development)](#sdd-gate-spec-driven-development)
7. [Ponytail Gate (Frugality Ladder)](#ponytail-gate-frugality-ladder)
8. [Workflow Lifecycle](#workflow-lifecycle)
9. [Toolkit Integration Map](#toolkit-integration-map)
10. [Post-Flight Protocol (Before Commit)](#post-flight-protocol-before-commit)
11. [GitNexus Execution Flows](#gitnexus-execution-flows)
12. [Audit-Observability](#audit-observability)
13. [Governance](#governance)
14. [JSON Schema](#json-schema)
15. [Conventions Checking](#conventions-checking)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## State Machine

```
INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE
                                                                                       ↓
                                                                                  BLOCKED
```

### Transitions

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

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Contract Envelope

The envelope is stored in lean-ctx knowledge as `orchestration-contract`.

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

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Scoring Pipeline (after each delegation)

```
Tier 1 — Rule-Based Checks (tool calls, no LLM)
  Start at 100. Deduct:
  - Schema valid?        -15
  - Permissions violated? -40
  - Blast radius safe?    -40 if HIGH/CRITICAL
  - Required fields?      -15

  If subtotal < 70 → skip Tier 2, use subtotal as combined

Tier 2 — LLM-as-Judge (if Tier 1 ≥ 70)
  Score 0-100:
  - Fulfills requirements?  0-40
  - Follows governance?     0-30
  - Completeness?           0-20
  - Edge cases covered?     0-10

Tier 3 — Combined Verdict
  ≥ 70  → PASS   → advance state
  50-69 → RETRY  → re-delegate with issues
  < 50  → BLOCKED → escalate to user
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Validation Gates (block_on)

| Criterion | Threshold | Action |
|---|---|---|
| Test failures | > 3 | BLOCKED |
| Score drop | > 30 points | BLOCKED |
| Compile errors | > 1 | BLOCKED |
| Code-reviewer verdict | BLOCK | BLOCKED |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## DDD Gate (Doubt-Driven Development)

Integrated at 6 firing points:

1. Before planning → "What assumptions am I making?"
2. Before execution → "What could go wrong with this approach?"
3. Before commit → "What did I miss?"
4. Before review → "What would I criticize about my own code?"
5. After review → "Did the reviewer find what I expected?"
6. At BLOCKED → "What assumption was wrong?"

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## SDD Gate (Spec-Driven Development)

Mandatory gate between PLAN_SCORED → EXECUTE:

1. System-analyst produces a spec with Given/When/Then
2. Spec is scored (≥ 70 required)
3. Developer implements FROM the spec
4. Tests validate the spec

Exempted for: trivial bug fixes, config-only changes, documentation.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Ponytail Gate (Frugality Ladder)

Integrated at 2 firing points:

1. **Before any code decision** (EXECUTE phase) — Run the 6-rung frugality ladder:

   ```
   1. Does this need to exist?       → skip it (YAGNI)
   2. Standard library does it?      → use it
   3. Native platform feature?       → use it
   4. Already-installed dependency?  → use it
   5. Can this be one line?          → one line
   6. Only then: minimum code that works
   ```

2. **During REVIEW** — quality-analyst runs the Over-Engineering Check:
   - Is every abstraction justified? Any YAGNI violations?
   - Could stdlib or existing deps replace any custom code?
   - Any unnecessary indirection (factories, interfaces with one impl, over-abstracted patterns)?
   - Are there `ponytail:` debt comments? If so, are ceilings and upgrade paths documented?
   - Could any file be eliminated entirely?
   - Are any new dependencies avoidable?

### Ponytail Scoring Impact

The scoring pipeline includes a SIMPLICITY_001 rule (HIGH severity) that detects unnecessary abstractions, unused deps, and over-engineered patterns. An `over_engineering_deduction: 15` applies in Tier 1 scoring when YAGNI violations are detected.

### Ponytail Debt Convention

Intentional shortcuts are marked with `ponytail:` comments documenting the ceiling and upgrade path:
```java
// ponytail: global lock, wont scale past 10 concurrent. Upgrade: ConcurrentHashMap + stripe locks
```

See `usage/ponytail.md` for full reference, or `agent.md §5` for the 6-rung ladder in context.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## GitNexus Execution Flows

GitNexus indexes the codebase as a knowledge graph. Current index stats:

| Metric | Value |
|--------|-------|
| Symbols indexed | 1501 |
| Relationships | 1493 |
| Execution flows (processes) | 0 |

> **0 execution flows**: GitNexus auto-detects execution flows when entry points are annotated. Currently no flows are registered. All orchestration paths (INIT→PLAN→PLAN_SCORED→EXECUTE→EXECUTE_SCORED→REVIEW→REVIEW_SCORED→COMPLETE) are identified in this document but not yet mapped as GitNexus processes.

### Future Work

Add GitNexus execution flow annotations to key orchestration paths:
- **Orchestration lifecycle flow**: INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE
- **Scoring pipeline flow**: Delegation → Tier 1 rules → Tier 2 LLM judge → Tier 3 combined verdict → state transition
- **Escalation flow**: BLOCKED → persist → user intervention → resume with retry guidance

When flows are annotated, use `gitnexus_query({query: "orchestration flow"})` to retrieve the full step-by-step trace, or read `gitnexus://repo/workflow-state-engine/process/{name}` for a specific flow.

See `.opencode/skills/gitnexus/` for GitNexus usage guides.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Audit-Observability

Reference: `skills/audit-observability/SKILL.md`

The audit-observability skill monitors and audits the orchestration system across three pillars:

### 1. State Contract Transitions

Tracks every envelope state change: `INIT → PLAN → PLAN_SCORED → ... → COMPLETE` or `BLOCKED`. Records:
- Transition timestamps and duration
- Score at transition time
- Which agent triggered the transition
- Escalation events and retry count

Useful for detecting stalled workflows, infinite retry loops, or unexpected state regressions.

### 2. Score Analytics

Aggregates scoring pipeline results over time:
- Tier 1 (rule-based) subtotals per phase
- Tier 2 (LLM-as-judge) scores and rationales
- Combined verdict distribution (PASS / RETRY / BLOCKED)
- Score trends — are scores improving, degrading, or oscillating?
- Blast radius penalty frequency

### 3. Cross-Service/Component Consistency Enforcement

Validates that all services, agents, and components adhere to the shared contract:
- Envelope schema compliance across all agents
- Uniform scoring criteria application
- Consistent state machine rule interpretation
- Contract field naming and type consistency

Load the skill on demand: `skill({name: "audit-observability"})`.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Governance

Reference: `agents/_governance.md`

The shared governance document (`agents/_governance.md`) defines the rules, constraints, and conventions that ALL agents must follow. It is the single source of truth for:

- **Permission boundaries** — what each agent role may and may not do
- **Communication rules** — token efficiency, trade-off transparency, admission of unknowns
- **Escalation rules** — when to escalate to the orchestrator or user
- **Quality gates** — minimum scoring thresholds, validation criteria
- **Safety constraints** — never push to main, never force push, never edit without impact analysis

Agents **source their governance rules** from this file. The orchestrator (tech-lead) enforces governance compliance during scoring via the governance portion of the Tier 2 LLM-as-Judge evaluation (0-30 points).

> **Implementation note**: When adding a new agent, add a governance section to `agents/_governance.md` with the agent-specific rules, then reference it in the agent's instruction file.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## JSON Schema

Reference: `contract/contract.schema.json`

The envelope (`contract/contract.json`) has a canonical JSON Schema at `contract/contract.schema.json`. This schema:

- Defines the required structure for all envelope fields (state, scope, decisions, scoring, retry, metrics)
- Specifies valid state values and transitions
- Enforces type constraints (string, number, array, object)
- Documents field descriptions and optional/required status

### Validation

The script `scripts/check-conventions.sh` validates the envelope against this schema:

```bash
scripts/check-conventions.sh validate-contract
```

This check runs automatically in CI. A schema validation failure causes a Tier 1 scoring deduction of 15 points.

All agents should validate their envelope mutations against the schema before persisting. The orchestrator enforces schema compliance at every transition.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Conventions Checking

Two scripts maintain code quality and architecture conventions. Both are integrated into CI.

### 1. `scripts/check-conventions.sh`

Validates project-wide conventions including:
- JSON Schema compliance of `contract/contract.json`
- File and directory structure conventions
- Naming patterns and project layout rules
- Scoring pipeline configuration consistency

```bash
scripts/check-conventions.sh
```

### 2. `scripts/scan-ponytail-debt.sh`

Scans the codebase for `ponytail:` debt comments and generates a technical debt report. For each shortcut found, it reports:
- File and line number
- Ceiling (what limit the shortcut imposes)
- Upgrade path (how to fix it properly)

```bash
scripts/scan-ponytail-debt.sh
```

This feeds into the SIMPLICITY_001 scoring rule — unresolved ponytail debt with no documented upgrade path may trigger an `over_engineering_deduction` in Tier 1 scoring.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Workflow Lifecycle

```
1. INIT        → Create envelope, set state=INIT
2. PLAN        → Delegate to @system-analyst for architecture + plan
3. PLAN_SCORED → Score plan. If PASS → continue. If RETRY → fix plan.
4. EXECUTE     → Delegate to @developer. SDD gate enforces spec-first.
5. EXECUTE_SCORED → Score implementation. If PASS → continue.
6. REVIEW      → Delegate to @quality-analyst for code review
7. REVIEW_SCORED → Score review. If PASS → complete. If FLAG → fix.
8. COMPLETE    → Ship, persist lessons, save session.
```

### On BLOCKED — Escalation & Resume

When state becomes BLOCKED:

1. **Immediate stop** — Do NOT continue execution. All agents must halt.
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
   Then write to lean-ctx.
3. **Escalate to user** — Summarize blockers: `"I hit BLOCKED at ${phase}. Issues: ${issues}. Please review."`
4. **Wait for user response** — No polling loop. The orchestrator waits for user input to decide: adjust threshold, fix guidance, or discard.
5. **Resume from INIT** — User response triggers `BLOCKED→INIT` transition. Orchestrator creates fresh envelope for the retry. Previous `retry.issues[]` preserved for context.
6. **Max 3 retries** — If the same phase blocks 3 times (checked via `retry.attempt`), permanent BLOCKED. User must explicitly override.

> **Timeout guard**: If scoring pipeline exceeds `scoring.timeout_ms` (default: 30s), treat as scoring failure and set state=BLOCKED with issue 'scoring_timeout'.

1. Run scoring pipeline
2. Update envelope state
3. Persist to lean-ctx
4. Update STATE.md
5. Save session

---

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Toolkit Integration Map

How every piece of the toolkit connects in the workflow:

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

### Folder → Workflow Mapping

```

```text
├── agent.md                → Instructions[0] — loaded by EVERY agent at session start
├── agents/                 → Agent definitions loaded by opencode.json
├── skills/                 → Loaded on-demand via skill({name: "skill-name"})
├── usage/                  → Loaded on-demand when agent encounters an unfamiliar tool
├── template/               → contract.json loaded at INIT phase
│   └── contract.json       → Shared envelope, persisted via lean-ctx ctx_knowledge
├── rules/                  → rules.json — state machine transitions + scoring thresholds
├── config/                 → Plugin config files referenced by opencode.json
└── doc/                    → Planning/reporting documents (never loaded automatically)
```

### Tool Selection by Phase

| Phase | Agent | Primary Tools | Skills Loaded |
|---|---|---|---|
| INIT → PLAN | tech-lead → system-analyst | gitnexus_impact, gitnexus_query, context, graphify | `brainstorming`, `writing-plans`, `doubt-driven-development` |
| PLAN_SCORED | tech-lead | lean-ctx (scoring), lean-ctx (persist) | `spec-driven-development` (SDD gate) |
| EXECUTE | developer | lean-ctx (read/edit), gitnexus (impact) | `java-developer`, `test-driven-development`, **`simplify` (ponytail)** |
| EXECUTE_SCORED | tech-lead | lean-ctx (scoring) | `doubt-driven-development` (DDD gate), **over-engineering check** |
| REVIEW | quality-analyst | lean-ctx (read), gitnexus (impact), postgres (DB) | `code-review-and-quality`, `qa-expert`, `security-expert`, **OE check** |
| REVIEW_SCORED | tech-lead | lean-ctx (scoring + persist) | `verification-before-completion` |
| COMPLETE | quality-analyst-learner | lean-ctx (knowledge), gitnexus (detect) | `verification-before-completion` |

### Data Flow

```
1. User request
       │
2. tech-lead creates contract envelope
       │  (contract/contract.json → lean-ctx knowledge)
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
7. Subagent returns result
       │
8. tech-lead scores → updates envelope → persists → delegates next agent
       │
9. Loop: PLAN → EXECUTE → REVIEW → COMPLETE (or BLOCKED → retry)
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Post-Flight Protocol (Before Commit)

| # | Step | Tool |
|---|------|------|
| 1 | Impact verify | `gitnexus_impact` |
| 2 | Change detect | `gitnexus_detect_changes` |
| 3 | Knowledge persist | `lean-ctx ctx_knowledge remember` |
| 4 | Graphify sync | `lean-ctx ctx_shell --command "bash scripts/gitnexus-analyze.sh"` |
| 5 | STATE.md | `ctx_edit` to update Current Focus and Completed |
| 6 | Session save | `ctx_session save` |

Exceptions: docs-only changes skip 1, 2, 4. Config-only skip 1, 2.

### Cross-Reference Table

| Concept | Definition | Configured In | Loaded By |
|---|---|---|---|
| Envelope | Shared session state | `contract/contract.json` | lean-ctx knowledge recall |
| State machine | Legal transitions | `rules/rules.json` | tech-lead (enforced in prompt) |
| Scoring | PASS/RETRY/BLOCKED | `rules/rules.json` | tech-lead (scoring pipeline) |
| Agents | Role definitions | `opencode.json` + `agents/*.md` | OpenCode at startup |
| Skills | Extensible behaviors | `skills/*/SKILL.md` | On-demand via skill() tool |
| Tools | MCP capabilities | `opencode.json` mcp section | OpenCode MCP client |
| Usage guides | How-to references | `usage/*.md` | On-demand via read/lean-ctx |
| Ponytail | Frugality ladder + debt convention | `usage/ponytail.md`, `agent.md §5`, `skills/simplify/SKILL.md` | On-demand via skill() or plugin injection |

---

## Session Lifecycle (Contract Archival)

Every orchestration session persists its contract state to the `session/` directory for cross-session traceability and resumption.

### Directory Layout

```
contract/                    ← Active contract (mutable, current state)
  contract.json
  contract.schema.json
  state.md
  superpowers-contract.json

session/                     ← Historical archive (append-only state log + per-branch snapshots)
  state.md                   ← Append-only log of ALL state transitions
  index.md                   ← Master branch index (one row per branch)
  {branch-name}/             ← Per-branch snapshot for resumption
    contract.json
    contract.schema.json
    state.md
    superpowers-contract.json
```

### Lifecycle Protocol

| Event | Action |
|-------|--------|
| **Session start** | Read git branch → check `session/{branch}/` exists → if yes, resume from there; if no, init fresh from `contract/` template |
| **State transition** | Update `contract/contract.json` → snapshot to `session/{branch}/` via `scripts/snapshot-contract.sh` |
| **Session end** (COMPLETE/BLOCKED) | Run final snapshot → append to `session/state.md` → update `session/index.md` |
| **Branch switch** | Snapshot old branch → checkout new → load `session/NEW/` if exists |

### Snapshot Command

```bash
# Full snapshot (copies contract files + updates state.md + index.md)
bash scripts/snapshot-contract.sh --summary "State: ${STATE} — brief description"

# Files-only (skip index updates for hot-reload scenarios)
bash scripts/snapshot-contract.sh --snapshot-only

# Preview without writing
bash scripts/snapshot-contract.sh --dry-run --verbose
```

### Verification

```bash
# Validate session/ structure
ls -la session/                                 # Should show state.md, index.md, and branch dirs
cat session/state.md                            # Should show chronological state log
cat session/index.md                            # Should show all branches with status

# Validate per-branch snapshot
ls session/{branch-name}/                       # Should show 4 contract files
diff contract/contract.json session/{branch}/contract/contract.json   # Should match (identical snapshot)
```

### Save Session Protocol

When the user says "save session" or a phase completes, save to **ALL** systems. This is the canonical 6-step protocol:

```bash
# 1. Persist orchestration envelope to lean-ctx knowledge
lean-ctx ctx_knowledge remember key orchestration-contract value "<JSON>"

# 2. Update contract/state.md — append completed work items

# 3. Archive snapshot to session/ (contract files + state log + index)
bash scripts/snapshot-contract.sh --snapshot-only

# 4. Save conversation context (survives OpenCode restart)
lean-ctx ctx_session save

# 5. Re-index GitNexus code intelligence
bash scripts/gitnexus-analyze.sh

# 6. Re-index Graphify knowledge graph (if graphify-out/ exists)
graphify --update 2>/dev/null || true
```

**One-shot alias**: `save session` = all 6 steps above. Always run the full protocol — partial saves lose audit trail, break resumption, or leave stale indexes. This is referenced from the Post-Flight Protocol in all agent instruction files.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

[workflow-shield]: https://img.shields.io/badge/Workflow-Orchestration-blue?style=for-the-badge
[workflow-url]: #
