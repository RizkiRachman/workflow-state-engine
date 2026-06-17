---
name: orchestration-template
description: MANDATORY on EVERY task start — not just session start. Forces the orchestrator to load the shared orchestration envelope from lean-ctx BEFORE any work begins. If envelope exists → resume state. If not → ask user confirmation, then create fresh. Also use when user says "use orchestration template", "follow template", "resume", "continue", "check state". ALWAYS enforce this skill at the beginning of every task.
---

# Orchestration Template — Session Protocol

## When to load

Load this skill **first thing on every session start** and whenever the user says:

- "use orchestration template" / "follow template"

- "resume" / "continue our focus" / "check state"

- "orchestrate this" / "use the workflow"

## Protocol

### Step 1: Load the Envelope

```bash
lean-ctx ctx_knowledge recall --query "orchestration-contract"

```
### Step 2: Decision Gate

**If envelope FOUND:**

```text
→ Read state, session, decisions, governance, score, retry

→ Identify: current_phase, attempt, issues[]

→ Inform user: "Resuming at {state} (phase: {retry.current_phase}). Issues: {retry.issues}"

→ Load STATE.md → identify Current Focus

→ Continue from where the envelope left off

```
**If envelope NOT FOUND:**

```text
→ Ask user: "No orchestration session found. Use orchestration template? [Y/n]"

If YES:

  1. Read `.opencode/orchestration/contract.json`

  2. Populate: session.task_id, session.branch, session.created_at

  3. Persist via: lean-ctx ctx_knowledge remember key orchestration-contract value <JSON>

  4. Sync STATE.md: set Current Focus = "New orchestration session: {task_id}"

  5. Proceed with the workflow

If NO:

  → Skip orchestration. Work without the envelope.

  → Note: state, decisions, and retry will NOT be tracked.

```
### Step 3: Persist (on every transition)

After ANY delegation or phase change:

```bash
1. Update envelope: state, outputs, score, retry, metrics

2. lean-ctx ctx_knowledge remember key orchestration-contract value <updated JSON>

3. Sync STATE.md: Current Focus + Known Blockers

4. ctx_session save — survive opencode restart

```
### Step 4: Session Resume Detection

When resuming (envelope found with COMPLETE state):

```text
1. Read state + retry.current_phase + retry.issues

2. Update STATE.md Current Focus with "Resuming at {state} (phase: {retry.current_phase}). Issues: {retry.issues}"

3. Summarize to user: what was done, what's pending, any blockers

4. If blocked → ask user for guidance before continuing

```
---

## State Machine

```text
INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE

                                                                                       ↘

BLOCKED (any phase) → user intervention → retry with guidance → back to failed phase

```
### Transition Rules

- `PLAN_SCORED → EXECUTE` — only if `score.combined ≥ 70`

- `EXECUTE_SCORED → REVIEW` — only if `score.combined ≥ 70`

- Any phase → `BLOCKED` — if `score.combined < 50` OR `retry.attempt ≥ 3`

### Block-On Criteria (validation.block_on)

- Test failures > 3 → BLOCKED

- Score drop > 30 points → BLOCKED

- Compile errors > 1 → BLOCKED

- code-reviewer verdict = BLOCK → BLOCKED

---

## Quick Reference

```bash
Session start:

  lean-ctx ctx_knowledge recall --query "orchestration-contract"

  if found → resume

  if not → ask user → create fresh

After each phase:

  lean-ctx ctx_knowledge remember \

    category architecture \

    key orchestration-contract \

    value "<updated JSON>"

  ctx_session save

  sync STATE.md

```
