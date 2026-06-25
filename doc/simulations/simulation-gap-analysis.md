# Simulation Gap Analysis — doc/workflow.md vs Execution Reality

> Generated 2026-06-25 from 4 simulation use cases on branch `simulation/workflow-test-20250625`

| # | Finding | Source | Severity | Related Doc |
|---|---------|--------|----------|-------------|
| 1 | validate-contract.sh enforcement functions broken since PR #33 | UC4: enforcement check returned 0 errors when should have caught timeout | CRITICAL | 05-operations.md (post-flight protocol) |
| 2 | SDD gate position ambiguity — doc says PONYTAIL_CHECK→EXECUTE runs SDD, rules.json has SDD at PLAN_SCORED→EXECUTE | UC1: state-machine.ts has no SDD gate after ponytail | HIGH | 02-lifecycle.md §B1d |
| 3 | `post-mortem.sh` uses `--br` not `--contract` — UC3 post-mortem failed silently | UC3: post-mortem.sh --contract file.json —br|- not compatible | MEDIUM | 05-operations.md (post-mortem ref) |
| 4 | Metrics aggregation not integrated into workflow — manual tracking only | All UCs: no automated metrics capture | MEDIUM | 05-operations.md (health-check) |
| 5 | session/health-record.md doesn't exist — health check can't run | UC1-4: health check step references non-existent file | MEDIUM | 05-operations.md §health |
| 6 | scoping.timeout_ms only validated in validate-contract.sh, not in scoring pipeline | UC4: timeout exceeded but state machine never checked elapsed_ms | MEDIUM | 04-scoring.md (scoring pipeline) |
| 7 | macOS date `%3N` doesn't pad — duration_ms may have parsing errors | UC2-3: elapsed_ms values showed 000 for nanoseconds | LOW | 01-fundamentals.md (metrics.elapsed_ms) |
| 8 | Ponytail scan not automated in simulation — manual debt_items injection | UC1-4: pre-commit-ponytail.sh not integrated into simulation | LOW | 02-lifecycle.md §ponytail |
| 9 | No automated PR feedback or trend analysis integration | UC2 retry pattern shows learning but no feedback loop | LOW | 05-operations.md §gsd-health |

## Detail

### Finding 1 [CRITICAL]: Enforcement functions broken
**File:** `scripts/validate-contract.sh:522-581`
**Bug:** `check_timeout_enforcement()` and `check_deadlock_config()` had missing `fi` closures and used `ret` instead of `return`. Both functions returned 0 (success) regardless of input — enforcement was silently broken since PR #33.
**Simulation:** UC4 ran timeout check, expected `FAIL` but got `PASS` for a contract with `elapsed_ms: 60000` vs `timeout_ms: 30000`.
**Fix:** Added proper if/fi/else structure, replaced `ret` with `return`. Syntax verified.

### Finding 2 [HIGH]: SDD gate position ambiguity
**Doc:** `02-lifecycle.md §B1d` says PONYTAIL_CHECK→EXECUTE runs the "orig SDD gate (spec check)".
**Code:** `state-machine.ts` has SDD gate at PLAN_SCORED→EXECUTE (SDD bypass via `sdd_triggered` flag). No SDD gate exists after PONYTAIL_CHECK.
**Recommendation:** Either update doc to reflect code, or add SDD gate after PONYTAIL_CHECK in state-machine.ts.

### Finding 3 [MEDIUM]: post-mortem.sh flag mismatch
**Doc:** `05-operations.md` references post-mortem analysis with `--contract <file>` flag.
**Code:** `scripts/post-mortem.sh` uses `--br` for contract/backend ref, not `--contract`.
**Simulation:** UC3 post-mortem failed because `--contract` wasn't a valid flag.
**Fix:** Add `--contract` as alias for `--br` in post-mortem.sh.

### Finding 4 [MEDIUM]: Metrics not integrated
**Scripts created in PR #34** (`trend-analyzer.sh`, `metrics-aggregator.sh`) exist but are not called from the main workflow (autonomous-runner.sh, post-flight protocol).
**Recommendation:** Add metrics calls to session save protocol and post-flight hook.

### Finding 5 [MEDIUM]: health-record.md missing
**Doc:** `05-operations.md` §health references `session/health-record.md` for score trend.
**Reality:** File doesn't exist. Health check step 4 will fail.
**Fix:** Create template and initialize during setup.

### Finding 6 [MEDIUM]: Timeout not in scoring pipeline
**Doc:** `04-scoring.md` describes 3-tier scoring rules. No mention of timeout enforcement.
**Code:** `state-machine.ts` scoring doesn't check `metrics.elapsed_ms` vs `scoring.timeout_ms`.
**Recommendation:** Add elapsed_ms vs timeout_ms check in scoring pipeline (or document that validate-contract.sh is the only enforcement point).

### Finding 7 [LOW]: macOS date portability
**Issue:** `date +%s%3N` on BSD `date` (macOS) doesn't pad nanoseconds to 3 digits — returns e.g. `1719250328000` correctly but format is shell-dependent.
**Affected:** `scripts/validate-contract.sh:44`, `scripts/auto-score.sh:45`, simulation test steps.
**Fix:** Use `perl -MTime::HiRes -e 'printf "%.0f", Time::HiRes::time * 1000'` for portable millisecond timestamps.

### Finding 8 [LOW]: Ponytail scan not automated
**Simulation:** UC1-4 manually set `ponytail.debt_items` in contract JSON.
**Production:** `pre-commit-ponytail.sh` scans staged git changes.
**Gap:** No pre-commit hook was tested. Simulation covered state transitions only, not actual git-level enforcement.
**Recommendation:** Add git-level ponytail test as UC5.

### Finding 9 [LOW]: No feedback loop integration
**PR #34 scripts** (`pr-feedback-loop.sh`, `trend-analyzer.sh`) exist but aren't wired into the main orchestration loop.
**Simulation:** UC2 showed learning behavior (score 55→65→72) but no automated threshold adjustment.
**Recommendation:** Wire pr-feedback-loop.sh into session completion protocol.
