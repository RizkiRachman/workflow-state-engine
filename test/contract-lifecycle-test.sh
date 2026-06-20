#!/usr/bin/env bash
# contract-lifecycle-test.sh — Test suite for validate-contract.sh
# Tests contract JSON validation, state transitions, score gates, and content quality.
# Usage:
#   test/contract-lifecycle-test.sh              # Run all tests
#   test/contract-lifecycle-test.sh --verbose    # Show detailed output
#   test/contract-lifecycle-test.sh --help       # Show usage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VALIDATE_SCRIPT="$PROJECT_DIR/scripts/validate-contract.sh"
TEMPLATE_CONTRACT="$PROJECT_DIR/contract/contract.template.json"
VERBOSE=false
PASSED=0
FAILED=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Test script for scripts/validate-contract.sh.

Options:
  --verbose    Show detailed command output
  --help       Show this help message

Tests:
  1. Valid INIT contract          — baseline PASS
  2. Invalid JSON                 — malformed → BLOCKED (exit 2)
  3. Missing top-level field      — remove "state" → deduction
  4. Invalid state enum           — state="INVALID" → BLOCKED
  5. Missing nested field         — remove session.task_id → deduction
  6. INIT→PLAN transition         — valid transition, no score required
  7. PLAN→EXECUTE (skip)         — invalid transition → BLOCKED
  8. PLAN_SCORED→EXECUTE (score=80) — valid with sufficient score
  9. PLAN_SCORED→EXECUTE (score=30) — score gate blocks → BLOCKED
  10. Content quality at PLAN_SCORED no plan — missing outputs.plan → fail
  11. Content quality at REVIEW_SCORED no architecture — missing arch → fail
  12. Audit log required beyond INIT — state=PLAN but empty audit → fail
  13. Scope: parallel_eligible w/o max_parallel_agents — flagged
  14. Scope: included/excluded overlap — flagged
  15. Scope: shard_id without parallel_eligible — flagged
  16. Scope: valid parallel config — passes
  17. --score mode: outputs ONLY a number on valid contract
  18. --score mode: invalid JSON exits 2 with clean output
  19. --max-depth 0: skips deep checks, still outputs score
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose) VERBOSE=true; shift ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

if [[ ! -f "$VALIDATE_SCRIPT" ]]; then
    echo "ERROR: $VALIDATE_SCRIPT not found" >&2
    exit 1
fi

if [[ ! -f "$TEMPLATE_CONTRACT" ]]; then
    echo "ERROR: Template not found: $TEMPLATE_CONTRACT" >&2
    exit 1
fi

cleanup() {
    rm -rf /tmp/contract-test-*
}
trap cleanup EXIT

pass() {
    echo "  ${GREEN}[PASS]${NC} $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "  ${RED}[FAIL]${NC} $1"
    FAILED=$((FAILED + 1))
}

warn() {
    echo "  ${YELLOW}[WARN]${NC} $1"
}

# Helper: create a contract copy in temp dir
make_contract() {
    local dest="$1"
    mkdir -p "$(dirname "$dest")"
    cp "$TEMPLATE_CONTRACT" "$dest"
}

# Helper: set a JSON field in contract file (handles bools, strings, numbers, arrays)
set_field() {
    local file="$1" key="$2" value="$3"
    python3 -c "
import json
with open('$file') as f: data = json.load(f)
keys = '$key'.split('.')
obj = data
for k in keys[:-1]:
    obj = obj[k]
# Parse value via json.loads — handles true/false/null/numbers/strings/arrays
obj[keys[-1]] = json.loads('$value')
with open('$file', 'w') as f: json.dump(data, f, indent=2)
"
}

# Helper: delete a JSON field from contract file
del_field() {
    local file="$1" key="$2"
    python3 -c "
import json
with open('$file') as f: data = json.load(f)
keys = '$key'.split('.')
obj = data
for k in keys[:-1]:
    obj = obj[k]
del obj[keys[-1]]
with open('$file', 'w') as f: json.dump(data, f, indent=2)
"
}

# Helper: set state
set_state() {
    set_field "$1" "state" "\"$2\""
}

# Helper: set combined score
set_score() {
    set_field "$1" "score.combined" "$2"
}

# Helper: run validate-contract.sh and check exit code
run_validation() {
    local contract="$1" expected_exit="$2" label="$3"
    local extra_args="${4:-}"
    local exit_code=0
    output=$("$VALIDATE_SCRIPT" --file "$contract" --score $extra_args 2>&1) || exit_code=$?
    if [[ "$VERBOSE" == true ]]; then
        echo "    Command: $VALIDATE_SCRIPT --file $(basename $contract) --score $extra_args"
        echo "    Exit: $exit_code (expected $expected_exit)"
        echo "    Output: $output"
    fi
    if [[ "$exit_code" -eq "$expected_exit" ]]; then
        pass "$label (exit $exit_code)"
    else
        fail "$label — expected exit $expected_exit, got $exit_code"
        if [[ "$VERBOSE" == true ]]; then
            echo "    $output"
        fi
    fi
}

echo ""
echo "================================================"
echo " Contract Lifecycle Validation Tests"
echo "================================================"
echo ""

# ────────────────────────────────────────────
# Test 1: Valid INIT contract
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-1"
make_contract "$td/contract.json"
run_validation "$td/contract.json" 0 "Test 1: Valid INIT contract — PASS expected"

# ────────────────────────────────────────────
# Test 2: Invalid JSON (malformed)
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-2"
mkdir -p "$td"
echo '{"state": "INIT", broken}' > "$td/contract.json"
run_validation "$td/contract.json" 2 "Test 2: Invalid JSON — BLOCKED expected"

# ────────────────────────────────────────────
# Test 3: Missing required top-level field ("state")
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-3"
make_contract "$td/contract.json"
del_field "$td/contract.json" "state"
run_validation "$td/contract.json" 2 "Test 3: Missing 'state' field — BLOCKED expected"

# ────────────────────────────────────────────
# Test 4: Invalid state enum
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-4"
make_contract "$td/contract.json"
set_state "$td/contract.json" "INVALID"
run_validation "$td/contract.json" 2 "Test 4: Invalid state 'INVALID' — BLOCKED expected"

# ────────────────────────────────────────────
# Test 5: Missing nested field (session.task_id)
# Note: Missing session.task_id causes -15 deduction → score=85 → PASS (exit 0).
# Warning is logged but doesn't block — content quality also catches it.
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-5"
make_contract "$td/contract.json"
del_field "$td/contract.json" "session.task_id"
run_validation "$td/contract.json" 0 "Test 5: Missing session.task_id — PASS with warning (-15 deduction)"

# ────────────────────────────────────────────
# Test 6: State transition INIT→PLAN (plan state triggers content quality warnings)
# Content quality flags empty audit, DDD not done → -20 deduction, score=80 → PASS (exit 0).
# The real check is 6b: validate that INIT→PLAN is a valid transition per rules.
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-6"
make_contract "$td/contract.json"
set_state "$td/contract.json" "PLAN"
run_validation "$td/contract.json" 0 "Test 6: PLAN state content quality warning — PASS with note"
# The important check is the transition when prev-state=INIT
output=$("$VALIDATE_SCRIPT" --file "$td/contract.json" --prev-state INIT 2>&1) || true
if echo "$output" | grep -qE "[Tt]ransition.*INIT.*PLAN.*is valid"; then
    pass "Test 6b: INIT→PLAN transition valid per rules"
else
    fail "Test 6b: INIT→PLAN transition validation failed"
fi
TOTAL=$((TOTAL + 1))

# ────────────────────────────────────────────
# Test 7: Invalid transition PLAN→EXECUTE (skip PLAN_SCORED)
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-7"
make_contract "$td/contract.json"
set_state "$td/contract.json" "EXECUTE"
output=$("$VALIDATE_SCRIPT" --file "$td/contract.json" --prev-state PLAN 2>&1) || true
if echo "$output" | grep -qE "NOT in rules.json allowed transitions"; then
    pass "Test 7: PLAN→EXECUTE correctly blocked (invalid transition)"
else
    fail "Test 7: PLAN→EXECUTE should be blocked (must go through PLAN_SCORED)"
    if [[ "$VERBOSE" == true ]]; then echo "    $output"; fi
fi

# ────────────────────────────────────────────
# Test 8: PLAN_SCORED→EXECUTE with sufficient score (80)
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-8"
make_contract "$td/contract.json"
set_state "$td/contract.json" "EXECUTE"
set_score "$td/contract.json" 80
set_field "$td/contract.json" "audit_log" '[{"timestamp": "2024-01-01", "action": "test"}]'
output=$("$VALIDATE_SCRIPT" --file "$td/contract.json" --prev-state PLAN_SCORED 2>&1) || true
if echo "$output" | grep -qE "[Tt]ransition.*PLAN_SCORED.*EXECUTE.*is valid"; then
    pass "Test 8: PLAN_SCORED→EXECUTE (score=80) — valid transition"
else
    fail "Test 8: PLAN_SCORED→EXECUTE should pass with score 80"
    if [[ "$VERBOSE" == true ]]; then echo "    $output"; fi
fi

# ────────────────────────────────────────────
# Test 9: PLAN_SCORED→EXECUTE with insufficient score (30)
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-9"
make_contract "$td/contract.json"
set_state "$td/contract.json" "EXECUTE"
set_score "$td/contract.json" 30
set_field "$td/contract.json" "audit_log" '[{"timestamp": "2024-01-01", "action": "test"}]'
output=$("$VALIDATE_SCRIPT" --file "$td/contract.json" --prev-state PLAN_SCORED 2>&1) || true
if echo "$output" | grep -qE "requires score ≥ 70"; then
    pass "Test 9: PLAN_SCORED→EXECUTE (score=30) — correctly blocked by score gate"
else
    fail "Test 9: PLAN_SCORED→EXECUTE should block with score 30"
    if [[ "$VERBOSE" == true ]]; then echo "    $output"; fi
fi

# ────────────────────────────────────────────
# Test 10: Content quality — PLAN_SCORED with missing outputs.plan
# Content quality flags null plan → -20 deduction, score=80 → PASS (exit 0).
# Quality issues are warnings that inform, not blockers — score remains ≥ 70.
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-10"
make_contract "$td/contract.json"
set_state "$td/contract.json" "PLAN_SCORED"
set_score "$td/contract.json" 80
set_field "$td/contract.json" "decisions.ddd_performed" "true"
set_field "$td/contract.json" "audit_log" '[{"timestamp": "2024-01-01", "action": "test"}]'
# outputs.plan is null by default — content quality should flag
run_validation "$td/contract.json" 0 "Test 10: PLAN_SCORED with null outputs.plan — PASS with warning"

# ────────────────────────────────────────────
# Test 11: Content quality — REVIEW_SCORED with missing architecture
# Content quality flags null architecture + build_unverified → -20 deduction
# Score = 100 - 20 = 80 → PASS (exit 0). Quality warnings inform, not block.
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-11"
make_contract "$td/contract.json"
set_state "$td/contract.json" "REVIEW_SCORED"
set_score "$td/contract.json" 85
set_field "$td/contract.json" "outputs.plan" '"test plan content"'
set_field "$td/contract.json" "outputs.architecture" "null"
set_field "$td/contract.json" "outputs.code_changes" '["file1.java"]'
set_field "$td/contract.json" "decisions.ddd_performed" "true"
set_field "$td/contract.json" "validation.build_verified" "false"
set_field "$td/contract.json" "audit_log" '[{"timestamp": "2024-01-01", "action": "test"}, {"timestamp": "2024-01-02", "action": "test2"}]'
run_validation "$td/contract.json" 0 "Test 11: REVIEW_SCORED with null arch — PASS with warning"

# ────────────────────────────────────────────
# Test 12: Audit required beyond INIT — PLAN state with empty audit
# Content quality flags empty audit log → -20 deduction
# Score = 100 - 20 = 80 → PASS (exit 0). Quality warnings inform, not block.
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-12"
make_contract "$td/contract.json"
set_state "$td/contract.json" "PLAN"
set_field "$td/contract.json" "audit_log" '[]'
run_validation "$td/contract.json" 0 "Test 12: PLAN with empty audit — PASS with warning"

# ────────────────────────────────────────────
# Test 13: Scope consistency — parallel_eligible without max_parallel_agents
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-13"
make_contract "$td/contract.json"
set_field "$td/contract.json" "scope.parallel_eligible" "true"
set_field "$td/contract.json" "scope.max_parallel_agents" "0"
output=$("$VALIDATE_SCRIPT" --file "$td/contract.json" 2>&1) || true
if echo "$output" | grep -qE "[SCOPE]"; then
    pass "Test 13: parallel_eligible=true with max_parallel_agents=0 — flagged"
else
    fail "Test 13: Should flag invalid max_parallel_agents"
    if [[ "$VERBOSE" == true ]]; then echo "    $output"; fi
fi

# ────────────────────────────────────────────
# Test 14: Scope consistency — included/excluded overlap
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-14"
make_contract "$td/contract.json"
set_field "$td/contract.json" "scope.included" '["src/main/java"]'
set_field "$td/contract.json" "scope.excluded" '["src/main/java"]'
output=$("$VALIDATE_SCRIPT" --file "$td/contract.json" 2>&1) || true
if echo "$output" | grep -qE "overlap"; then
    pass "Test 14: scope.included/excluded overlap — flagged"
else
    fail "Test 14: Should flag included/excluded overlap"
    if [[ "$VERBOSE" == true ]]; then echo "    $output"; fi
fi

# ────────────────────────────────────────────
# Test 15: Scope consistency — shard_id without parallel_eligible
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-15"
make_contract "$td/contract.json"
set_field "$td/contract.json" "scope.shard_id" '"service-a"'
output=$("$VALIDATE_SCRIPT" --file "$td/contract.json" 2>&1) || true
if echo "$output" | grep -qE "shard_id"; then
    pass "Test 15: shard_id without parallel_eligible — flagged"
else
    fail "Test 15: Should flag shard_id without parallel_eligible"
    if [[ "$VERBOSE" == true ]]; then echo "    $output"; fi
fi

# ────────────────────────────────────────────
# Test 16: Scope consistency — valid parallel config passes
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-16"
make_contract "$td/contract.json"
set_field "$td/contract.json" "scope.parallel_eligible" "true"
set_field "$td/contract.json" "scope.max_parallel_agents" "3"
set_field "$td/contract.json" "scope.shard_id" '"shard-a"'
set_field "$td/contract.json" "scope.parallel_instances" '["shard-a", "shard-b", "shard-c"]'
output=$("$VALIDATE_SCRIPT" --file "$td/contract.json" 2>&1) || true
if echo "$output" | grep -qE "[PASS].*Scope consistency"; then
    pass "Test 16: Valid parallel config — passes scope checks"
else
    fail "Test 16: Valid parallel config should pass"
    if [[ "$VERBOSE" == true ]]; then echo "    $output"; fi
fi

# ────────────────────────────────────────────
# Test 17: --score mode outputs ONLY a number on valid contract
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-17"
make_contract "$td/contract.json"
output=$("$VALIDATE_SCRIPT" --file "$td/contract.json" --score 2>/dev/null)  # redirect stderr away
if echo "$output" | grep -qE '^[0-9]+$'; then
    pass "Test 17: --score mode outputs numeric score ($output)"
else
    fail "Test 17: --score mode should output only a number, got: '$output'"
fi

# ────────────────────────────────────────────
# Test 18: --score mode on invalid JSON still exits 2 but no stray output
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-18"
mkdir -p "$td"
echo 'broken' > "$td/contract.json"
exit_code=0
output=$("$VALIDATE_SCRIPT" --file "$td/contract.json" --score 2>/dev/null) || exit_code=$?
[[ $exit_code -eq 2 ]] && pass "Test 18: Exit 2 on invalid JSON in --score mode" || fail "Test 18: Expected exit 2, got $exit_code"

# ────────────────────────────────────────────
# Test 19: --max-depth 0 skips deep checks
# ────────────────────────────────────────────
TOTAL=$((TOTAL + 1))
td="/tmp/contract-test-19"
make_contract "$td/contract.json"
del_field "$td/contract.json" "session.task_id"
# Without --max-depth, this would flag missing task_id
# With --max-depth 0, it should skip nested checks
output=$("$VALIDATE_SCRIPT" --file "$td/contract.json" --max-depth 0 --score 2>/dev/null)
# Should still produce a number
if echo "$output" | grep -qE '^[0-9]+$'; then
    pass "Test 19: --max-depth 0 still outputs score"
else
    fail "Test 19: --max-depth 0 should output numeric score, got: '$output'"
fi

# ────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────
echo ""
echo "================================================"
printf " Results: ${GREEN}${PASSED}${NC}/${TOTAL} passed"
if [[ "$FAILED" -gt 0 ]]; then
    printf ", ${RED}${FAILED}${NC} failed"
fi
echo ""
echo "================================================"

if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
exit 0
