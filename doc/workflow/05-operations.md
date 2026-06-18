<!-- omit from toc -->

# Part E — Operations & Reference

> See [doc/workflow/README.md](../workflow/README.md) for index.

This part covers operational procedures (post-flight protocol, session lifecycle), tooling (audit observability, conventions scripts), and reference material (GitNexus flows, JSON Schema).

## E1. Post-Flight Protocol

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
| 7 | Re-index Graphify | `graphify --update 2>/dev/null || true` | Docs-only skip |

### Pre-Flight Protocol (Session Start)

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

## E2. Session Lifecycle

Every orchestration session persists its contract state to the `session/` directory for cross-session traceability and safe resumption.

### Directory Layout

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

### Lifecycle Protocol

| Event | Action |
|---|---|
| **Session start** | Read git branch → check `session/{branch}/` exists → if yes, resume from there (load state, decisions, outputs); if no, init fresh from `contract/` templates |
| **State transition** | Update `session/{branch}/contract.json` → snapshot via `scripts/snapshot-contract.sh` |
| **Session end** (COMPLETE/BLOCKED) | Final snapshot → append summary to `session/state.md` → update `session/index.md` |
| **Branch switch** | Snapshot current branch first → checkout new branch → load `session/NEW/{branch}/` if exists, else init fresh |

The `session/state.md` is an append-only chronological log — every state transition creates a new entry with timestamp, phase, score, and summary. This provides a durable audit trail for every session.

### Snapshot Command

```bash
bash scripts/snapshot-contract.sh --summary "State: ${STATE} — brief description"   # Full snapshot
bash scripts/snapshot-contract.sh --snapshot-only                                      # Files-only (skip index updates)
bash scripts/snapshot-contract.sh --dry-run --verbose                                  # Preview without changes
```

### Verification

```bash
ls -la session/                                    # state.md, index.md, branch dirs
cat session/state.md                               # Chronological log
cat session/index.md                               # All branches with status
ls session/{branch-name}/                          # 4 contract files
```

### Why Per-Branch Archival Matters

Without per-branch snapshots, contract files get overwritten when switching branches or resuming sessions. The `session/` archive preserves:
- **Audit trail**: `session/state.md` grows monotonically — every state transition, every decision, every blocker
- **Safe resume**: `session/{branch}/contract.json` is the exact state from last session — no reconstruction needed
- **Discoverability**: `session/index.md` shows all branches with their status at a glance

## E3. Audit-Observability

Reference: `skills/audit-observability/SKILL.md`. Load: `skill({name: "audit-observability"})`.

Three pillars of orchestration observability:

**1. State Contract Transitions** — Tracks every envelope state change: `INIT → PLAN → PLAN_SCORED → ... → COMPLETE` or `BLOCKED`. Records transition timestamps and duration, score at transition time, which agent triggered the transition, escalation events and retry count. Useful for detecting stalled workflows, infinite retry loops, or unexpected state regressions.

**2. Score Analytics** — Aggregates scoring pipeline results over time: Tier 1 (rule-based) subtotals per phase, Tier 2 (LLM-as-judge) scores and rationales, combined verdict distribution (PASS / RETRY / BLOCKED), score trends (improving, degrading, or oscillating), and blast radius penalty frequency. Score analytics feed into the metrics.* contract fields.

**3. Cross-Service Consistency Enforcement** — Validates that all services, agents, and components adhere to the shared contract: envelope schema compliance across all agents, uniform scoring criteria application, consistent state machine rule interpretation, and contract field naming and type consistency.

## E4. Conventions Checking

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

### Automation Scripts (Auto-Persist & Scoring)

**`scripts/auto-persist.sh`** — Unified contract persistence. Writes the orchestration envelope to both lean-ctx knowledge and `session/{branch}/contract.json` in one atomic call. Supports `--dry-run`, `--no-knowledge`, `--no-file`, `--branch`, and `--triggered-by` flags. Automatically detects state transitions and appends audit log entries.

```bash
bash scripts/auto-persist.sh                              # Persist current branch
bash scripts/auto-persist.sh --dry-run                    # Preview without writing
bash scripts/auto-persist.sh --triggered-by developer     # Tag the source agent
```

**`scripts/auto-score.sh`** — Three-tier automated scoring pipeline. Runs Tier 1 rule-based checks (schema, permissions, blast radius, writing order, required fields), Tier 2 LLM-as-judge (when available), and computes the combined PASS/RETRY/BLOCKED verdict. Mirrors the scoring logic from the orchestration contract.

```bash
bash scripts/auto-score.sh --file session/{branch}/contract.json --rules rules/rules.json
bash scripts/auto-score.sh --file contract.json --rules rules.json --score-only   # Just the number
```

### Guard & Recovery Scripts

**`scripts/state-guard.sh`** — Agent state access verification. Checks if an agent is allowed to operate in the current contract state by reading `rules.json agent_states`. Prevents agents from being called in states they don't have access to.

```bash
bash scripts/state-guard.sh --agent system-analyst --state PLAN     # PASS
bash scripts/state-guard.sh --agent system-analyst --state EXECUTE  # BLOCKED
```

**`scripts/self-repair.sh`** — Contract corruption recovery. Validates the current contract, scans `session/{branch}/` for valid snapshots when corruption is detected, and restores from the newest valid snapshot. Requires `--force` for auto-restore; prompts by default.

```bash
bash scripts/self-repair.sh                              # Check + auto-detect
bash scripts/self-repair.sh --dry-run                    # Preview restoration
bash scripts/self-repair.sh --force                      # Restore without prompt
```

**`scripts/drift-detect.sh`** — Drift detection between lean-ctx knowledge and file versions of the contract. Compares 5 key fields (`state`, `score.combined`, `score.verdict`, `session.task_id`, `retry.attempt`) and reports discrepancies.

```bash
bash scripts/drift-detect.sh                             # Auto-detect branch
bash scripts/drift-detect.sh --verbose                   # Show all field values
```

### Spec Gate & Knowledge Verification

**`scripts/sdd-gate.sh`** — SDD (Spec-Driven Development) gate enforcement. Checks if a change touches >3 files, crosses service boundaries, or is estimated >30 min. If so, requires an approved spec before EXECUTE delegation. Supports trivial fix, config-only, and doc-only exemptions.

```bash
bash scripts/sdd-gate.sh --file session/{branch}/contract.json
bash scripts/sdd-gate.sh --file contract.json --estimate 30
```

**`scripts/verify-knowledge.sh`** — Knowledge persistence verification. Queries lean-ctx knowledge base for expected categories (architecture, patterns, testing, lessons) and reports coverage. PASS at ≥70% coverage, FAIL below.

```bash
bash scripts/verify-knowledge.sh --phase PLAN
bash scripts/verify-knowledge.sh --all
```

### Git Hooks

**`scripts/install-hooks.sh`** — Git hook manager for `.githooks/` directory. Installs, uninstalls, or checks status of pre-commit and post-commit hooks. The pre-commit hook blocks commits when the contract is BLOCKED; the post-commit hook auto re-indexes GitNexus.

```bash
bash scripts/install-hooks.sh                            # Install all hooks
bash scripts/install-hooks.sh --status                   # Check current state
bash scripts/install-hooks.sh --uninstall                # Remove hooks
```

**`.githooks/pre-commit`** — Blocks commits on feature branches when the orchestration contract is in BLOCKED state (score < 50). Only activates when `session/{branch}/contract.json` exists.

**`.githooks/post-commit`** — Auto re-indexes GitNexus after every commit by running `scripts/gitnexus-analyze.sh`.

### Ponytail Debt Convention

Intentional shortcuts are marked with `ponytail:` comments documenting the ceiling and upgrade path:

```java
// ponytail: global lock, wont scale past 10 concurrent. Upgrade: ConcurrentHashMap + stripe locks
```

Each ponytail comment must document: why the shortcut exists (constraint), what limit it imposes (ceiling), and how to fix it properly (upgrade path). The `scripts/scan-ponytail-debt.sh` script generates a technical debt report from these markers. Unresolved ponytail debt with no documented upgrade path triggers a SIMPLICITY_001 rule deduction of 15 points in Tier 1 scoring.

See `usage/ponytail.md` for full reference, or `agent.md §5` for the 6-rung frugality ladder in context.

## E5. GitNexus Execution Flows

GitNexus indexes the codebase as a knowledge graph. Current index stats: 1675 symbols, 1666 relationships, 0 execution flows.

**0 execution flows registered**: GitNexus auto-detects execution flows when entry points are annotated. Currently no orchestration paths are mapped as GitNexus processes. All lifecycle paths (INIT→PLAN→…→COMPLETE) are documented in Part A but not yet machine-annotated.

**Future work** — Add GitNexus execution flow annotations to:
- **Orchestration lifecycle**: INIT → PLAN → PLAN_SCORED → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE
- **Scoring pipeline**: Delegation → Tier 1 rules → Tier 2 LLM judge → Tier 3 verdict → state transition
- **Escalation flow**: BLOCKED → persist → user intervention → resume with retry guidance

When flows are annotated, use `gitnexus_query({query: "orchestration flow"})` for step-by-step traces or read `gitnexus://repo/workflow-state-engine/process/{name}` for a specific flow.

See `skills/gitnexus/` for the full annotation guide.

## E6. JSON Schema Reference

Full schema: `contract/contract.schema.json`. Validate against any envelope:

```bash
bash scripts/validate-contract.sh --file session/{branch}/contract.json --score
```

The JSON Schema defines: required envelope structure for all fields (state, session, requirements, decisions, scoring, retry, outputs, metrics), valid state values and allowed transitions, type constraints (string, number, array, object) with field descriptions, and optional/required status per field. A validation failure triggers a Tier 1 scoring deduction of 15 points.

All agents should validate their envelope mutations against the schema before persisting. The orchestrator enforces schema compliance at every transition via Tier 1 rule checks.

## E7. /gsd-health — Daily Health Check Command

Copy-paste this block into any AI chat to run a full workflow architecture health check:

```
Run /gsd-health to evaluate the current workflow architecture.

1. Load shared envelope — check current state, score trend, and open issues
2. Run scripts/health-check.sh — get a scored baseline
3. Review doc/workflow/*.md against actual scripts/*.sh — flag docs drift
4. Check session/health-record.md for score trend (up/down/flat)
5. Check session/state.md last 5 entries — spot recurring patterns
6. Cross-reference rules/rules.json agent_states with actual agents/*.md — are agents in sync with rules?
7. gitnexus_detect_changes({scope: "compare", base_ref: "main"}) — any unexpected scope creep?

If health_score < 90: produce a gap analysis + fix plan (like the 15-gap campaign)
If health_score >= 90 with declining trend: flag the top 3 risk areas
If health_score >= 90 with stable/improving trend: confirm health, suggest 1 optimization
```

---

[workflow-shield]: https://img.shields.io/badge/Workflow-Orchestration-blue?style=for-the-badge
