#!/usr/bin/env bash
# pre-post-flight.sh — Pre-flight & post-flight enforcement for orchestration sessions
#
# Pre-flight (before commit/state transition):
#   Validates contract, checks blast radius, enforces timeouts, detects drift
# Post-flight (after commit/state transition):
#   Validates contract, snapshots session, re-indexes gitnexus
#
# Usage:
#   scripts/pre-post-flight.sh pre-flight --file <contract.json> [--branch <name>]
#   scripts/pre-post-flight.sh post-flight --file <contract.json> [--branch <name>]
#   scripts/pre-post-flight.sh --help

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_pass() { echo -e "  ${GREEN}[PASS]${NC} $*"; }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $*"; }
log_info() { echo -e "  ${YELLOW}[INFO]${NC} $*"; }
log_verbose() { [[ "$VERBOSE" == "true" ]] && echo -e "  ${CYAN}[VERB]${NC} $*"; }

usage() {
    cat <<EOF
Usage: $(basename "$0") <mode> [options]

Modes:
  pre-flight    Run pre-flight checks before commit/transition
  post-flight   Run post-flight checks after commit/transition

Options:
  --file <path>     Path to contract.json (required)
  --branch <name>   Branch name (auto-detected if omitted)
  --verbose         Verbose output
  --help            Show this help

Pre-flight checks:
  1. Contract validation (via validate-contract.sh)
  2. Blast radius — changed files vs contract scope
  3. Timeout enforcement — elapsed_ms vs scoring.timeout_ms
  4. Drift detection — contract vs lean-ctx knowledge

Post-flight checks:
  1. Contract validation (via validate-contract.sh)
  2. Session snapshot (via snapshot-contract.sh)
  3. GitNexus re-index (via gitnexus-analyze.sh)
  4. Knowledge persist signal
EOF
    exit 0
}

# --- Pre-flight ---
pre_flight() {
    local contract_file="$1"
    local branch="$2"
    local exit_code=0

    echo "=== PRE-FLIGHT ENFORCEMENT ==="
    echo "  Branch:   $branch"
    echo "  Contract: $contract_file"
    echo ""

    # 1. Contract validation
    if [[ -f "scripts/validate-contract.sh" ]]; then
        echo "--- Step 1: Contract Validation ---"
        if bash scripts/validate-contract.sh --file "$contract_file" --score; then
            log_pass "Contract validation OK"
        else
            log_fail "Contract validation FAILED"
            exit_code=1
        fi
    else
        log_info "scripts/validate-contract.sh not found — skipping contract validation"
    fi
    echo ""

    # 2. Blast radius check
    echo "--- Step 2: Blast Radius Check ---"
    if command -v jq &>/dev/null; then
        local scope
        scope=$(jq -r '.orchestration_contract.planning.impact_scope.scope // empty' "$contract_file" 2>/dev/null || echo "")
        if [[ -n "$scope" ]]; then
            local changed_files
            changed_files=$(git diff --name-only HEAD 2>/dev/null || git diff --name-only 2>/dev/null || echo "")
            if [[ -n "$changed_files" ]]; then
                local outside=0
                while IFS= read -r file; do
                    if [[ -n "$file" && "$scope" != "all" ]]; then
                        if ! echo "$file" | grep -qE "^(${scope//\//\\/})"; then
                            log_verbose "File outside expected scope: $file"
                            outside=$((outside + 1))
                        fi
                    fi
                done <<< "$changed_files"
                if [[ $outside -gt 0 ]]; then
                    log_info "$outside changed file(s) outside declared scope '$scope' — verify intentional"
                else
                    log_pass "All changed files in scope '$scope'"
                fi
            fi
        else
            log_info "No impact_scope found in contract — skipping blast radius check"
        fi
    else
        log_info "jq not found — skipping blast radius check"
    fi
    echo ""

    # 3. Timeout enforcement
    echo "--- Step 3: Timeout Enforcement ---"
    if command -v jq &>/dev/null; then
        local elapsed_ms timeout_ms
        elapsed_ms=$(jq -r '.metrics.elapsed_ms // 0' "$contract_file" 2>/dev/null || echo "0")
        timeout_ms=$(jq -r '.scoring.timeout_ms // 0' "$contract_file" 2>/dev/null || echo "0")
        if [[ "$timeout_ms" -gt 0 && "$elapsed_ms" -gt 0 ]]; then
            if [[ "$elapsed_ms" -gt "$timeout_ms" ]]; then
                log_fail "TIMEOUT: elapsed_ms ($elapsed_ms) exceeds timeout_ms ($timeout_ms)"
                exit_code=1
            else
                log_pass "elapsed_ms ($elapsed_ms) within timeout_ms ($timeout_ms)"
            fi
        else
            log_info "No timeout config to enforce (elapsed_ms=$elapsed_ms, timeout_ms=$timeout_ms)"
        fi
    else
        log_info "jq not found — skipping timeout enforcement"
    fi
    echo ""

    # 4. Drift detection
    echo "--- Step 4: Drift Detection ---"
    if [[ -f "scripts/drift-detect.sh" ]]; then
        bash scripts/drift-detect.sh --branch "$branch" --file "$contract_file" 2>/dev/null || log_info "Drift detected — run scripts/drift-detect.sh for details"
        log_pass "Drift check completed"
    else
        log_info "scripts/drift-detect.sh not found — skipping drift detection"
    fi
    echo ""

    if [[ $exit_code -eq 0 ]]; then
        echo "=== PRE-FLIGHT PASSED ==="
    else
        echo "=== PRE-FLIGHT FAILED (check above) ==="
    fi

    return $exit_code
}

# --- Post-flight ---
post_flight() {
    local contract_file="$1"
    local branch="$2"
    local exit_code=0

    echo "=== POST-FLIGHT ENFORCEMENT ==="
    echo "  Branch:   $branch"
    echo "  Contract: $contract_file"
    echo ""

    # 1. Contract validation
    if [[ -f "scripts/validate-contract.sh" ]]; then
        echo "--- Step 1: Contract Validation ---"
        bash scripts/validate-contract.sh --file "$contract_file" --score || exit_code=1
    else
        log_info "scripts/validate-contract.sh not found — skipping contract validation"
    fi
    echo ""

    # 2. Session snapshot
    echo "--- Step 2: Session Snapshot ---"
    if [[ -f "scripts/snapshot-contract.sh" ]]; then
        bash scripts/snapshot-contract.sh --summary "Post-flight snapshot" --verbose 2>/dev/null && log_pass "Session snapshot created" || log_fail "Session snapshot failed"
    else
        log_info "scripts/snapshot-contract.sh not found — skipping snapshot"
    fi
    echo ""

    # 3. GitNexus re-index
    echo "--- Step 3: GitNexus Re-index ---"
    if [[ -f "scripts/gitnexus-analyze.sh" ]]; then
        bash scripts/gitnexus-analyze.sh 2>/dev/null && log_pass "GitNexus re-indexed" || log_info "GitNexus re-index skipped (non-zero exit)"
    else
        log_info "scripts/gitnexus-analyze.sh not found — skipping re-index"
    fi
    echo ""

    # 4. Knowledge persist signal
    echo "--- Step 4: Knowledge Persist ---"
    if [[ -d ".opencode/context/knowledge" ]]; then
        log_info "Knowledge directory exists — run 'lean-ctx ctx_knowledge remember' to persist decisions"
        log_pass "Knowledge persist check completed"
    else
        log_info "No knowledge directory found — skipping knowledge persist check"
    fi
    echo ""

    if [[ $exit_code -eq 0 ]]; then
        echo "=== POST-FLIGHT PASSED ==="
    else
        echo "=== POST-FLIGHT COMPLETED WITH ISSUES ==="
    fi

    return $exit_code
}

# --- Main ---
MODE=""
CONTRACT_FILE=""
BRANCH=""
VERBOSE="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) usage ;;
        --verbose) VERBOSE="true" ;;
        --file) CONTRACT_FILE="$2"; shift ;;
        --branch) BRANCH="$2"; shift ;;
        pre-flight|post-flight) MODE="$1" ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
    shift
done

if [[ -z "$MODE" ]]; then
    echo "ERROR: Missing mode. Use 'pre-flight' or 'post-flight'." >&2
    usage
fi

# Auto-detect branch
if [[ -z "$BRANCH" ]]; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
fi

# Auto-detect contract file if not specified
if [[ -z "$CONTRACT_FILE" ]]; then
    if [[ -f "session/$BRANCH/contract.json" ]]; then
        CONTRACT_FILE="session/$BRANCH/contract.json"
    elif [[ -f "contract/contract.template.json" ]]; then
        CONTRACT_FILE="contract/contract.template.json"
    else
        echo "ERROR: No contract file found. Use --file <path>." >&2
        exit 1
    fi
    log_info "Auto-detected contract file: $CONTRACT_FILE"
fi

case "$MODE" in
    pre-flight)  pre_flight  "$CONTRACT_FILE" "$BRANCH" ;;
    post-flight) post_flight "$CONTRACT_FILE" "$BRANCH" ;;
esac
