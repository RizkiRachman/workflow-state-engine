#!/usr/bin/env bash
# =============================================================================
# detect-parallel-conflicts.sh — Detect file conflicts between parallel agents
#
# Takes two file lists (or git diff outputs) and finds overlapping
# file modifications. Used by the orchestrator to reconcile parallel
# agent outputs before accepting changes.
#
# Usage:
#   ./scripts/detect-parallel-conflicts.sh --agent1 FILELIST1 --agent2 FILELIST2
#   ./scripts/detect-parallel-conflicts.sh --agent1 <(git diff --name-only agent1) --agent2 <(git diff --name-only agent2)
#   ./scripts/detect-parallel-conflicts.sh --diff1 agent1.diff --diff2 agent2.diff
#   ./scripts/detect-parallel-conflicts.sh --agent1 F1 --agent2 F2 --verbose
#
# Input format: One file path per line (or a unified diff — script auto-detects)
#
# Exit codes:
#   0 = No conflicts
#   1 = Conflicts found
#   2 = Usage error
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERBOSE=false
AGENT1_FILE=""
AGENT2_FILE=""
AGENT1_LABEL="agent-1"
AGENT2_LABEL="agent-2"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Detect file conflicts between two parallel agents.

Options:
  --agent1 FILE    File list from first agent (one path per line, or diff)
  --agent2 FILE    File list from second agent
  --label1 TEXT     Label for agent 1 (default: "agent-1")
  --label2 TEXT     Label for agent 2 (default: "agent-2")
  --verbose         Show detailed output
  --help            Show this message

Input formats (auto-detected):
  - Plain file list (one path per line)
  - Unified diff (parses +++ lines)
  - Git diff --name-only output

Exit codes:
  0 = No conflicts
  1 = Conflicts found
  2 = Usage error
EOF
    exit 0
}

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo "  $1"; }

# --- Parse diff or plain file list -----------------------------------------
extract_files() {
    local input="$1"
    local output
    output=$(mktemp)

    # Check if it looks like a unified diff (contains +++ lines)
    if grep -q '^+++ ' "$input" 2>/dev/null; then
        # Extract files from diff — look for +++ b/ paths
        grep '^+++ ' "$input" | sed 's/^+++ b\///' | sed 's/^+++ //' | sort -u > "$output"
    elif grep -q '^diff --git' "$input" 2>/dev/null; then
        # Another diff format
        grep '^--- ' "$input" | sed 's/^--- a\///' | sort -u > "$output"
    else
        # Plain file list
        grep -v '^$' "$input" | grep -v '^#' | sed 's|^\./||' | sort -u > "$output"
    fi

    echo "$output"
}

# --- Main ------------------------------------------------------------------
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --agent1) AGENT1_FILE="$2"; shift 2 ;;
            --agent2) AGENT2_FILE="$2"; shift 2 ;;
            --diff1) AGENT1_FILE="$2"; shift 2 ;;
            --diff2) AGENT2_FILE="$2"; shift 2 ;;
            --label1) AGENT1_LABEL="$2"; shift 2 ;;
            --label2) AGENT2_LABEL="$2"; shift 2 ;;
            --verbose) VERBOSE=true; shift ;;
            --help|-h) usage ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done

    if [[ -z "$AGENT1_FILE" || -z "$AGENT2_FILE" ]]; then
        echo "ERROR: --agent1 and --agent2 are required" >&2
        exit 2
    fi

    if [[ ! -f "$AGENT1_FILE" ]]; then
        echo "ERROR: File not found: $AGENT1_FILE" >&2
        exit 2
    fi
    if [[ ! -f "$AGENT2_FILE" ]]; then
        echo "ERROR: File not found: $AGENT2_FILE" >&2
        exit 2
    fi

    echo "=========================================="
    echo " Parallel Conflict Detection Report"
    echo " Agent 1: $AGENT1_LABEL ($AGENT1_FILE)"
    echo " Agent 2: $AGENT2_LABEL ($AGENT2_FILE)"
    echo "=========================================="
    echo ""

    # Extract file lists
    local files1 files2
    files1=$(extract_files "$AGENT1_FILE")
    files2=$(extract_files "$AGENT2_FILE")

    local count1 count2
    count1=$(wc -l < "$files1" | tr -d ' ')
    count2=$(wc -l < "$files2" | tr -d ' ')

    log_info "Agent 1 modifies $count1 file(s)"
    log_info "Agent 2 modifies $count2 file(s)"

    if [[ "$VERBOSE" == true ]]; then
        echo ""
        log_verbose "=== $AGENT1_LABEL files ==="
        while IFS= read -r f; do log_verbose "  $f"; done < "$files1"
        echo ""
        log_verbose "=== $AGENT2_LABEL files ==="
        while IFS= read -r f; do log_verbose "  $f"; done < "$files2"
        echo ""
    fi

    # Find conflicts
    local conflicts
    conflicts=$(comm -12 "$files1" "$files2" | grep -v '^$' || true)

    local conflict_count
    if [[ -z "$conflicts" ]]; then
        conflict_count=0
    else
        conflict_count=$(echo "$conflicts" | wc -l | tr -d ' ')
    fi

    echo ""
    if [[ "$conflict_count" -eq 0 ]]; then
        log_pass "No conflicts — agents modified disjoint file sets"
        rm -f "$files1" "$files2"
        exit 0
    else
        log_fail "$conflict_count overlapping file(s) detected!"
        echo ""
        echo "$conflicts" | while IFS= read -r f; do
            echo "  ⚠  $f"
        done
        echo ""
        log_info "Resolution: Re-deploy these files serially (one agent at a time)"
        rm -f "$files1" "$files2"
        exit 1
    fi
}

main "$@"
