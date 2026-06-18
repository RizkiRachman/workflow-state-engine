# Meta-Analysis Framework — Architecture Decisions

## Overview

The 10-loop autonomous meta-analysis framework enables the workflow-state-engine
to analyze its own orchestration behavior through repeated PLAN → EXECUTE →
REVIEW cycles. This is a recursive meta-analysis: the orchestration framework
analyzes itself across multiple runs to evaluate workflow architecture adherence,
contract enforcement, agent consistency, and autonomous capability.

## Architecture

```
autonomous-runner.sh
  ├── Iteration 1..10
  │     ├── Phase 1: PLAN      (system-analyst agent)
  │     ├── Phase 2: EXECUTE   (developer agent)
  │     └── Phase 3: REVIEW    (quality-analyst agent)
  └── doc/analysis/
        ├── iter-N/metrics.json   (per-iteration metrics)
        └── 10-loop-report.md     (cumulative analysis report)

collect-metrics.sh
  └── Aggregates all iter-*/metrics.json into cumulative JSON summary
```

## Key Design Decisions

### 1. Bash for-loop + opencode run

| Decision | Chosen approach | Rationale |
|----------|----------------|-----------|
| Runtime | Bash script wrapping `opencode run` | No additional infrastructure. Leverages existing opencode agent definitions. |
| Alternative rejected | Python + subprocess | Adding Python dependency violates ponytail ladder — bash is sufficient. |
| Alternative rejected | Makefile targets | Less flexible for --resume, --iterations, --dry-run. |

### 2. Mixed Permission Mode

- Iterations 1–5: `--dangerously-skip-permissions` (bypass mode)
- Iterations 6–10: Normal permission enforcement

**Rationale**: The meta-analysis compares agent output quality and governance
compliance with and without permission gates. This reveals whether permission
bypass impacts output thoroughness, violation rate, or score quality.

### 3. Per-Iteration Metrics Storage

- Each iteration writes `doc/analysis/iter-N/metrics.json`
- Includes: phase exit codes, durations, contract state transitions, compliance data
- Enables incremental analysis and resume capability

### 4. BLOCKED Tolerance

BLOCKED iterations are logged and continue — they don't stop the loop.
This is by design: the BLOCKED count is a key metric of autonomous capability
and permission impact.

### 5. Resume Capability (`--resume N`)

- Skips iterations < N
- Continues from iteration N
- Partial state saved on SIGINT to `doc/analysis/partial-state-*.json`

## Scope

- **Included**: `scripts/autonomous-runner.sh`, `scripts/collect-metrics.sh`,
  `doc/analysis/10-loop-report.md`, `doc/analysis/iter-*/metrics.json`
- **Excluded**: `src/`, `pom.xml`, `db/`, CI/CD configuration

## File Layout

```
scripts/
├── autonomous-runner.sh    # Main orchestrator (637L)
└── collect-metrics.sh      # Metrics aggregation (270L)

doc/analysis/
├── 10-loop-report.md       # Analysis report template (157L)
├── meta-analysis-framework.md # This file
└── iter-*/                 # Per-iteration metrics (generated at runtime)
    ├── metrics.json
    ├── PLAN-output.json
    ├── EXECUTE-output.json
    └── REVIEW-output.json
```

## Agent Mapping

Each iteration dispatches to three opencode agents:

| Phase | Agent | Role | Allowed States |
|-------|-------|------|----------------|
| PLAN | system-analyst | Analyze project state, report on architecture, contract, consistency | INIT, PLAN, PLAN_SCORED |
| EXECUTE | developer | Implement changes identified in PLAN | EXECUTE, EXECUTE_SCORED |
| REVIEW | quality-analyst | Review quality, security, governance | REVIEW, REVIEW_SCORED |

## Metrics Schema

Per-iteration `metrics.json`:

```json
{
  "iteration": 1,
  "timestamp": "2026-06-18T14:35:00Z",
  "permissions_mode": "bypass|normal",
  "duration_ms": 0,
  "phases": {
    "PLAN": { "agent": "system-analyst", "exit_code": 0, "duration_ms": 0,
              "contract_state_before": "EXECUTE", "contract_state_after": "PLAN_SCORED",
              "score_rules": {}, "score_combined": 0, "verdict": "PASS" },
    "EXECUTE": { ... },
    "REVIEW": { ... }
  },
  "contract_compliance": {
    "field_access_violations": 0,
    "audit_log_entries_added": 0,
    "schema_validation_passed": true,
    "writing_order_violations": 0
  },
  "blocked": false,
  "blocked_reason": null
}
```

## Verification

| Test | Expected | Status |
|------|----------|--------|
| `bash -n scripts/autonomous-runner.sh` | Zero syntax errors | ✅ |
| `bash -n scripts/collect-metrics.sh` | Zero syntax errors | ✅ |
| `bash scripts/autonomous-runner.sh --help` | Prints usage | ✅ |
| `bash scripts/autonomous-runner.sh --dry-run` | Prints plan for all 10 iterations | ✅ |
| `bash scripts/autonomous-runner.sh --iterations 1 --dry-run` | Single iteration dry-run | ✅ |
| `bash scripts/autonomous-runner.sh --iterations 3 --resume 2 --dry-run` | Resume from 2 | ✅ |