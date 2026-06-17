# Architecture Enforcement Audit — Backlog Gaps

**Generated:** 2026-06-18
**Source:** `feature/20260618-architecture-enforcement-audit`
**Status:** Not addressed in this session

---

## Gap 1: validate-toolkit.sh — 1 Persistent Failure

| Check | Expected | Actual | Status |
|---|---|---|---|
| `.opencode/orchestration` symlink | `../contract` | `../template` | **Pre-existing mismatch** |

**Context:** `setup.sh` creates `.opencode/orchestration → ../template`, but `validate-toolkit.sh` expects `../contract`. The `template/` directory doesn't exist at root level — it's `contract/`. The owner or orchestrator-template migration likely introduced this.

**Action:** Either rename `contract/` to `template/` or change validate-toolkit.sh to expect `../template`.

---

## Gap 2: 114 Ponytail Debt Items

| Tag | Count | Top Source |
|---|---|---|
| `ponytail:` | 40 | `agents/developer.md` (11) |
| `TODO` | 19 | `agents/system-analyst.md` (4) |
| `FIXME` | 12 | `doc/workflow.md` (4) — scoring pipeline edge cases |
| `HACK` | 11 | `agents/quality-analyst.md` (3) |
| `XXX` | 12 | Dispersed |
| `WORKAROUND` | 10 | `agents/developer.md` (5) |
| `TEMPORARY` | 10 | Dispersed |

**80% in agent instruction files** — unusual but expected for a doc-driven toolkit.

**Recommended first pass:** Clear all `FIXME` items in `doc/workflow.md` (scoring pipeline edge cases) and `agents/tech-lead.md` (contract migration).

---

## Gap 3: GitNexus — 0 Execution Flows

**Finding:** 1,622 symbols, 1,607 edges indexed but **zero execution flows**. The 8-state machine transitions (`INIT → PLAN → PLAN_SCORED → ...`) from `doc/workflow.md` are not mapped as GitNexus processes.

**Impact:** `impact()` and `query()` work on individual symbols, but cross-flow traceability is blind.

**Action:** Register each state machine transition as a GitNexus process with entry point (current state) and terminal (next state). See `doc/workflow.md` for authoritative transition table.

---

## Gap 4: Graphify Community Fragmentation

**Metric:** 254 communities for 2,525 nodes (31 thin communities excluded). Key communities have concerningly low cohesion:

| Community | Cohesion | Interpretation |
|---|---|---|
| Quality Gates Pipeline | 0.22 | Weak |
| Change Impact Analysis | 0.20 | Moderate |
| Architecture Governance | 0.18 | Weak |
| Verification Quality Gates | 0.15 | Weak |
| **Orchestration Workflow** | **0.05** | **Very weak** |

**Action:** Re-cluster with fewer communities or tag core orchestration concepts for tighter clustering.

---

## Gap 5: check-conventions.sh — 2 False Positives

| File | Flag | Why False Positive |
|---|---|---|
| `agents/system-analyst.md` | `src/main/java/` FQN | Inside template code block showing project structure example |
| `agents/tech-lead.md` | `push to main` | Inside scoring table description explaining what to check FOR |

**Action:** Add markdown code-block exclusion to `scripts/check-conventions.sh`, or suppress these two specific anchors.

---

## Gap 6: Ponytail Debt CI Integration

**Finding:** The CI pipeline runs `scan-ponytail-debt.sh` but only reports — no threshold or blocking mechanism.

**Action:** Add a configurable debt budget (e.g., block at 120 items) to `scan-ponytail-debt.sh` so debt doesn't grow unbounded.
