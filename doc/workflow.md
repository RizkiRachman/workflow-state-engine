<!-- omit from toc -->

# Orchestration Contract & State Machine

> **Contract template**: `template/contract.json`
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
       │  (template/contract.json → lean-ctx knowledge)
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
| Envelope | Shared session state | `template/contract.json` | lean-ctx knowledge recall |
| State machine | Legal transitions | `rules/rules.json` | tech-lead (enforced in prompt) |
| Scoring | PASS/RETRY/BLOCKED | `rules/rules.json` | tech-lead (scoring pipeline) |
| Agents | Role definitions | `opencode.json` + `agents/*.md` | OpenCode at startup |
| Skills | Extensible behaviors | `skills/*/SKILL.md` | On-demand via skill() tool |
| Tools | MCP capabilities | `opencode.json` mcp section | OpenCode MCP client |
| Usage guides | How-to references | `usage/*.md` | On-demand via read/lean-ctx |
| Ponytail | Frugality ladder + debt convention | `usage/ponytail.md`, `agent.md §5`, `skills/simplify/SKILL.md` | On-demand via skill() or plugin injection |

<p align="right">(<a href="#readme-top">back to top</a>)</p>

[workflow-shield]: https://img.shields.io/badge/Workflow-Orchestration-blue?style=for-the-badge
[workflow-url]: #
