<!-- omit from toc -->

# Part E — Operations & Reference

> See [doc/workflow/README.md](../workflow/README.md) for index.

This part covers operational procedures (post-flight protocol, session lifecycle), tooling (audit observability, conventions scripts), and reference material (GitNexus flows, JSON Schema).

## E1. Post-Flight Protocol

This 9-step protocol runs before every commit. It verifies impact, persists knowledge, archives session state, and re-indexes code intelligence. Execute all 9 steps unless exceptions apply.

| # | Step | Tool | Exceptions |
|---|---|---|---|
| 0 | Validate contract | `bash scripts/validate-contract.sh --file session/{branch}/contract.json --score` | — |
| 1 | Impact verify | `gitnexus_impact` | Docs-only skip |
| 2 | Change detect | `gitnexus_detect_changes` | Docs-only skip |
| 3 | Knowledge persist | `lean-ctx ctx_knowledge remember` | — |
| 4 | Session archive | `bash scripts/snapshot-contract.sh --snapshot-only` | — |
| 5 | Save conversation | `lean-ctx ctx_session save` | — |
| 6 | Re-index GitNexus | `bash scripts/gitnexus-analyze.sh` | Docs-only skip |
| 7 | Run metrics aggregation | `bash scripts/metrics-aggregator.sh` | Docs-only skip |
| 8 | Re-index Graphify | `graphify --update 2>/dev/null || true` | Docs-only skip |

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

**One-shot alias**: `save session` = all 9 post-flight steps. Always run the full protocol — partial saves lose audit trail, break resumption, or leave stale indexes.

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
| **Post-merge** | Run `update all states`: GitNexus re-index → Graphify re-index → snapshot → save session |

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

### Prototype Mode & Uncertainty Routing

**`scripts/prototype-mode.sh`** — Prototype-First Mode (G26) toggle. Switches between prototype-mode (lightweight, low-ceremony workflow) and full orchestration mode. In prototype mode: SDD gate is skipped, scoring pipeline is bypassed (no PLAN_SCORED/EXECUTE_SCORED/REVIEW_SCORED), single-pass execute (no retry cycles for prototype code), and auto-merge enabled (no formal review gate). Mode state is persisted to `session/{branch}/.mode`. Ponytail intensity is read from `rules.json -> ponytail.default_intensity`.

```bash
bash scripts/prototype-mode.sh --enable             # Enable prototype mode
bash scripts/prototype-mode.sh --disable            # Disable, restore full orchestration
bash scripts/prototype-mode.sh --status             # Check if prototype mode is active
bash scripts/prototype-mode.sh --enable --verbose   # Enable with detail
```

**`scripts/uncertainty-router.sh`** — Uncertainty-Based Routing (G27). Routes decisions based on confidence/uncertainty level. Thresholds are read from `rules.json -> decisions.confidence_journal` (maps 1-5 scale to 0-100). Routing: 0-30 → ESCALATE to user (exit 2), 31-60 → COUNCIL/REVIEW (exit 1), 61-85 → PROCEED WITH NOTES (exit 0), 86-100 → AUTO-APPROVE (exit 0). Supports `--advisory-only` for non-blocking recommendation mode. Domain-specific guidance for code, architecture, security, deployment, testing, and requirements decisions.

```bash
bash scripts/uncertainty-router.sh --score 25 --domain architecture    # ESCALATE
bash scripts/uncertainty-router.sh --score 75 --domain code --advisory-only  # Advisory
bash scripts/uncertainty-router.sh --score 95 --domain deployment      # AUTO
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

### Analytics & Trend Scripts

**`scripts/trend-analyzer.sh`** — Score trend analysis over time. Reads session/{branch}/contract.json and session/state.md to detect regression patterns, score trends (improving/degrading/oscillating), and produce sparkline visualizations. Supports --days N, --all-branches, --json output modes.

```bash
bash scripts/trend-analyzer.sh                                  # Last 7 days by default
bash scripts/trend-analyzer.sh --days 30 --all-branches         # 30 days, all branches
bash scripts/trend-analyzer.sh --json                           # Machine-readable output
```

**`scripts/metrics-aggregator.sh`** — Cross-session quality metrics aggregation. Produces summary statistics (total sessions, avg score, pass rate), by-state breakdowns, timeline views, and quality metrics (avg issues per phase, retry rate, avg duration). Reads from session/state.md and session/index.md.

```bash
bash scripts/metrics-aggregator.sh                              # Default summary mode
bash scripts/metrics-aggregator.sh --mode by-state              # Breakdown by state
bash scripts/metrics-aggregator.sh --mode timeline              # Timeline view
bash scripts/metrics-aggregator.sh --mode quality               # Quality metrics
```

### MCP Reliability Scripts

**`scripts/mcp-retry.sh`** — Auto-retry with configurable backoff strategies for MCP failures. Supports exponential, linear, and fibonacci backoff modes with configurable base delay (default 1s), max delay (default 30s), and max retries (default 3). Includes jitter for thundering herd prevention and circuit breaker state tracking.

```bash
bash scripts/mcp-retry.sh --cmd "graphify query 'test'"         # Retry a command
bash scripts/mcp-retry.sh --cmd "curl $URL" --backoff linear    # Linear backoff
bash scripts/mcp-retry.sh --cmd "mcp-health.sh" --max-retries 5 # Increase retry limit
```

**`scripts/mcp-health.sh`** — MCP server health checks. Tests connectivity to graphify-mcp, gitnexus, sumopod API, and other MCP endpoints. Supports single-check and continuous monitoring modes. Returns pass/fail with response time and error details. Results are persisted to `session/health-record.md` for historical trend analysis.

```bash
bash scripts/mcp-health.sh                                      # Single check all endpoints
bash scripts/mcp-health.sh --continuous                         # Continuous monitoring
bash scripts/mcp-health.sh --endpoint sumopod                   # Check specific endpoint
```

### Feedback & Learning Scripts

**`scripts/pr-feedback-loop.sh`** — Automated PR feedback analysis. Analyzes PR review scores, block rate, and retry frequency to auto-adjust configuration thresholds. Tracks improvement over time and recommends threshold changes when patterns emerge.

```bash
bash scripts/pr-feedback-loop.sh                                # Analyze recent PRs
bash scripts/pr-feedback-loop.sh --adjust                       # Auto-adjust thresholds
bash scripts/pr-feedback-loop.sh --dry-run                      # Preview adjustments
```

**`scripts/post-mortem.sh`** — BLOCKED state post-mortem analysis. Analyzes the escalation trace from BLOCKED events and produces structured findings: root cause, failure pattern, lessons learned, and recommendations. Supports quick, deep, and report output modes.

```bash
bash scripts/post-mortem.sh --contract session/{branch}/contract.json  # Analyze a BLOCKED contract
bash scripts/post-mortem.sh --branch feature/my-branch --mode deep     # Deep analysis
bash scripts/post-mortem.sh --mode report                              # Generate full report
```

### Enforcement & Monitoring Scripts

**`scripts/contract-enforcer.sh`** — Runtime contract validation enforcement. Monitors contract state in real-time, validates transitions against rules.json, enforces agent→state MCP mappings, and can trigger BLOCKED transitions on violation. Supports validate (check only), enforce (auto-block), and mcp (agent-level enforcement) modes.

```bash
bash scripts/contract-enforcer.sh --mode validate              # Check contract state
bash scripts/contract-enforcer.sh --mode enforce               # Enforce with auto-block
bash scripts/contract-enforcer.sh --mode mcp --agent developer # Agent-level enforcement
```

**`scripts/ponytail-daemon.sh`** — Continuous ponytail debt monitoring. Runs as a lightweight daemon that periodically scans the codebase for new ponytail debt markers, compares against the last scan, and alerts on debt growth. Supports --interval, --alert-threshold, and --json output.

```bash
bash scripts/ponytail-daemon.sh                                # Start with default interval
bash scripts/ponytail-daemon.sh --interval 300                 # Every 5 minutes
bash scripts/ponytail-daemon.sh --alert-threshold 5            # Alert at 5+ new debt items
```

**`scripts/hook-enforcer.sh`** — Git hook installation and enforcement. Ensures all required git hooks (pre-commit, post-commit) are installed and enforced. Can detect missing hooks, install them automatically, and report compliance.

```bash
bash scripts/hook-enforcer.sh                                  # Check hook status
bash scripts/hook-enforcer.sh --install                        # Install missing hooks
bash scripts/hook-enforcer.sh --enforce                        # Force hook requirements
```

**`scripts/scheduled-runner.sh`** — Cron-style scheduled task runner for workflow operations. Supports scheduled ponytail scans, health checks, trend analysis, and metrics aggregation. Schedule config from rules.json §scheduled. Supports --list, --run, --daemon modes.

```bash
bash scripts/scheduled-runner.sh --list                        # List scheduled tasks
bash scripts/scheduled-runner.sh --run ponytail                # Run ponytail scan
bash scripts/scheduled-runner.sh --daemon                      # Start scheduler daemon
```

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
