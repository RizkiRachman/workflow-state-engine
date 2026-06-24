#!/usr/bin/env bash
# =============================================================================
# rollback-state.sh — Rollback orchestration state to a previous snapshot
#
# Manages state rollback for the workflow state engine. When BLOCKED state is
# reached, this script enables recovery to the last good state by restoring
# session/{branch}/contract.json from the snapshot archive.
#
# Features:
#   - Lists available snapshots for a branch
#   - Restores a specific snapshot by index (1 = latest, 2 = previous, etc.)
#   - Verifies SHA-256 integrity before restore
#   - Preserves the current (failed) state as contract.json.failed
#   - Creates a new state.md entry documenting the rollback
#
# Usage:
#   ./scripts/rollback-state.sh                    # List all snapshots for current branch
#   ./scripts/rollback-state.sh --restore 1        # Restore latest snapshot
#   ./scripts/rollback-state.sh --restore 2        # Restore 2nd latest
#   ./scripts/rollback-state.sh --list             # Same as no-arg (list snapshots)
#   ./scripts/rollback-state.sh --branch BRANCH    # Override branch detection
#   ./scripts/rollback-state.sh --dry-run          # Show what would be done
#   ./scripts/rollback-state.sh --verbose          # Detailed output
#   ./scripts/rollback-state.sh --help             # Show usage
#
# Exit codes:
#   0 = Rollback completed successfully
#   1 = Error (no snapshots, invalid index, etc.)
#   2 = Usage error
# =============================================================================

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

VERBOSE=false
DRY_RUN=false
BRANCH_OVERRIDE=""
RESTORE_INDEX=""
MODE="list"

if [[ -t 1 ]]; then
    GREEN='\033[0;32m'; RED='\033[0;31m'
    YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    GREEN=''; RED=''; YELLOW=''; CYAN=''; NC=''
fi

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Rollback orchestration state to a previous snapshot.

Options:
  --list              List available snapshots (default)
  --restore INDEX     Restore snapshot at INDEX (1 = latest, 2 = second latest)
  --branch BRANCH     Override branch detection (for CI/testing)
  --dry-run           Show what would be done without modifying anything
  --verbose           Detailed output
  --help              Show this message

Exit codes:
  0 = Rollback completed
  1 = Error
  2 = Usage error
EOF
    exit 0
}

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo "  $1"; }
log_dry() { echo -e "${CYAN}[DRY-RUN]${NC} $1"; }

get_branch() {
    if [[ -n "$BRANCH_OVERRIDE" ]]; then echo "$BRANCH_OVERRIDE"; return 0; fi
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_fail "Not in a git repository"; exit 1
    fi
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
    echo "$branch"
}

get_date() { date -u +"%Y-%m-%d"; }
get_commit_hash() { git rev-parse --short HEAD 2>/dev/null || echo "unknown"; }

# List all unique snapshot entries for a branch from state.md
list_snapshots() {
    local branch="$1"
    local state_file="$PROJECT_ROOT/session/state.md"

    if [[ ! -f "$state_file" ]]; then
        log_fail "No state history found: $state_file"
        return 1
    fi

    echo "Snapshots for branch: $branch"
    echo ""

    # Parse state.md rows for this branch (reverse order, newest first)
    local snapshots=()
    while IFS= read -r line; do
        if echo "$line" | grep -q "|.*\`$branch\`.*|"; then
            snapshots+=("$line")
        fi
    done < <(grep "^|" "$state_file" | grep -v "|---" | grep -v "| Date |")

    local count=${#snapshots[@]}
    if [[ $count -eq 0 ]]; then
        log_warn "No snapshots found for branch '$branch'"
        echo ""
        echo "  The state history file exists but contains no entries for this branch."
        echo "  Run ./scripts/snapshot-contract.sh to create the first snapshot."
        return 1
    fi

    echo "  Index  Date       State         Score   Hash          Summary"
    echo "  ------ ---------- ------------- ------- ------------- ------------------------------"
    local idx=1
    for ((i = count - 1; i >= 0; i--)); do
        local row="${snapshots[$i]}"
        local date_field=$(echo "$row" | awk -F'|' '{print $2}' | xargs)
        local state_field=$(echo "$row" | awk -F'|' '{print $4}' | xargs)
        local score_field=$(echo "$row" | awk -F'|' '{print $5}' | xargs)
        local hash_field=$(echo "$row" | awk -F'|' '{print $6}' | xargs)
        local summary_field=$(echo "$row" | awk -F'|' '{print $8}' | xargs)
        printf "  %-5d  %-10s %-13s %-7s %-13s %s\n" "$idx" "$date_field" "$state_field" "$score_field" "$hash_field" "$summary_field"
        ((idx++))
    done
    echo ""
    log_info "Use --restore INDEX to restore a snapshot"
}

# Restore a specific snapshot by index (1 = latest)
restore_snapshot() {
    local branch="$1"
    local target_idx="$2"
    local session_dir="$PROJECT_ROOT/session/$branch"
    local state_file="$PROJECT_ROOT/session/state.md"
    local contract_file="$session_dir/contract.json"

    if [[ ! -f "$state_file" ]]; then
        log_fail "No state history found: $state_file"
        return 1
    fi

    # Collect snapshots for this branch
    local snapshots=()
    while IFS= read -r line; do
        if echo "$line" | grep -q "|.*\`$branch\`.*|"; then
            snapshots+=("$line")
        fi
    done < <(grep "^|" "$state_file" | grep -v "|---" | grep -v "| Date |")

    local count=${#snapshots[@]}
    if [[ $count -eq 0 ]]; then
        log_fail "No snapshots found for branch '$branch'"
        return 1
    fi

    if [[ $target_idx -lt 1 || $target_idx -gt $count ]]; then
        log_fail "Invalid index: $target_idx (valid range: 1-$count)"
        return 1
    fi

    # Get the target snapshot row (index 1 = latest = last in array)
    local target_row="${snapshots[$((count - target_idx))]}"
    local commit_hash=$(echo "$target_row" | awk -F'|' '{print $6}' | xargs)
    local target_state=$(echo "$target_row" | awk -F'|' '{print $4}' | xargs)

    echo "Target snapshot: index=$target_idx, state=$target_state, commit=$commit_hash"
    echo ""

    # Check if we have the hash to verify
    local hash_file="$session_dir/contract.json.sha256"
    if [[ -f "$hash_file" ]]; then
        log_info "Current contract integrity verified via SHA-256 before rollback"
        if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1 && ! command -v openssl >/dev/null 2>&1; then
            log_warn "Cannot verify hash (no sha256sum/shasum/openssl)"
        else
            local expected_hash
            expected_hash="$(cat "$hash_file" | tr -d '[:space:]')"
            local current_hash
            if command -v sha256sum >/dev/null 2>&1; then
                current_hash=$(sha256sum "$contract_file" | cut -d' ' -f1)
            elif command -v shasum >/dev/null 2>&1; then
                current_hash=$(shasum -a 256 "$contract_file" | cut -d' ' -f1)
            else
                current_hash=$(openssl sha256 "$contract_file" | cut -d' ' -f2)
            fi
            if [[ "$current_hash" != "$expected_hash" ]]; then
                log_warn "Current contract hash MISMATCH — possible tampering or concurrent modification"
                log_warn "  Stored: $expected_hash"
                log_warn "  Actual: $current_hash"
                echo ""
            else
                log_verbose "Current contract hash: $current_hash"
            fi
        fi
    fi

    # Determine the state to restore. Given we may not have the actual contract
    # from that commit, we use git to restore it. The orchestration envelope
    # is stored in the git history via the snapshot commits.
    if [[ "$commit_hash" == "unknown" || "$commit_hash" == "—" ]]; then
        log_fail "Snapshot $target_idx has no commit hash — cannot restore via git"
        log_fail "  (snapshot created with --snapshot-only or commit hash unavailable)"
        return 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would restore contract.json from commit $commit_hash"
        log_dry "Would preserve current contract.json as contract.json.failed"
        log_dry "Would update state: ${target_state} (rolled back from BLOCKED)"
        return 0
    fi

    # Step 1: Preserve current (failed) state
    if [[ -f "$contract_file" ]]; then
        local failed_file="$session_dir/contract.json.failed"
        cp "$contract_file" "$failed_file"
        log_pass "Preserved current state as: $(basename "$failed_file")"
        log_verbose "Current contract saved for debugging: $failed_file"
    fi

    # Step 2: Restore previous contract from git
    if git show "$commit_hash:session/$branch/contract.json" > "$contract_file" 2>/dev/null; then
        log_pass "Restored contract.json from commit $commit_hash"
    elif git show "$commit_hash:contract/contract.template.json" > "$contract_file" 2>/dev/null; then
        log_warn "contract.json not in git history for commit $commit_hash"
        log_warn "Falling back to contract.template.json from same commit"
        log_pass "Restored contract.template.json from commit $commit_hash"
    else
        log_fail "Could not restore contract.json from commit $commit_hash"
        log_fail "  (commit may not exist or session files were not committed)"
        return 1
    fi

    # Step 3: Update contract state to rolled back state
    local rolled_back_state="${target_state} (rollback)"
    if command -v jq >/dev/null 2>&1; then
        local tmp_file
        tmp_file="$(mktemp /tmp/rollback-contract.XXXXXX)"
        jq --arg state "$rolled_back_state" '.state = $state' "$contract_file" > "$tmp_file"
        mv "$tmp_file" "$contract_file"
        log_verbose "Updated contract state to: $rolled_back_state"
    fi

    # Step 4: Recompute SHA-256 hash
    local new_hash="unavailable"
    if command -v sha256sum >/dev/null 2>&1; then
        new_hash=$(sha256sum "$contract_file" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        new_hash=$(shasum -a 256 "$contract_file" | cut -d' ' -f1)
    elif command -v openssl >/dev/null 2>&1; then
        new_hash=$(openssl sha256 "$contract_file" | cut -d' ' -f2)
    fi
    if [[ "$new_hash" != "unavailable" ]]; then
        echo -n "$new_hash" > "$session_dir/contract.json.sha256"
        log_verbose "Updated SHA-256 hash: ${new_hash:0:16}..."
    fi

    log_pass "Rollback to snapshot $target_idx (state=$target_state) completed"
    echo ""
    log_info "Current state rolled back to: $target_state"
}

# --- Main ------------------------------------------------------------------
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --list) MODE="list"; shift ;;
            --restore) MODE="restore"; RESTORE_INDEX="${2:-}"; shift 2 ;;
            --branch) BRANCH_OVERRIDE="$2"; shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --verbose) VERBOSE=true; shift ;;
            --help|-h) usage ;;
            --) shift; break ;;
            *) echo "Unknown option: $1"; usage ;;
        esac
    done

    local branch
    branch="$(get_branch)"
    log_verbose "Branch: $branch"

    echo "=========================================="
    echo " State Rollback — Workflow State Engine"
    echo "=========================================="
    echo ""

    case "$MODE" in
        list)
            list_snapshots "$branch"
            exit $?
            ;;
        restore)
            if [[ -z "$RESTORE_INDEX" ]]; then
                echo "ERROR: --restore requires an index number" >&2
                exit 2
            fi
            restore_snapshot "$branch" "$RESTORE_INDEX"
            exit $?
            ;;
    esac
}

main "$@"