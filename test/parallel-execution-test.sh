#!/usr/bin/env bash
# parallel-execution-test.sh — Test suite for detect-parallel-conflicts.sh
# Validates conflict detection with multi-file scenarios.
# Usage:
#   test/parallel-execution-test.sh              # Run all tests
#   test/parallel-execution-test.sh --verbose    # Show detailed output
#   test/parallel-execution-test.sh --help
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT_SCRIPT="$SCRIPT_DIR/../scripts/detect-parallel-conflicts.sh"
VERBOSE=false
PASSED=0
FAILED=0
TOTAL=5

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Test script for scripts/detect-parallel-conflicts.sh.

Options:
  --verbose    Show detailed command output
  --help       Show this help message

Tests:
  1. No conflict           — disjoint file sets
  2. Single conflict       — one overlapping file
  3. Multiple conflicts    — two overlapping files
  4. Empty lists           — one side has no files
  5. Mixed paths/whitespace — handles paths, empty lines, duplicates
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

if [[ ! -f "$DETECT_SCRIPT" ]]; then
    echo "ERROR: $DETECT_SCRIPT not found" >&2
    exit 1
fi

cleanup() {
    rm -rf /tmp/parallel-test-*
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

# Run a single test case
#   run_test name expected_exit expected_output_substr arg1 arg2 ...
run_test() {
    local name="$1" expected_exit="$2" expected_output="$3"
    shift 3
    echo "=== $name ==="

    local output=""
    local exit_code=0
    output=$("$DETECT_SCRIPT" "$@" 2>&1) || exit_code=$?

    if [[ "$VERBOSE" == true ]]; then
        echo "  Command: $DETECT_SCRIPT $*"
        echo "  Output:"
        while IFS= read -r line; do
            echo "    $line"
        done <<< "$output"
    fi

    if [[ "$exit_code" -eq "$expected_exit" ]]; then
        pass "Exit code $exit_code (expected $expected_exit)"
    else
        fail "Exit code $exit_code (expected $expected_exit)"
    fi

    if [[ -n "$expected_output" ]]; then
        if echo "$output" | grep -Fq "$expected_output"; then
            pass "Output contains '$expected_output'"
        else
            fail "Output does not contain '$expected_output'"
        fi
    fi
}

echo "============================================"
echo " Parallel Execution Conflict Detection Tests"
echo "============================================"
echo ""

# ---- Test 1: No conflict ----
td1="/tmp/parallel-test-1"
mkdir -p "$td1"
printf 'file-a.java\nfile-b.java\n' > "$td1/agent1.txt"
printf 'file-c.java\nfile-d.java\n' > "$td1/agent2.txt"
run_test \
    "Test 1: No conflict" \
    0 "" \
    --agent1 "$td1/agent1.txt" --agent2 "$td1/agent2.txt"

# ---- Test 2: Single conflict ----
td2="/tmp/parallel-test-2"
mkdir -p "$td2"
printf 'file-a.java\nfile-b.java\n' > "$td2/agent1.txt"
printf 'file-b.java\nfile-c.java\n' > "$td2/agent2.txt"
run_test \
    "Test 2: Single conflict" \
    1 "file-b.java" \
    --agent1 "$td2/agent1.txt" --agent2 "$td2/agent2.txt"

# ---- Test 3: Multiple conflicts ----
td3="/tmp/parallel-test-3"
mkdir -p "$td3"
printf 'file-a.java\nfile-b.java\nfile-c.java\n' > "$td3/agent1.txt"
printf 'file-b.java\nfile-c.java\nfile-d.java\n' > "$td3/agent2.txt"
run_test \
    "Test 3: Multiple conflicts" \
    1 "2 overlapping" \
    --agent1 "$td3/agent1.txt" --agent2 "$td3/agent2.txt"

# ---- Test 4: Empty lists ----
td4="/tmp/parallel-test-4"
mkdir -p "$td4"
printf '' > "$td4/agent1.txt"
printf 'file-a.java\n' > "$td4/agent2.txt"
run_test \
    "Test 4: Empty lists" \
    0 "" \
    --agent1 "$td4/agent1.txt" --agent2 "$td4/agent2.txt"

# ---- Test 5: Mixed paths / duplicates / comments ----
td5="/tmp/parallel-test-5"
mkdir -p "$td5"
printf 'src/main/java/A.java\nsrc/test/java/B.java\n\n' > "$td5/agent1.txt"
printf 'src/main/java/A.java\n' > "$td5/agent2.txt"
run_test \
    "Test 5: Mixed paths / duplicates / comments" \
    1 "A.java" \
    --agent1 "$td5/agent1.txt" --agent2 "$td5/agent2.txt"

# ---- Results ----
echo ""
echo "============================================"
printf " Results: ${GREEN}${PASSED}${NC}/${TOTAL} passed"
if [[ "$FAILED" -gt 0 ]]; then
    printf ", ${RED}${FAILED}${NC} failed"
fi
echo ""
echo "============================================"

if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
