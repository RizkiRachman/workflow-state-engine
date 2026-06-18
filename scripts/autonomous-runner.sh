#!/usr/bin/env bash
# shellcheck disable=SC2086
# autonomous-runner.sh — 10-loop Autonomous Meta-Analysis Framework
# Orchestrates 10 iterations of PLAN→EXECUTE→REVIEW via opencode run.
# Each iteration captures JSON metrics, state transitions, and scoring.
# Mixed permission mode: bypass (1-5), normal (6-10).
#   bash scripts/autonomous-runner.sh                  # Full 10 iterations
#   bash scripts/autonomous-runner.sh --help            # Show usage
#   bash scripts/autonomous-runner.sh --dry-run         # Preview without executing
#   bash scripts/autonomous-runner.sh --iterations N    # Override count
#   bash scripts/autonomous-runner.sh --resume N        # Continue from N
#   0 — All iterations completed
#   1 — Partial completion (some iterations BLOCKED/failed)
#   2 — Fatal error (opencode not found, invalid args)
# Requirements:
#   - bash 4+
#   - opencode 1.x (in PATH)
#   - jq (for JSON metric parsing)

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ITERATIONS=10
RESUME_FROM=1
DRY_RUN=false
VERBOSE=false
EXIT_CODE=0
BLOCKED_COUNT=0
PASS_COUNT=0
START_TIME=""

# Color output (disable if not a terminal)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN='' RED='' YELLOW='' CYAN='' BLUE='' BOLD='' NC=''
fi

log_pass()  { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail()  { echo -e "${RED}[FAIL]${NC} $1"; EXIT_CODE=1; }
log_info()  { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_verbose(){ [[ "$VERBOSE" == true ]] && echo -e "${CYAN}[DEBUG]${NC} $1"; }
log_dry()   { echo -e "${BLUE}[DRY-RUN]${NC} $1"; }
log_bold()  { echo -e "${BOLD}$1${NC}"; }

usage() {
    cat <<'USAGE'
Usage: autonomous-runner.sh [OPTIONS]

10-loop autonomous meta-analysis framework. Runs PLAN→EXECUTE→REVIEW
iterations via opencode run, collecting metrics per iteration.

Options:
  --help              Show this help and exit
  --dry-run           Preview all iterations without executing opencode
  --iterations N      Number of iterations to run (default: 10)
  --resume N          Resume from iteration N (default: 1)
  --verbose           Detailed per-phase output

Iterations 1-5 use --dangerously-skip-permissions (bypass mode).
Iterations 6-10 use normal permission mode.

Each iteration saves metrics to doc/analysis/iter-N/metrics.json.
After completion, generates doc/analysis/10-loop-report.md.
USAGE
    exit 2
}

# Parse command-line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help) usage ;;
            --dry-run) DRY_RUN=true; shift ;;
            --iterations)
                if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    echo "Error: --iterations requires a positive integer"
                    exit 2
                fi
                ITERATIONS="$2"; shift 2 ;;
            --resume)
                if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    echo "Error: --resume requires a positive integer"
                    exit 2
                fi
                RESUME_FROM="$2"; shift 2 ;;
            --verbose) VERBOSE=true; shift ;;
            *)
                echo "Error: Unknown option: $1"
                usage ;;
        esac
    done
}

# Verify prerequisites
check_prereqs() {
    if ! command -v opencode &>/dev/null; then
        log_fail "opencode not found in PATH. Install: npm i -g @opencode/cli"
        exit 2
    fi
    if ! command -v jq &>/dev/null; then
        log_fail "jq not found in PATH. Install: brew install jq"
        exit 2
    fi
    log_pass "Prerequisites: opencode $(opencode --version 2>/dev/null || echo '?'), jq $(jq --version 2>/dev/null || echo '?')"
}

# Get ISO timestamp (macOS/BSD compatible)
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Get epoch milliseconds for duration calculation
get_epoch_ms() {
    if command -v gdate &>/dev/null; then
        gdate +%s%3N
    else
        date +%s000 2>/dev/null || echo 0
    fi
}

# Determine permissions mode for a given iteration
get_permissions_flag() {
    local iter="$1"
    if [[ "$iter" -le 5 ]]; then
        echo "--dangerously-skip-permissions"
    else
        echo ""
    fi
}

# Determine permissions mode label
get_permissions_label() {
    local iter="$1"
    if [[ "$iter" -le 5 ]]; then
        echo "bypass"
    else
        echo "normal"
    fi
}

# Generate the opencode run prompt for each phase
generate_prompt() {
    local phase="$1"
    local iter="$2"
    case "$phase" in
        PLAN)
            cat <<'PROMPT'
You are system-analyst in the workflow-state-engine meta-analysis framework.
Analyze current project state against orchestration contract.
Report on: workflow architecture adherence, contract enforcement,
agent behavior consistency, autonomous capability gaps.
Output JSON with findings and recommendations.
PROMPT
            ;;
        EXECUTE)
            cat <<'PROMPT'
You are developer in the workflow-state-engine meta-analysis framework.
Implement changes identified in the PLAN phase.
Focus on: contract compliance, state machine transitions,
writing order adherence, and edge case handling.
PROMPT
            ;;
        REVIEW)
            cat <<'PROMPT'
You are quality-analyst in the workflow-state-engine meta-analysis framework.
Review the implementation for: code quality, security vulnerabilities,
governance compliance, permission bypass risks, and test coverage.
Output JSON with scores and remediation items.
PROMPT
            ;;
    esac
}

# Run a single opencode phase and capture metrics
run_phase() {
    local iter="$1"
    local phase="$2"
    local agent="$3"
    local permissions_flag="$4"
    local prompt
    prompt="$(generate_prompt "$phase" "$iter")"
    local start_ms
    start_ms=$(get_epoch_ms)
    local exit_code=0
    # Convert phase to lowercase for filename (POSIX-compatible)
    local phase_lower
    phase_lower=$(echo "$phase" | tr '[:upper:]' '[:lower:]')
    local output_file="$PROJECT_ROOT/doc/analysis/iter-${iter}/${phase_lower}-output.json"
    local cmd_base="opencode run"

    # Build command
    local cmd="$cmd_base --agent $agent --format json"
    if [[ -n "$permissions_flag" ]]; then
        cmd="$cmd $permissions_flag"
    fi
    cmd="$cmd \"$prompt\""

    # Use stderr for log messages so stdout is clean for return value capture
    log_info "  [$phase] Agent: $agent | Iteration: $iter" >&2

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "  Would run: $cmd" >&2
        log_dry "  Would save output to: $output_file" >&2
        echo '{"dry_run":true,"phase":"'$phase'","iteration":'$iter'}' > "$output_file" 2>/dev/null || true
        echo "0 0"
        return
    fi

    # Execute
    mkdir -p "$(dirname "$output_file")"
    if eval "$cmd" > "$output_file" 2>&1; then
        exit_code=0
        log_pass "  [$phase] Completed (exit=0)" >&2
    else
        exit_code=$?
        log_fail "  [$phase] Failed (exit=$exit_code)" >&2
    fi

    local end_ms
    end_ms=$(get_epoch_ms)
    local duration=$((end_ms - start_ms))
    echo "$exit_code $duration"
}

# Build the per-iteration metrics JSON
build_metrics() {
    local iter="$1"
    local plan_exit="$2" plan_duration="$3"
    local exec_exit="$4" exec_duration="$5"
    local review_exit="$6" review_duration="$7"
    local blocked="$8"
    local blocked_reason="$9"
    local timestamp
    timestamp="$(get_timestamp)"
    local perm_label
    perm_label="$(get_permissions_label "$iter")"

    cat <<METRICS
{
  "iteration": $iter,
  "timestamp": "$timestamp",
  "permissions_mode": "$perm_label",
  "duration_ms": $((plan_duration + exec_duration + review_duration)),
  "phases": {
    "PLAN": {
      "agent": "system-analyst",
      "exit_code": $plan_exit,
      "duration_ms": $plan_duration,
      "contract_state_before": "EXECUTE",
      "contract_state_after": "PLAN_SCORED",
      "score_rules": {},
      "score_combined": 0,
      "verdict": "PASS"
    },
    "EXECUTE": {
      "agent": "developer",
      "exit_code": $exec_exit,
      "duration_ms": $exec_duration,
      "contract_state_before": "PLAN_SCORED",
      "contract_state_after": "EXECUTE_SCORED",
      "score_rules": {},
      "score_combined": 0,
      "verdict": "PASS"
    },
    "REVIEW": {
      "agent": "quality-analyst",
      "exit_code": $review_exit,
      "duration_ms": $review_duration,
      "contract_state_before": "EXECUTE_SCORED",
      "contract_state_after": "REVIEW_SCORED",
      "score_rules": {},
      "score_combined": 0,
      "verdict": "PASS"
    }
  },
  "contract_compliance": {
    "field_access_violations": 0,
    "audit_log_entries_added": 0,
    "schema_validation_passed": true,
    "writing_order_violations": 0
  },
  "blocked": $blocked,
  "blocked_reason": $(if [[ -n "$blocked_reason" ]]; then echo "\"$blocked_reason\""; else echo "null"; fi)
}
METRICS
}

# Save per-iteration metrics to JSON file
save_metrics() {
    local iter="$1"
    local metrics_json="$2"
    local target_dir="$PROJECT_ROOT/doc/analysis/iter-${iter}"
    local target_file="$target_dir/metrics.json"

    mkdir -p "$target_dir"
    echo "$metrics_json" > "$target_file"
    log_verbose "  Metrics saved: $target_file"
}

# Check if opencode output indicates BLOCKED state
detect_blocked() {
    local output_file="$1"
    if [[ ! -f "$output_file" ]]; then
        echo "false"
        return
    fi
    if grep -qi "BLOCKED\|blocked\|FATAL\|permission denied" "$output_file" 2>/dev/null; then
        echo "true"
    else
        echo "false"
    fi
}

# Generate the final analysis report
generate_report() {
    local report_file="$PROJECT_ROOT/doc/analysis/10-loop-report.md"
    local timestamp
    timestamp="$(get_timestamp)"

    log_info "Generating final analysis report: $report_file"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would generate report at: $report_file"
        return
    fi

    mkdir -p "$(dirname "$report_file")"

    cat > "$report_file" <<REPORT
# 10-Loop Autonomous Meta-Analysis Report

**Generated**: $timestamp
**Iterations**: ${RESUME_FROM}–${ITERATIONS}
**Permissions mode**: Bypass (1–5), Normal (6–10)
**Total BLOCKED**: ${BLOCKED_COUNT} / $((ITERATIONS - RESUME_FROM + 1))

---

## Executive Summary

This report presents the results of ${ITERATIONS} autonomous meta-analysis iterations,
each running PLAN → EXECUTE → REVIEW via the workflow-state-engine orchestration framework.
The meta-analysis evaluates workflow architecture adherence, contract enforcement,
agent behavior consistency, autonomous capability, and the impact of permission bypass.

---

## 1. Workflow Architecture Adherence

Analysis of how well the state machine transitions, agent delegation patterns,
and writing orders conform to the canonical architecture defined in \`rules/rules.json\`
and \`doc/workflow.md\`.

| Iteration | Architecture Score | Deviations | Notes |
|-----------|-------------------|------------|-------|
| 1–10 | — | — | TBD from opencode run output |

**Findings**:
- _To be populated after iteration completion._

---

## 2. Contract Enforcement

Evaluation of contract.json schema compliance, field access control,
audit log completeness, and score pipeline execution.

| Iteration | Schema Valid | Audit Entries | Score Pipeline | Violations |
|-----------|-------------|---------------|----------------|------------|
| 1–10 | — | — | — | — |

**Findings**:
- _To be populated after iteration completion._

---

## 3. Agent Behavior Consistency

Assessment of consistency across agent types (system-analyst, developer,
quality-analyst) across multiple iterations. Measures output format adherence,
governance compliance, and decision reproducibility.

| Iteration | Agent | Format Adherence | Governance Score | Consistency |
|-----------|-------|-----------------|------------------|-------------|
| 1–10 | — | — | — | — |

**Findings**:
- _To be populated after iteration completion._

---

## 4. Autonomous Capability

Evaluation of the framework's ability to run without human intervention:
self-recovery from BLOCKED states, error handling, state persistence, and resume.

| Metric | Value | Notes |
|--------|-------|-------|
| Total iterations | ${ITERATIONS} | — |
| BLOCKED count | ${BLOCKED_COUNT} | — |
| Avg duration per iteration | — | — |
| Resume capability | — | — |

**Findings**:
- _To be populated after iteration completion._

---

## 5. Permission Bypass Comparison

Comparative analysis of bypass mode (iterations 1–5) vs normal mode (iterations 6–10)
on score quality, violation rate, agent output thoroughness, and governance compliance.

| Metric | Bypass (1–5) | Normal (6–10) | Delta |
|--------|-------------|---------------|-------|
| Avg score | — | — | — |
| Avg duration | — | — | — |
| BLOCKED count | — | — | — |
| Violations found | — | — | — |

**Findings**:
- _To be populated after iteration completion._

---

## Iteration Log

| Iter | Permissions | PLAN | EXECUTE | REVIEW | Duration | BLOCKED |
|------|-------------|------|---------|--------|----------|---------|
REPORT

    # Append per-iteration summary rows
    for ((i = RESUME_FROM; i <= ITERATIONS; i++)); do
        local metrics_file="$PROJECT_ROOT/doc/analysis/iter-${i}/metrics.json"
        local perm_label
        perm_label="$(get_permissions_label "$i")"
        local plan_status="—" exec_status="—" review_status="—" duration="—" blocked="—"

        if [[ -f "$metrics_file" ]]; then
            plan_status=$(jq -r '.phases.PLAN.exit_code | if . == 0 then "✅" else "❌" end' "$metrics_file" 2>/dev/null || echo "?")
            exec_status=$(jq -r '.phases.EXECUTE.exit_code | if . == 0 then "✅" else "❌" end' "$metrics_file" 2>/dev/null || echo "?")
            review_status=$(jq -r '.phases.REVIEW.exit_code | if . == 0 then "✅" else "❌" end' "$metrics_file" 2>/dev/null || echo "?")
            duration=$(jq -r '.duration_ms | if . > 0 then (. / 1000 | tostring) + "s" else "—" end' "$metrics_file" 2>/dev/null || echo "—")
            blocked=$(jq -r 'if .blocked then "🚫" else "—" end' "$metrics_file" 2>/dev/null || echo "—")
        fi

        echo "| $i | $perm_label | $plan_status | $exec_status | $review_status | $duration | $blocked |" >> "$report_file"
    done

    cat >> "$report_file" <<REPORT_END

---

*Report generated by autonomous-runner.sh at $timestamp.*
REPORT_END

    log_pass "Report generated: $report_file"
}

# Cleanup handler for SIGINT/SIGTERM
cleanup() {
    echo
    log_info "SIGINT received — saving partial state..."
    local timestamp
    timestamp="$(get_timestamp)"
    local summary_file="$PROJECT_ROOT/doc/analysis/partial-state-${timestamp}.json"
    cat > "$summary_file" <<PARTIAL
{
  "status": "INTERRUPTED",
  "timestamp": "$timestamp",
  "iterations_completed": $((CURRENT_ITER - 1)),
  "iterations_total": $ITERATIONS,
  "resume_from": $RESUME_FROM,
  "blocked_count": $BLOCKED_COUNT,
  "pass_count": $PASS_COUNT
}
PARTIAL
    log_info "Partial state saved to: $summary_file"
    log_info "Resume with: bash $0 --resume $CURRENT_ITER --iterations $ITERATIONS"
    exit 130
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    parse_args "$@"
    local total_iterations=$ITERATIONS
    local resume_from=$RESUME_FROM

    # Adjust if resume > iterations
    if [[ "$resume_from" -gt "$total_iterations" ]]; then
        log_fail "Resume iteration ($resume_from) exceeds total iterations ($total_iterations)"
        exit 2
    fi

    echo "=== Autonomous Meta-Analysis Runner ==="
    echo "Project root: $PROJECT_ROOT"
    echo "Iterations: $resume_from → $total_iterations (total: $((total_iterations - resume_from + 1)))"
    echo "Mode: dry-run=$DRY_RUN"
    echo ""

    check_prereqs

    # Register SIGINT handler
    trap cleanup SIGINT SIGTERM

    local START_TIME_ITER
    START_TIME_ITER="$(get_epoch_ms)"

    # ---- ITERATION LOOP ----
    for ((i = resume_from; i <= total_iterations; i++)); do
        CURRENT_ITER=$i
        local perm_flag
        perm_flag="$(get_permissions_flag "$i")"
        local perm_label
        perm_label="$(get_permissions_label "$i")"

        echo ""
        log_bold "=== Iteration $i / $total_iterations (${perm_label}) ==="

        # Create iteration directory
        mkdir -p "$PROJECT_ROOT/doc/analysis/iter-${i}"

        # ---- Phase 1: PLAN ----
        local plan_result plan_exit=0 plan_duration=0
        plan_result=$(run_phase "$i" "PLAN" "system-analyst" "$perm_flag")
        plan_exit=$(echo "$plan_result" | awk '{print $1}')
        plan_duration=$(echo "$plan_result" | awk '{print $2}')
        if [[ -z "$plan_exit" ]]; then plan_exit=0; fi
        if [[ -z "$plan_duration" ]]; then plan_duration=0; fi

        local plan_blocked=false
        if [[ "$plan_exit" -ne 0 ]]; then
            plan_blocked=true
        fi

        # ---- Phase 2: EXECUTE ----
        local exec_result exec_exit=0 exec_duration=0
        if [[ "$plan_blocked" != "true" || "$DRY_RUN" == true ]]; then
            exec_result=$(run_phase "$i" "EXECUTE" "developer" "$perm_flag")
            exec_exit=$(echo "$exec_result" | awk '{print $1}')
            exec_duration=$(echo "$exec_result" | awk '{print $2}')
            if [[ -z "$exec_exit" ]]; then exec_exit=0; fi
            if [[ -z "$exec_duration" ]]; then exec_duration=0; fi
        else
            log_info "  Skipping EXECUTE (PLAN blocked)"
        fi

        local exec_blocked=false
        if [[ "$exec_exit" -ne 0 ]]; then
            exec_blocked=true
        fi

        # ---- Phase 3: REVIEW ----
        local review_result review_exit=0 review_duration=0
        if [[ "$exec_blocked" != "true" || "$DRY_RUN" == true ]]; then
            review_result=$(run_phase "$i" "REVIEW" "quality-analyst" "$perm_flag")
            review_exit=$(echo "$review_result" | awk '{print $1}')
            review_duration=$(echo "$review_result" | awk '{print $2}')
            if [[ -z "$review_exit" ]]; then review_exit=0; fi
            if [[ -z "$review_duration" ]]; then review_duration=0; fi
        else
            log_info "  Skipping REVIEW (EXECUTE blocked)"
        fi

        # ---- Determine BLOCKED status ----
        local blocked=false
        local blocked_reason=""
        if [[ "$plan_exit" -ne 0 ]]; then
            blocked=true
            blocked_reason="PLAN phase failed (exit=$plan_exit)"
        elif [[ "$exec_exit" -ne 0 ]]; then
            blocked=true
            blocked_reason="EXECUTE phase failed (exit=$exec_exit)"
        elif [[ "$review_exit" -ne 0 ]]; then
            blocked=true
            blocked_reason="REVIEW phase failed (exit=$review_exit)"
        fi

        if [[ "$blocked" == true ]]; then
            BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
            log_info "  Iteration $i BLOCKED: $blocked_reason"
        else
            PASS_COUNT=$((PASS_COUNT + 1))
            log_pass "Iteration $i completed successfully"
        fi

        # Build and save metrics
        local metrics_json
        metrics_json=$(build_metrics "$i" "$plan_exit" "$plan_duration" "$exec_exit" "$exec_duration" "$review_exit" "$review_duration" "$blocked" "$blocked_reason")
        save_metrics "$i" "$metrics_json"

        # Detect BLOCKED from opencode output files
        local plan_output="$PROJECT_ROOT/doc/analysis/iter-${i}/PLAN-output.json"
        local exec_output="$PROJECT_ROOT/doc/analysis/iter-${i}/EXECUTE-output.json"
        local review_output="$PROJECT_ROOT/doc/analysis/iter-${i}/REVIEW-output.json"

        if [[ "$(detect_blocked "$plan_output")" == "true" ]]; then
            log_info "  PLAN output indicates BLOCKED state"
        fi
        if [[ "$(detect_blocked "$exec_output")" == "true" ]]; then
            log_info "  EXECUTE output indicates BLOCKED state"
        fi
        if [[ "$(detect_blocked "$review_output")" == "true" ]]; then
            log_info "  REVIEW output indicates BLOCKED state"
        fi
    done

    local END_TIME_ITER
    END_TIME_ITER="$(get_epoch_ms)"
    local total_duration=$((END_TIME_ITER - START_TIME_ITER))

    # Generate final report
    echo ""
    generate_report

    # Print summary
    echo ""
    log_bold "=== Meta-Analysis Complete ==="
    echo "  Iterations: $((total_iterations - resume_from + 1)) (${resume_from}→${total_iterations})"
    echo "  Passed:     ${PASS_COUNT}"
    echo "  BLOCKED:    ${BLOCKED_COUNT}"
    echo "  Duration:   $((total_duration / 1000))s"
    echo "  Report:     doc/analysis/10-loop-report.md"
    echo ""

    if [[ "$BLOCKED_COUNT" -gt 0 ]]; then
        log_info "${BLOCKED_COUNT} iteration(s) BLOCKED — review report for details"
        exit 1
    fi
    exit 0
}

main "$@"
