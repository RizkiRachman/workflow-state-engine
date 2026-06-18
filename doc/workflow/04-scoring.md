<!-- omit from toc -->

# Part D — Scoring & Governance

> See [doc/workflow/README.md](../workflow/README.md) for index.

This part defines how every delegation is scored across 3 tiers, what validation gates can block transitions, and the governance rules that constrain all agent behavior.

## D1. Scoring Pipeline

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

## D2. Validation Gates (block_on)

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

## D3. Governance

Reference: `agents/_governance.md`

The shared governance document defines rules all agents must follow:

- **Permission boundaries** — what each agent role may and may not do (e.g., read-only agents never write code)
- **Communication rules** — token efficiency, trade-off transparency, admission of unknowns
- **Escalation rules** — when to escalate to the orchestrator or user (BLOCKED state, confidence < 3/5, uncovered risk)
- **Quality gates** — minimum scoring thresholds (≥70), validation criteria per phase
- **Safety constraints** — never push to main/master, never force push, never edit without gitnexus_impact

Agents source their governance rules from this file at session start. The orchestrator enforces governance compliance during Tier 2 scoring (0-30 points). When adding a new agent, add a governance section to `agents/_governance.md` with agent-specific rules, then reference it in the agent's instruction file.

---

[workflow-shield]: https://img.shields.io/badge/Workflow-Orchestration-blue?style=for-the-badge
