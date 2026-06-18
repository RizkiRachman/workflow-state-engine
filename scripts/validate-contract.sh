#!/usr/bin/env bash
# =============================================================================
# validate-contract.sh — Envelope Integrity & Transition Validator
#
# Validates a session/{branch}/contract.json (or contract.template.json) against:
#   1. JSON validity
#   2. Schema-required field presence (top-level + nested subsections)
#   3. State machine enum validity
#   4. State transition validity (when --prev-state or --rules provided)
#
# Usage:
#   ./scripts/validate-contract.sh [--file path] [--rules path] [--prev-state STATE]
#   ./scripts/validate-contract.sh            # auto-detect session/{branch}/contract.json → template
#   ./scripts/validate-contract.sh --verbose  # detailed field-level reporting
#   ./scripts/validate-contract.sh --score    # output numeric score for CI
#
# Exit codes:
#   0 = PASS (score ≥ 70)
#   1 = RETRY (score 50-69)
#   2 = BLOCKED (score < 50 or critical errors)
# =============================================================================

set -euo pipefail

# --- Config ----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTRACT_FILE=""
RULES_FILE="$PROJECT_DIR/rules/rules.json"
PREV_STATE=""
VERBOSE=false
SCORE_MODE=false
PASS_COUNT=0
FAIL_COUNT=0
DEDUCTION=0
MAX_SCORE=100

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# --- Help ------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Validate a contract JSON file against schema and transition rules.

Options:
  --file PATH         Contract JSON file to validate (default: auto-detect)
  --rules PATH        Path to rules.json (default: \$PROJECT_DIR/rules/rules.json)
  --prev-state STATE  Expected previous state for transition validation
  --verbose           Show detailed field-level results
  --score             Output numeric score only (for CI/scripts)
  --help              Show this message
EOF
    exit 0
}

# --- Logging functions -----------------------------------------------------
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo "  $1"; }

# --- Auto-detect contract file ---------------------------------------------
detect_contract_file() {
    local candidates=()
    local br
    br=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ -n "$br" && "$br" != "HEAD" ]]; then
        candidates+=("$PROJECT_DIR/session/$br/contract.json")
    fi
    candidates+=(
        "$PROJECT_DIR/contract/contract.json"
        "$PROJECT_DIR/contract/contract.template.json"
    )
    for f in "${candidates[@]}"; do
        if [[ -f "$f" ]]; then
            CONTRACT_FILE="$f"
            return 0
        fi
    done
    echo "ERROR: No contract file found. Use --file to specify." >&2
    exit 1
}

# --- Step 1: JSON validity -------------------------------------------------
check_json_valid() {
    local file="$1"
    if python3 -c "
import json, sys
try:
    with open('$file') as f:
        json.load(f)
    sys.exit(0)
except Exception as e:
    print(str(e))
    sys.exit(1)
"; then
        log_pass "JSON is valid"
        return 0
    else
        log_fail "JSON is INVALID"
        return 1
    fi
}

# --- Step 2: Top-level required fields -------------------------------------
REQUIRED_TOP_LEVEL=(
    "contract_version" "state_machine_version" "state" "session" "requirements"
    "decisions" "governance" "score" "retry" "outputs" "metrics"
    "token_budget" "scope" "validation" "lessons_learned" "audit_log"
)

check_top_level_fields() {
    local file="$1"
    local missing=()
    for field in "${REQUIRED_TOP_LEVEL[@]}"; do
        if ! python3 -c "
import json
with open('$file') as f:
    data = json.load(f)
print('$field' in data)
" 2>/dev/null | grep -q True; then
            missing+=("$field")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_pass "All 16 top-level required fields present"
        return 0
    else
        log_fail "Missing top-level fields: ${missing[*]}"
        return 1
    fi
}

# --- Step 3: Validate state enum ------------------------------------------
VALID_STATES=("INIT" "PLAN" "PLAN_SCORED" "EXECUTE" "EXECUTE_SCORED" "REVIEW" "REVIEW_SCORED" "COMPLETE" "BLOCKED")

check_state_enum() {
    local file="$1"
    local state
    state=$(python3 -c "
import json
with open('$file') as f:
    print(json.load(f).get('state', 'MISSING'))
" 2>/dev/null)

    if [[ "$state" == "MISSING" ]]; then
        log_fail "'state' field is missing"
        return 1
    fi

    for valid in "${VALID_STATES[@]}"; do
        if [[ "$state" == "$valid" ]]; then
            log_pass "State '$state' is valid enum value"
            return 0
        fi
    done

    log_fail "State '$state' is NOT a valid enum value (${VALID_STATES[*]})"
    return 1
}

# --- Step 4: Nested required fields (per schema) ---------------------------
check_nested_fields() {
    local file="$1"
    local nested_checks=(
        "session:task_id"
        "session:branch"
        "session:created_at"
        "session:archived_at"
        "requirements:goal"
        "requirements:acceptance_criteria"
        "requirements:constraints"
        "decisions:approved_architecture"
        "decisions:coding_standard"
        "decisions:rejected_approaches"
        "decisions:adr_log"
        "decisions:ddd_performed"
        "governance:active_agent"
        "governance:mode"
        "governance:applicable_skills"
        "governance:rules_references"
        "governance:cur_guidance"
        "governance:permissions"
        "governance:prev_blockers"
        "score:rules"
        "score:judge"
        "score:combined"
        "score:verdict"
        "retry:cur_phase"
        "retry:attempt"
        "retry:max_attempts"
        "retry:score_threshold"
        "retry:escalation_threshold"
        "retry:issues"
        "retry:phase_issues"
        "retry:escalation_trace"
        "outputs:plan"
        "outputs:architecture"
        "outputs:code_changes"
        "outputs:test_results"
        "outputs:agent_reports"
        "outputs:score_summary"
        "metrics:cost_tokens"
        "metrics:elapsed_ms"
        "metrics:agents_used"
        "metrics:phases_completed"
        "metrics:phase_durations"
        "token_budget:max_per_session"
        "token_budget:W_threshold"
        "token_budget:hard_limit"
        "token_budget:max_per_phase"
        "token_budget:max_per_subagent_call"
        "token_budget:cur_session_usage"
        "token_budget:phase_usage"
        "scope:included"
        "scope:excluded"
        "scope:boundary"
        "scope:parallel_eligible"
        "scope:max_parallel_agents"
        "scope:shard_id"
        "scope:parallel_instances"
        "validation:block_on"
        "validation:rule_overrides"
        "validation:build_verified"
        "validation/block_on:max_test_failures"
        "validation/block_on:max_score_drop"
        "validation/block_on:max_compile_errors"
    )

    local missing=()
    for check in "${nested_checks[@]}"; do
        IFS=':' read -r parent field <<< "$check"
        # Handle nested paths like validation/block_on
        if [[ "$parent" == */* ]]; then
            local parent_key="${parent%/*}"
            local sub_key="${parent#*/}"
            if ! python3 -c "
import json
with open('$file') as f:
    data = json.load(f)
try:
    d = data
    for k in '${parent_key}','${sub_key}':
        d = d[k]
    print('${field}' in d)
except:
    print('False')
" 2>/dev/null | grep -q True; then
                missing+=("$parent.$field")
            fi
        else
            if ! python3 -c "
import json
with open('$file') as f:
    data = json.load(f)
try:
    print('${field}' in data['${parent}'])
except:
    print('False')
" 2>/dev/null | grep -q True; then
                missing+=("$parent.$field")
            fi
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_pass "All 60+ nested required fields present"
        return 0
    else
        log_fail "Missing nested fields (${#missing[@]}): ${missing[*]}"
        return 1
    fi
}

# --- Step 5: Content quality checks (Tier 1 semantic validation) -----------
check_content_quality() {
    local file="$1"

    if python3 -c "
import json, sys

with open('$file') as f:
    data = json.load(f)

fails = []
state = data.get('state', 'INIT')
score = data.get('score', {})
outputs = data.get('outputs', {})
audit = data.get('audit_log', [])
scope = data.get('scope', {})
decisions = data.get('decisions', {})
validation = data.get('validation', {})

state_rank = ['INIT', 'PLAN', 'PLAN_SCORED', 'EXECUTE', 'EXECUTE_SCORED', 'REVIEW', 'REVIEW_SCORED', 'COMPLETE', 'BLOCKED']
try:
    si = state_rank.index(state)
except ValueError:
    si = 0

# 1. If state beyond INIT, score should not be all zeros/INIT
if si >= 1:
    combined = score.get('combined', 0)
    verdict = score.get('verdict', 'INIT')
    if combined == 0 and verdict == 'INIT':
        fails.append('State %s but score still 0/INIT' % state)

# 2. If PLAN_SCORED+, outputs.plan should not be null
if si >= 2:
    plan = outputs.get('plan')
    if plan is None or plan == '':
        fails.append('State %s but outputs.plan null/empty' % state)

# 3. If REVIEW_SCORED+, outputs.architecture should not be null
if si >= 6:
    arch = outputs.get('architecture')
    if arch is None:
        fails.append('State %s but outputs.architecture null' % state)

# 4. If EXECUTE_SCORED+, outputs.code_changes should not be empty
if si >= 4:
    changes = outputs.get('code_changes', [])
    if len(changes) == 0:
        fails.append('State %s but outputs.code_changes empty' % state)

# 5. If verdict is PASS, combined score should be >= 70
if score.get('verdict') == 'PASS' and score.get('combined', 0) < 70:
    fails.append('score.verdict PASS but combined=%d < 70' % score.get('combined', 0))

# 6. If state beyond INIT, audit_log should not be empty
if si >= 1 and len(audit) == 0:
    fails.append('State %s but audit_log empty' % state)

# 6a. Audit log trim: flag if >100 entries or >10KB content
if len(audit) > 100:
    fails.append('audit_log has %d entries (>100) — consider trimming' % len(audit))
if len(str(audit)) > 10240:
    fails.append('audit_log content is %d bytes (>10KB) — consider trimming' % len(str(audit)))

# 7. SDD gate: if scope.included has >3 items, flag SDD
incl = scope.get('included', [])
if len(incl) > 3:
    fails.append('scope.included has %d items (>3) — SDD should trigger' % len(incl))

# 8. DDD: if PLAN_SCORED+, decisions.ddd_performed should be true
if si >= 2:
    ddd = decisions.get('ddd_performed', False)
    if not ddd:
        fails.append('State %s but decisions.ddd_performed false — DDD should have run' % state)

# 9. Build verify: if REVIEW_SCORED+, validation.build_verified should be true
if si >= 6:
    bv = validation.get('build_verified', False)
    if not bv:
        fails.append('State %s but validation.build_verified false — build verify should have run' % state)

# 10. Recurring retry tracking: check escalation_trace for repeated patterns
retry_data = data.get('retry', {})
trace = retry_data.get('escalation_trace', [])
if len(trace) >= 2:
    issue_counts = {}
    for entry in trace:
        if isinstance(entry, dict):
            # Object entries: extract from 'issues' key or use stringified entry
            issues = entry.get('issues', [entry.get('reason', str(entry))[:80]])
            for issue in (issues if isinstance(issues, list) else [str(issues)[:80]]):
                key = str(issue)[:80]
                issue_counts[key] = issue_counts.get(key, 0) + 1
        elif isinstance(entry, str):
            issue_counts[entry[:80]] = issue_counts.get(entry[:80], 0) + 1
    recurring = {k: v for k, v in issue_counts.items() if v >= 2}
    if recurring:
        for issue, count in recurring.items():
            fails.append('Recurring retry issue (%dx): %s' % (count, issue[:60]))

# 11. Partial credit: when BLOCKED, note what passed
if state == 'BLOCKED':
    # Report checks that DID pass before failing
    passed = []
    if si >= 1 and score.get('combined', 0) > 0:
        passed.append('score recorded (combined=%d)' % score.get('combined'))
    if si >= 2 and outputs.get('plan'):
        passed.append('plan exists')
    if len(audit) > 0:
        passed.append('%d audit entries' % len(audit))
    if passed:
        print('  [PARTIAL] BLOCKED state — %d checks passed: %s' % (len(passed), '; '.join(passed)))

if len(fails) > 0:
    for f in fails:
        print('  [CONTENT] ' + f)
    sys.exit(1)
sys.exit(0)
" 2>&1; then
        log_pass "Content quality checks passed"
        return 0
    else
        log_fail "Content quality issues detected (see above)"
        return 1
    fi
}

# --- Step 6a: Field-level access control check ----------------------------
check_field_access() {
    local file="$1"

    if python3 -c "
import json, sys

with open('$file') as f:
    data = json.load(f)

gov = data.get('governance', {})
perms = gov.get('permissions', {})
ro = perms.get('read_only_fields', [])
wo = perms.get('writeable_fields', [])

# Check no overlap
overlap = [f for f in ro if f in wo]
if overlap:
    print('  [CONTENT] Field access overlap (read-only and writeable both contain): ' + ', '.join(overlap))

# Check all listed fields exist as top-level keys
top_keys = set(data.keys())
all_listed = set(ro + wo)
missing = [f for f in all_listed if f not in top_keys]
if missing:
    print('  [CONTENT] Field access references non-existent top-level keys: ' + ', '.join(missing))

if overlap or missing:
    sys.exit(1)
sys.exit(0)
" 2>&1; then
        log_pass "Field-level access control valid"
        return 0
    else
        log_fail "Field-level access control issues detected (see above)"
        return 1
    fi
}

# --- Step 7: Transition validation (if --prev-state) -----------------------
TRANSITIONS_FILE=$(python3 -c "
import json, sys
with open('$RULES_FILE') as f:
    rules = json.load(f)
trans = rules.get('state_machine', {}).get('transitions', [])
for t in trans:
    print(f\"{t.get('from','?')}->{t.get('to','?')}\")
" 2>/dev/null) || TRANSITIONS_FILE=""

check_transition() {
    local file="$1"
    local current_state
    current_state=$(python3 -c "
import json
with open('$file') as f:
    print(json.load(f).get('state', ''))
")

    if [[ -z "$PREV_STATE" ]]; then
        log_verbose "No --prev-state provided, skipping transition validation"
        return 0
    fi

    if [[ "$PREV_STATE" == "$current_state" ]]; then
        log_verbose "State unchanged ($PREV_STATE → $current_state), no transition needed"
        return 0
    fi

    # Check if transition is valid per rules.json
    local valid=false
    local transition_key="$PREV_STATE"
    # rules.json uses wildcard "*" for any-to-any (or specific transitions)
    while IFS= read -r rule_trans; do
        local from="${rule_trans%%->*}"
        local to="${rule_trans##*->}"
        if [[ ("$from" == "$PREV_STATE" || "$from" == "*") && ("$to" == "$current_state" || "$to" == "*") ]]; then
            valid=true
            break
        fi
    done <<< "$TRANSITIONS_FILE"

    if [[ "$valid" == true ]]; then
        log_pass "Transition '$PREV_STATE → $current_state' is valid per rules.json"
        return 0
    else
        log_fail "Transition '$PREV_STATE → $current_state' is NOT in rules.json allowed transitions"
        return 1
    fi
}

# --- Scoring ---------------------------------------------------------------
compute_score() {
    local total_checks=$((PASS_COUNT + FAIL_COUNT))
    if [[ $total_checks -eq 0 ]]; then
        echo "0"
        return
    fi

    # Start at 100, deduct for failures
    local raw_score=$((MAX_SCORE - DEDUCTION))
    if [[ $raw_score -lt 0 ]]; then
        raw_score=0
    fi
    echo "$raw_score"
}

# --- Check wrapper (suppress non-score output in --score mode) -----------
run_check() {
    if [[ "$SCORE_MODE" == true ]]; then
        "$@" >&2
    else
        "$@"
    fi
}

# --- Main ------------------------------------------------------------------
main() {
    # Parse args
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file) CONTRACT_FILE="$2"; shift 2 ;;
            --rules) RULES_FILE="$2"; shift 2 ;;
            --prev-state) PREV_STATE="$2"; shift 2 ;;
            --verbose) VERBOSE=true; shift ;;
            --score) SCORE_MODE=true; shift ;;
            --help|-h) usage ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done

    # Auto-detect contract file if not specified
    if [[ -z "$CONTRACT_FILE" ]]; then
        detect_contract_file
    fi

    if [[ ! -f "$CONTRACT_FILE" ]]; then
        echo "ERROR: File not found: $CONTRACT_FILE" >&2
        exit 2
    fi

    if [[ ! -f "$RULES_FILE" ]]; then
        echo "WARNING: Rules file not found: $RULES_FILE (transition validation disabled)" >&2
    fi

    if [[ "$SCORE_MODE" == false ]]; then
        echo "=========================================="
        echo " Contract Validation Report"
        echo " File: $CONTRACT_FILE"
        echo "=========================================="
        echo ""
    fi

    # Step 1: JSON validity
    if ! run_check check_json_valid "$CONTRACT_FILE"; then
        if [[ "$SCORE_MODE" == false ]]; then
            echo ""
            echo "BLOCKED: Invalid JSON"
        fi
        exit 2
    fi
    PASS_COUNT=$((PASS_COUNT + 1))

    # Step 2: Top-level fields
    if run_check check_top_level_fields "$CONTRACT_FILE"; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        DEDUCTION=$((DEDUCTION + 15))
    fi

    # Step 3: State enum
    if run_check check_state_enum "$CONTRACT_FILE"; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        DEDUCTION=$((DEDUCTION + 15))
    fi

    # Step 4: Nested fields
    if run_check check_nested_fields "$CONTRACT_FILE"; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        DEDUCTION=$((DEDUCTION + 15))
    fi

    # Step 5: Content quality checks
    if run_check check_content_quality "$CONTRACT_FILE"; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        DEDUCTION=$((DEDUCTION + 20))
    fi

    # Step 6: Field-level access control
    if run_check check_field_access "$CONTRACT_FILE"; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        DEDUCTION=$((DEDUCTION + 15))
    fi

    # Step 7: Transition (conditional)
    if [[ -n "$PREV_STATE" ]]; then
        if run_check check_transition "$CONTRACT_FILE"; then
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            DEDUCTION=$((DEDUCTION + 20))
        fi
    fi

    # Compute score
    local score
    score=$(compute_score)

    if [[ "$SCORE_MODE" == false ]]; then
        echo ""
        echo "------------------------------------------"
        echo " Results: $PASS_COUNT passed, $FAIL_COUNT failed"
        echo " Deduction: $DEDUCTION points"
        echo " Score: $score/100"
        echo "------------------------------------------"
    fi

    if [[ "$SCORE_MODE" == true ]]; then
        # Suppress all non-score output in score mode
        echo "$score"
    fi

    # Exit code
    if [[ $score -ge 70 ]]; then
        if [[ "$SCORE_MODE" == false ]]; then
            echo -e "${GREEN}VERDICT: PASS${NC}"
        fi
        exit 0
    elif [[ $score -ge 50 ]]; then
        if [[ "$SCORE_MODE" == false ]]; then
            echo -e "${YELLOW}VERDICT: RETRY${NC}"
        fi
        exit 1
    else
        if [[ "$SCORE_MODE" == false ]]; then
            echo -e "${RED}VERDICT: BLOCKED${NC}"
        fi
        exit 2
    fi
}

main "$@"
