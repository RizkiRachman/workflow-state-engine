# Workflow Architecture Gap Analysis — 2026-06-26

## Executive Summary

Analysis using graphify, gitnexus, state machine, and ponytail reveals **10 critical gaps** in workflow architecture. Documentation inconsistencies between `state-machine.ts`, `rules.json`, and workflow docs create ambiguity that breaks agent execution.

---

## Gap #1: State Machine Inconsistency (CRITICAL)

**Problem**: `tech-lead.md` §5.8 shows state machine **without PONYTAIL_CHECK**:
```
INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE
```

But `state-machine.ts` and `rules.json` include `PONYTAIL_CHECK`:
```
INIT → PLAN → PLAN_SCORED → PONYTAIL_CHECK → EXECUTE → ...
```

**Impact**: Tech-lead agent skips ponytail gate during orchestration.

**Fix**: Update `tech-lead.md` §5.8 to include PONYTAIL_CHECK state.

---

## Gap #2: Scoring Formula Contradiction (CRITICAL)

**Problem**: Two different formulas exist:

**04-scoring.md** (line 13):
> "If subtotal < 70 → skip Tier 2, use subtotal as combined"

**rules.json** (scoring.formulas.combined_formula):
> "(tier1_subtotal + tier2_judge.score) / 2"

**Impact**: Agents compute different scores depending on which doc they read.

**Fix**: Align both to use the average formula from rules.json (single source of truth).

---

## Gap #3: SDD Gate Bypass Not Documented (HIGH)

**Problem**: `state-machine.ts` defines bypass path:
```typescript
{ from: "PLAN_SCORED", to: "EXECUTE", gate: "sdd_triggered" }
```

But `01-fundamentals.md` and `README.md` don't document this bypass.

**Impact**: Agents don't know when SDD gate can be skipped.

**Fix**: Document bypass in `01-fundamentals.md` §A1 transition table.

---

## Gap #4: README.md Missing PONYTAIL_CHECK (MEDIUM)

**Problem**: `doc/workflow/README.md` shows:
```
PLAN_SCORED→EXECUTE
```

Should show:
```
PLAN_SCORED→PONYTAIL_CHECK→EXECUTE
```

**Impact**: Quick reference is incomplete.

**Fix**: Update README.md transition table.

---

## Gap #5: Ponytail Gate Firing Points Confusing (HIGH)

**Problem**: `02-lifecycle.md` says ponytail fires at:
- B1c: PLAN_SCORED → PONYTAIL_CHECK (correct)
- B1e: EXECUTE → EXECUTE_SCORED "before ANY code is written" (contradictory — code already written)
- B1g: REVIEW → REVIEW_SCORED (over-engineering check)

But state machine only has **one** PONYTAIL_CHECK state.

**Impact**: Agents confused about when ponytail gate actually runs.

**Fix**: Clarify that:
- PONYTAIL_CHECK state = pre-execution frugality gate
- "Ponytail fires at B1e" = Over-Engineering Check during scoring (different from state)
- "Ponytail fires at B1g" = Review includes over-engineering dimension

---

## Gap #6: Agent State Count Wrong (MEDIUM)

**Problem**: `03-agents.md` says tech-lead has access to "all 8" states.

Actual count:
- 9 forward states: INIT, PLAN, PLAN_SCORED, PONYTAIL_CHECK, EXECUTE, EXECUTE_SCORED, REVIEW, REVIEW_SCORED, COMPLETE
- + 1 escalation state: BLOCKED
- **Total: 10 states**

**Impact**: Documentation doesn't match implementation.

**Fix**: Update to "all 10 states" or list them explicitly.

---

## Gap #7: quality-analyst-learner Missing in Some Diagrams (LOW)

**Problem**: Some workflow diagrams don't show learner delegation at COMPLETE.

`02-lifecycle.md` §B1h shows:
> "Delegates to: @tech-lead (score review findings) + @quality-analyst-learner (post-exec analysis)"

But `01-fundamentals.md` §A3 table shows:
> REVIEW_SCORED→COMPLETE delegated to "quality-analyst-learner"

**Impact**: Minor inconsistency, but learner role unclear.

**Fix**: Standardize on "tech-lead scores, then delegates to quality-analyst-learner for lessons extraction".

---

## Gap #8: Confidence Journal vs Uncertainty Routing Scale Mismatch (MEDIUM)

**Problem**: 
- `rules.json` → `decisions.confidence_journal` uses **1-5 scale**
- `02-lifecycle.md` §B2b → uncertainty routing uses **0-100 scale**

No mapping documented between them.

**Impact**: Agents don't know how to convert confidence scores.

**Fix**: Add mapping table:
```
1 (Guess)      → 0-20
2 (Informed)   → 21-40
3 (Confident)  → 41-60
4 (Strong)     → 61-80
5 (Certain)    → 81-100
```

---

## Gap #9: Prototype Mode Not in state-machine.ts (MEDIUM)

**Problem**: `02-lifecycle.md` §B2a describes Prototype Mode that bypasses SDD and scoring.

But `state-machine.ts` has no prototype mode flag or bypass logic.

**Impact**: Prototype mode is documentation-only, not enforced in code.

**Fix**: Either:
1. Add prototype mode flag to `OrchestrationContext` in state-machine.ts, OR
2. Document that prototype mode is a convention, not enforced

---

## Gap #10: Post-Flight Protocol Step Numbering (LOW)

**Problem**: `05-operations.md` §E1 shows 9 steps (0-8), but step 6 has "6b" sub-step.

Should be:
- Steps 0-7 (8 steps total), OR
- Steps 0-8 with 6b as separate step 7

**Impact**: Minor confusion when referencing steps.

**Fix**: Renumber to 0-7 or 1-8 consistently.

---

## Simulation Test Results

### Test 1: Happy Path (INIT → COMPLETE)

**Expected**: 9 states traversed in order
**Actual**: 
- tech-lead.md skips PONYTAIL_CHECK → **FAIL**
- README.md skips PONYTAIL_CHECK → **FAIL**
- state-machine.ts correct → **PASS**

### Test 2: BLOCKED Escalation

**Expected**: Any state → BLOCKED on score < 50 or retry ≥ 3
**Actual**: 
- rules.json defines all escalation paths → **PASS**
- state-machine.ts implements escalation → **PASS**
- 02-lifecycle.md documents protocol → **PASS**

### Test 3: Scoring Pipeline

**Expected**: Tier 1 → Tier 2 → Combined verdict
**Actual**:
- rules.json formula: `(tier1 + tier2) / 2` → **PASS**
- 04-scoring.md formula: "skip Tier 2 if subtotal < 70" → **FAIL** (contradicts rules.json)

### Test 4: Agent State Access

**Expected**: Each agent has defined state access
**Actual**:
- 03-agents.md says "all 8 states" → **FAIL** (should be 10)
- rules.json agent_states mapping → **PASS**

---

## Recommendations

### Priority 1 (CRITICAL — Fix Immediately)
1. **Update tech-lead.md §5.8** to include PONYTAIL_CHECK state
2. **Align scoring formula** in 04-scoring.md with rules.json

### Priority 2 (HIGH — Fix This Week)
3. **Document SDD bypass** in 01-fundamentals.md
4. **Clarify ponytail gate firing points** in 02-lifecycle.md

### Priority 3 (MEDIUM — Fix This Sprint)
5. **Fix README.md** transition table
6. **Correct agent state count** in 03-agents.md
7. **Add confidence scale mapping** to 02-lifecycle.md
8. **Decide on prototype mode** enforcement

### Priority 4 (LOW — Backlog)
9. **Standardize quality-analyst-learner** delegation docs
10. **Renumber post-flight steps** in 05-operations.md

---

## Verification Checklist

After fixes, verify:
- [ ] `state-machine.ts` matches all documentation
- [ ] `rules.json` is single source of truth for thresholds
- [ ] All 10 states documented consistently
- [ ] Scoring formula consistent across all docs
- [ ] Agent state access counts correct
- [ ] Simulation test passes all 4 scenarios

---

## Files to Modify

1. `agents/tech-lead.md` — §5.8 state machine
2. `doc/workflow/04-scoring.md` — scoring formula
3. `doc/workflow/01-fundamentals.md` — SDD bypass, transition table
4. `doc/workflow/README.md` — quick reference table
5. `doc/workflow/02-lifecycle.md` — ponytail clarification, confidence mapping
6. `doc/workflow/03-agents.md` — state count
7. `doc/workflow/05-operations.md` — step numbering

---

**Analysis Date**: 2026-06-26  
**Analyst**: opencode (tech-lead orchestration)  
**Tools Used**: graphify, gitnexus, state-machine.ts, rules.json, workflow docs  
**Branch**: feature/20260626-workflow-architecture-gaps
