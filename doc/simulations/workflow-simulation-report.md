# Workflow Architecture Simulation Report

> **Date**: 2026-06-18
> **Branch**: `feature/20260618-workflow-simulation`
> **Scope**: 10 simulation scenarios testing the workflow state machine, contract envelope, scoring pipeline, agent delegation, and governance rules.

---

## Executive Summary

This report documents 10 simulated workflow scenarios that test the Workflow State Engine architecture for gaps, structural weaknesses, protocol violations, and contract inconsistencies. Each simulation walks through the state machine transitions, checks rule compliance, and identifies issues.

**Total gaps found: 18**
- **CRITICAL**: 5
- **HIGH**: 6
- **MEDIUM**: 4
- **LOW**: 3

---

## Simulation 1: Happy Path — Full INIT→COMPLETE Cycle

### Scenario
A simple, well-defined task (add a new REST endpoint) runs through the entire workflow without errors.

### State Machine Trace

```
INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE
```

### Step-by-Step

| Step | Agent | Action | Expected State |
|------|-------|--------|---------------|
| 1 | tech-lead | Create envelope, set state=INIT | INIT |
| 2 | tech-lead | Delegate to system-analyst | PLAN |
| 3 | system-analyst | Produce plan with files_affected, risks, edge cases | PLAN |
| 4 | tech-lead | Score plan (Tier 1 + Tier 2) ≥ 70 | PLAN_SCORED |
| 5 | tech-lead | SDD gate: if >3 files, run spec (skip for simple task) | PLAN_SCORED |
| 6 | tech-lead | Delegate to developer | EXECUTE |
| 7 | developer | Implement per plan, write tests | EXECUTE |
| 8 | tech-lead | Score implementation ≥ 70 | EXECUTE_SCORED |
| 9 | tech-lead | Delegate to quality-analyst | REVIEW |
| 10 | quality-analyst | Code review report with PASS verdict | REVIEW |
| 11 | tech-lead | Score review ≥ 70 | REVIEW_SCORED |
| 12 | tech-lead | Run verify loop (mvn test, conventions) | REVIEW_SCORED |
| 13 | tech-lead | Delegate to quality-analyst-learner | COMPLETE |
| 14 | learner | Extract lessons, persist knowledge | COMPLETE |

### Gaps Found

**GAP-1 [HIGH]**: `audit_log[]` field does not exist in `contract.template.json`
- The template (source of truth for new envelopes) has no `audit_log[]` field
- The schema defines `audit_log[]` as an array of `audit_entry` objects
- Rules rule AUDIT_001 deducts -15 if transition without audit entry
- **Impact**: Every state transition will be penalized because there's no field to append to
- **Fix**: Add `"audit_log": []` to the template

**GAP-2 [CRITICAL]**: Template field `current_phase` vs Schema required field `cur_phase`
- Template: `"retry": { "current_phase": "", ... }`
- Schema required: `["cur_phase", "attempt", "max_attempts", ...]`
- Field names don't match! Schema validation would fail.
- **Impact**: `check-conventions.sh validate-contract` will report schema violations on every envelope.
- **Fix**: Align field names — change schema to `current_phase` or template to `cur_phase`.

**GAP-3 [MEDIUM]**: DDD gate not triggered at PLAN_SCORED
- DDD gate has 6 firing points but none between PLAN→PLAN_SCORED
- Plan output goes directly to scoring without adversarial review
- **Impact**: Architecture flaws in the plan aren't caught until EXECUTE (costly rework)
- **Fix**: Add DDD gate between PLAN and PLAN_SCORED

**GAP-4 [MEDIUM]**: No build verification between EXECUTE_SCORED→REVIEW
- After EXECUTE_SCORED, the flow goes directly to REVIEW without running `mvn test`
- The Verify loop (step 5 in tech-lead.md) says to run tests, but it's after REVIEW, not before
- **Impact**: Broken compilation or test failures go to the reviewer, wasting review effort
- **Fix**: Add verification step between EXECUTE_SCORED and REVIEW delegation

**GAP-5 [LOW]**: No pre-flight validation for orchestrator's own steps
- Pre-flight gates exist for subagents (system-analyst, developer, quality-analyst)
- But the orchestrator (tech-lead) has no automated validation that it performed pre-flight before delegating
- **Impact**: If orchestrator forgets to load envelope, no guard catches it
- **Fix**: Add orchestrator pre-flight checklist with automated validation

---

## Simulation 2: BLOCKED at Scoring — Poor Agent Output

### Scenario
System-analyst returns an incomplete plan with no edge case analysis. Scoring pipeline blocks advancement.

### State Machine Trace

```
INIT → PLAN → PLAN_SCORED (score = 45) → BLOCKED
```

### Step-by-Step

| Step | Action | Expected | Actual |
|------|--------|----------|--------|
| 1 | tech-lead delegates to system-analyst | INIT→PLAN | ✅ |
| 2 | system-analyst returns plan | PLAN | ✅ |
| 3 | Tier 1 scoring: missing edge cases (-15), no required output fields (-15) | subtotal=70 | subtotal=70 |
| 4 | Tier 2 judge: requirements 20/40, gov 15/30, completeness 8/20, edge 2/10 | score≥70 | score=45 |
| 5 | Combined verdict: 45 < 50 | PASS | **BLOCKED** |

### Gaps Found

**GAP-6 [HIGH]**: Tier 1 scoring deductions not triggered by actual content quality
- Tier 1 checks format/schema but NOT content quality
- An empty plan with correct JSON structure passes Tier 1 (subtotal=100)
- Only Tier 2 catches empty content
- **Impact**: Wastes Tier 2 LLM-as-judge call on obviously poor output
- **Fix**: Add "output has meaningful content" check to Tier 1 (simple word/line count threshold)

**GAP-7 [MEDIUM]**: No partial credit path for BLOCKED tasks
- When state=BLOCKED, all partial outputs are lost
- There's no mechanism to salvage useful work (e.g., partial plan, partial code)
- **Impact**: Rework cost is 100% — no incremental progress possible
- **Fix**: Add `outputs.partial_work` field to preserve salvageable output from BLOCKED phases

---

## Simulation 3: Forbidden Transition — EXECUTE Without PLAN_SCORED

### Scenario
An orchestrator (or rogue agent) tries to skip directly from PLAN to EXECUTE, bypassing PLAN_SCORED scoring and SDD gate.

### State Machine Trace

```
INIT → PLAN → EXECUTE (ILLEGAL — blocked)
```

### Detection Mechanism

| Check | Rule | Result |
|-------|------|--------|
| State validation | `rules.json` agent_states: developer=["EXECUTE","EXECUTE_SCORED"] | ✅ Developer validates state |
| Pre-flight gate | system-analyst checks state is INIT/PLAN/PLAN_SCORED | ✅ |
| Orchestrator transition check | "Before each delegation: validate transition is legal" | ✅ |
| Schema enum validation | State enum permits only valid transitions | ❌ **MISSING** |

### Gaps Found

**GAP-8 [CRITICAL]**: No schema-level state machine transition validation
- The JSON schema validates that `state` is one of the enum values
- But it does NOT validate that transitions follow the state machine rules
- A rogue agent could set `state: "EXECUTE"` directly from `INIT` and the schema would accept it
- The only enforcement is in the orchestrator's instructions (human-readable, not machine-enforceable)
- **Impact**: No compile-time/load-time validation of transition legality
- **Fix**: Add JSON Schema `if/then` conditional validation for transition rules, or add a server-side transition validation function

**GAP-9 [HIGH]**: No write-access control on envelope fields per agent
- All agents have write access to the envelope via `lean-ctx ctx_knowledge remember`
- A subagent could (accidentally or maliciously) change the state field
- The only guard is "trust the agent to follow instructions"
- **Impact**: No defense-in-depth for envelope integrity
- **Fix**: Add field-level access control — agents should only write to their allowed sections (system-analyst → `outputs.plan`, developer → `outputs.code_changes`, etc.)

---

## Simulation 4: Retry Loop Exhaustion — 3 Failed Attempts

### Scenario
Developer keeps failing scoring with scores between 50-69. After 3 retries, state becomes BLOCKED.

### State Machine Trace

```
EXECUTE → EXECUTE_SCORED (score=55) → RETRY → EXECUTE (attempt 2)
        → EXECUTE_SCORED (score=52) → RETRY → EXECUTE (attempt 3)
        → EXECUTE_SCORED (score=48) → BLOCKED
```

### Gaps Found

**GAP-10 [CRITICAL]**: `max_attempts` field missing from `contract.template.json`
- The schema has `retry.max_attempts` as a required integer
- The template doesn't include it — neither does the schema default
- When creating a new envelope from template, `max_attempts` is undefined
- **Impact**: The retry loop doesn't know when to stop. Rules say "max 3 attempts" but the contract has no field to track it.
- **Fix**: Add `"max_attempts": 3` and `"score_threshold": 70` and `"escalation_threshold": 50` to the template

**GAP-11 [MEDIUM]**: No escalating feedback between retries
- When retrying, `retry.issues[]` is populated with current issues
- But there's no mechanism to detect if the same issue recurs across retries
- If the developer fails for the same reason on attempt 2 and 3, there's no early cutoff
- **Impact**: Wastes 1-2 retry cycles on the same unfixable issue
- **Fix**: Add `retry.recurring_issues[]` to detect repeated failures and escalate faster

---

## Simulation 5: Parallel Conflict — Two Agents Modifying Same File

### Scenario
A task spans two services that share a common utility file. The orchestrator parallelizes incorrectly.

### State Machine Trace

```
PLAN_SCORED → scope.parallel_eligible = true → max_parallel_agents = 2
→ Developer A (shard 1) modifies service-a/UserService.java + common/Util.java
→ Developer B (shard 2) modifies service-b/OrderService.java + common/Util.java
→ CONFLICT detected on common/Util.java
```

### Gaps Found

**GAP-12 [HIGH]**: No automated conflict detection mechanism in the framework
- The rules describe conflict detection (PARALLEL_001) and reconciliation steps
- But there's no tool or script that actually detects file-level conflicts across parallel agents
- The "check git diff --name-only" approach is fragile — agents run in isolated contexts
- **Impact**: Silent overwrites possible if conflict detection fails
- **Fix**: Add a `scripts/detect-parallel-conflicts.sh` that checks for file overlaps before parallel dispatch

**GAP-13 [LOW]**: No parallel shard ID tracking in envelope
- Each parallel agent gets `scope.included` slice but no unique shard ID
- Output reconciliation is manual — no automated merge mechanism
- **Impact**: Hard to track which output belongs to which shard
- **Fix**: Add `scope.shard_id` field and `scope.total_shards` to each parallel delegation

---

## Simulation 6: Contract Corruption — Invalid State / Missing Fields

### Scenario
A partially persisted envelope becomes corrupted (network issue during `lean-ctx ctx_knowledge remember`), resulting in invalid state or missing fields.

### State Machine Trace

```
INIT → PLAN → [network blip] → corrupt envelope loaded → BLOCKED
```

### Corruptions Tested

| Corruption | Detection | Recovery |
|-----------|-----------|----------|
| Missing `state` field | ❌ No pre-load validation | ❌ None |
| Invalid state enum value | ✅ Schema validation | ❌ Manual fix |
| NaN score value | ❌ No type validation at load | ❌ None |
| Half-written `requirements` | ❌ No atomicity guarantee | ❌ None |

### Gaps Found

**GAP-14 [CRITICAL]**: No envelope integrity validation on load
- The envelope is loaded via `lean-ctx ctx_knowledge recall` which returns whatever was stored
- There's no check that the loaded JSON is valid against the schema before use
- A corrupt envelope loads silently — the agent operates on garbage data
- **Impact**: Catastrophic failure cascade — bad plan from bad requirements, bad code from bad plan
- **Fix**: Add a `scripts/validate-contract.sh` that validates envelope against schema. Call it on every load.

**GAP-15 [HIGH]**: No atomic persistence for envelope updates
- `lean-ctx ctx_knowledge remember` is a single-shot write
- If the process crashes between envelope read and write, partial state is lost
- No write-ahead log, no transaction, no rollback
- **Impact**: Envelope can be in inconsistent state permanently
- **Fix**: Implement checkpointing — save to local file before writing to knowledge, recover from checkpoint on next load

---

## Simulation 7: Audit Trail Failure — Transition Without Audit Entry

### Scenario
A state transition completes but no audit entry is appended to the envelope. The orchestrator doesn't notice.

### State Machine Trace

```
INIT → PLAN (no audit entry) → PLAN_SCORED (no audit entry)
```

### Gaps Found

**GAP-1 (revisited)**: `audit_log[]` missing from template — this IS the root cause
- Even if the orchestrator wanted to append audit entries, the field doesn't exist
- The rules deduct -15 for missing audit entries, but the framework doesn't provide the storage

**GAP-16 [LOW]**: No audit entry rollup mechanism
- For tasks with many state transitions (e.g., 3 retries = 6+ transitions), the audit_log grows unbounded
- The audit-observability skill mentions trimming to 500 entries, but there's no automated archival
- **Impact**: Bloating the envelope with audit entries over time
- **Fix**: Add automatic audit_log archival at configurable thresholds (100/500/1000 entries)

---

## Simulation 8: SDD Gate Skip — Complex Task Skips Spec

### Scenario
A task modifying 5+ files with cross-service impact skips the SDD gate and goes directly from PLAN_SCORED to EXECUTE.

### State Machine Trace

```
PLAN_SCORED (score=85) → [SDD gate skipped] → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → need rework
```

### Gaps Found

**GAP-17 [HIGH]**: No machine-enforceable SDD gate trigger
- The SDD gate is supposed to trigger when "task touches >3 files, cross-service, or >30 min"
- These are advisory thresholds — no code enforces them
- The orchestrator's discretion alone decides whether to run spec
- **Impact**: Complex tasks can skip spec gate, causing rework in REVIEW
- **Fix**: Add automatic scope-check: before PLAN_SCORED→EXECUTE, check `scope.included.length > 3`. If yes, require spec approval.

---

## Simulation 9: Token Budget Exhaustion

### Scenario
During a massive task with 3 parallel agents, the session token budget is exceeded.

### State Machine Trace

```
INIT → PLAN → PLAN_SCORED → EXECUTE (parallel: 3 agents, heavy context) → [TOKEN BUDGET EXCEEDED]
```

### Gaps Found

**GAP-18 [CRITICAL]**: Token budget section completely missing from `contract.template.json`
- The schema defines a full `token_budget` section:
  - `max_per_session`, `warning_threshold`, `hard_limit`, `max_per_phase`
  - `max_per_subagent_call`, `current_session_usage`, `phase_usage`
- The template has NONE of these fields
- **Impact**: Token budget enforcement is advisory only — no field to track or check against
- **Fix**: Add full `token_budget` section to the template with reasonable defaults

---

## Simulation 10: Score Regression Between Audit Entries

### Scenario
The score drops more than 20 points between adjacent audit entries in the same phase (e.g., from 85 to 55).

### State Machine Trace

```
PLAN_SCORED (score=85) → EXECUTE → EXECUTE_SCORED (score=55) → REVIEW
→ Audit entry 1: combined=85 → Audit entry 2: combined=55 → drop=-30 > 20
```

### Rule Check

| Rule | Trigger | Action |
|------|---------|--------|
| AUDIT_003 | Score drop >20pts between adjacent entries | Deduct -15 from score |

### Gaps Found

- This is the **only gap type that IS properly handled** — AUDIT_003 exists in rules.json
- However, it depends on `audit_log[]` existing (GAP-1) and audit entries being appended (GAP-14)
- **Impact**: Until GAP-1 and GAP-14 are fixed, AUDIT_003 is non-functional

---

## Consolidated Findings

### CRITICAL (5)

| ID | Finding | File(s) | Fix |
|----|---------|---------|-----|
| GAP-1 | `audit_log[]` missing from template | `contract.template.json` | Add `"audit_log": []` |
| GAP-2 | `cur_phase` vs `current_phase` mismatch | `contract.schema.json`, `contract.template.json` | Align field names |
| GAP-8 | No schema-level state transition validation | `contract.schema.json` | Add `if/then` transition rules |
| GAP-10 | `max_attempts` and thresholds missing from template | `contract.template.json` | Add retry config fields |
| GAP-18 | `token_budget` section missing from template | `contract.template.json` | Add full token_budget section |

### HIGH (6)

| ID | Finding | File(s) | Fix |
|----|---------|---------|-----|
| GAP-6 | Tier 1 doesn't check output content quality | `rules.json` scoring | Add content-meaningfulness check |
| GAP-9 | No field-level write access control on envelope | Agent instruction files | Add per-agent field permissions |
| GAP-12 | No parallel conflict detection tool | Framework | Add conflict detection script |
| GAP-14 | No envelope integrity validation on load | All agents | Add validate-contract.sh call |
| GAP-15 | No atomic persistence for envelope writes | Framework | Add checkpointing mechanism |
| GAP-17 | SDD gate not machine-enforceable | `tech-lead.md` | Add automatic scope trigger |

### MEDIUM (4)

| ID | Finding | File(s) | Fix |
|----|---------|---------|-----|
| GAP-3 | DDD gate not triggered at PLAN_SCORED | `doc/workflow.md` | Add DDD firing point |
| GAP-4 | No build verification before REVIEW delegation | `tech-lead.md` | Add test step before REVIEW |
| GAP-7 | No partial credit for BLOCKED tasks | `contract.template.json` | Add `outputs.partial_work` |
| GAP-11 | Recurring retry issues not tracked | Framework | Add `retry.recurring_issues[]` |

### LOW (3)

| ID | Finding | File(s) | Fix |
|----|---------|---------|-----|
| GAP-5 | No orchestrator pre-flight validation | `tech-lead.md` | Add orchestrator checklist |
| GAP-13 | No parallel shard ID tracking | Framework | Add `scope.shard_id` |
| GAP-16 | No audit log trim mechanism | Framework | Add auto-archival |

---

## Proposed Solutions Summary

### Immediate Fixes (can be done in minutes)

1. **Update `contract.template.json`**:
   - Add `"audit_log": []`
   - Add `"max_attempts": 3`, `"score_threshold": 70`, `"escalation_threshold": 50`
   - Add `"token_budget": { ... }` with defaults
   - Add `"outputs.partial_work": {}`
   - Rename schema `cur_phase` → `current_phase` to match template

2. **Update `contract.schema.json`**:
   - Fix `retry.cur_phase` → `retry.current_phase`
   - Add `if/then` conditional transitions validation

### Short-Term Fixes (1-2 hours)

3. **Create `scripts/validate-contract.sh`** that validates loaded envelope against schema
4. **Create `scripts/detect-parallel-conflicts.sh`** for pre-dispatch file overlap check
5. **Add Tier 1 check for output content meaningfulness** (word count, required sections)
6. **Add DDD firing point at PLAN_SCORED** in workflow.md and tech-lead.md

### Architectural Changes (2-4 hours)

7. **Add field-level write permissions** to envelope — agents can only write to their sections
8. **Add checkpointing mechanism** for atomic envelope persistence
9. **Add auto-scope SDD trigger** that checks `scope.included.length` before PLAN_SCORED→EXECUTE
10. **Add `scope.shard_id` field** for parallel agent tracking

---

## Appendix A: Field Name Inconsistency Map

| Location | Field Name | Status |
|----------|-----------|--------|
| `contract.template.json` | `retry.current_phase` | ✅ Current |
| `contract.schema.json` required[] | `retry.cur_phase` | ❌ Wrong |
| `tech-lead.md` | `retry.current_phase` | ✅ Current |
| `SKILL.md` (orchestration-template) | `retry.current_phase` | ✅ Current |

## Appendix B: Template vs Schema Completeness

| Section | Template | Schema | Status |
|---------|----------|--------|--------|
| `state` | ✅ | ✅ | OK |
| `version` | ❌ | ✅ | **MISSING** |
| `state_machine_version` | ❌ | ✅ | **MISSING** |
| `session` | ✅ (partial) | ✅ | Missing `archived_at` |
| `scope` | ✅ (partial) | ✅ | Missing `boundary`, `max_parallel_agents` |
| `requirements` | ✅ (minimal) | ✅ | OK for minimal |
| `decisions` | ✅ (empty {}) | ✅ | Missing `approved_architecture`, `rejected_approaches`, `adr_log` |
| `governance` | ✅ (minimal) | ✅ | Missing many fields |
| `outputs` | ✅ (empty {}) | ✅ | Missing structured fields |
| `score` | ✅ | ✅ | OK |
| `retry` | ✅ (partial) | ✅ | Missing `max_attempts`, `score_threshold`, `escalation_threshold`, `phase_issues`, `escalation_trace` |
| `metrics` | ✅ (partial) | ✅ | Missing `phase_durations` |
| `token_budget` | ❌ | ✅ | **MISSING entirely** |
| `validation` | ✅ (minimal) | ✅ | Missing `rule_overrides` |
| `audit_log` | ❌ | ✅ | **MISSING entirely** |
| `lessons_learned` | ✅ | ✅ | OK |
