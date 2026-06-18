#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# snapshot-contract.sh — Snapshot the current orchestration contract state
#
# Validates session state and records orchestration state transitions into the
# session/ archive for the current git branch. Idempotent — safe to run multiple times.
# Live state lives at session/{branch}/contract.json (NOT contract/contract.json).
#
# Usage:
#   ./scripts/snapshot-contract.sh               # Default: snapshot current branch
#   ./scripts/snapshot-contract.sh --help         # Show usage
#   ./scripts/snapshot-contract.sh --dry-run      # Show what would be done
#   ./scripts/snapshot-contract.sh --verbose      # Detailed output
#   ./scripts/snapshot-contract.sh --snapshot-only # Only copy files, skip index updates
#   ./scripts/snapshot-contract.sh --branch BRANCH # Override branch name (CI/testing)
#   ./scripts/snapshot-contract.sh --summary TEXT  # Custom summary text
#
# Exit codes:
#   0 — Snapshot created successfully
#   1 — Error (no contract dir, not a git repo, etc.)
#   2 — Usage displayed
#
# Requirements:
#   - bash 4+
#   - git (for branch detection, commit hash)
#   - jq (for extracting state/score from runtime contract.json in session/<branch>)

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Config ──────────────────────────────────────────────────────────────────
VERBOSE=false
DRY_RUN=false
SNAPSHOT_ONLY=false
BRANCH_OVERRIDE=""
SUMMARY_TEXT="Snapshot"
EXIT_CODE=0

# Color output (disable if not a terminal)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    CYAN=''
    NC=''
fi

# ── Help ────────────────────────────────────────────────────────────────────
usage() {
    cat <<'USAGE'
snapshot-contract.sh — Snapshot the current orchestration contract state

SYNOPSIS
    ./scripts/snapshot-contract.sh [OPTIONS]

OPTIONS
    --help            Show this help message and exit
    --dry-run         Show what would be done without modifying anything
    --verbose         Print detailed output for each operation
    --snapshot-only   Only validate session state, skip state.md/index.md updates
    --branch BRANCH   Override branch detection (for CI/testing)
    --summary TEXT    Custom summary text for state.md entry (default: "Snapshot")

BEHAVIOR
    1. Detects current git branch name
    2. Ensures session/{branch}/ exists (initializes from contract templates if needed)
    3. Validates session state at session/{branch}/contract.json
    4. Appends an entry to session/state.md with date, branch, state, score
    5. Updates session/index.md — adds or updates the row for this branch

SOURCE FILES
    session/{branch}/contract.json     (live state — must exist for snapshot)
    contract/contract.template.json    (seed template for new branches)
    contract/state.template.md         (seed template for new branches)

EDGE CASES
    - No session state → initialize from contract templates
    - Not in a git repo → warn and exit 1
    - Branch name contains / → creates nested dirs correctly
    - session/state.md/index.md missing → create with headers
    - Same branch snapshotted multiple times → idempotent

EXIT CODES
    0   Snapshot created successfully
    1   Error (no contract files, not a git repo, etc.)
    2   Usage displayed

EXAMPLES
    ./scripts/snapshot-contract.sh
    ./scripts/snapshot-contract.sh --verbose
    ./scripts/snapshot-contract.sh --dry-run
    ./scripts/snapshot-contract.sh --branch feature/my-feature
    ./scripts/snapshot-contract.sh --summary "Post-review snapshot"
USAGE
    exit 2
}

# ── Logging ─────────────────────────────────────────────────────────────────
log_pass() {
    local msg="$1"
    echo -e "${GREEN}[PASS]${NC} $msg"
}

log_fail() {
    local msg="$1"
    EXIT_CODE=1
    echo -e "${RED}[FAIL]${NC} $msg"
}

log_info() {
    local msg="$1"
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${YELLOW}[INFO]${NC} $msg"
    fi
}

log_verbose() {
    local msg="$1"
    if [[ "$VERBOSE" == true ]]; then
        echo "  :: $msg"
    fi
}

log_dry() {
    local msg="$1"
    echo -e "${CYAN}[DRY-RUN]${NC} $msg"
}

# ── Helpers ─────────────────────────────────────────────────────────────────
# Get the current git branch name, or use override if provided
get_branch() {
    if [[ -n "$BRANCH_OVERRIDE" ]]; then
        echo "$BRANCH_OVERRIDE"
        return 0
    fi

    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_fail "Not in a git repository"
        exit 1
    fi

    local branch
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || git branch --show-current 2>/dev/null || true)"
    if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
        log_fail "Could not detect current branch (detached HEAD?)"
        exit 1
    fi
    echo "$branch"
}

# Get the short commit hash
get_commit_hash() {
    git rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

# Get today's date in YYYY-MM-DD format (macOS/BSD compatible)
get_date() {
    date -u +"%Y-%m-%d"
}

# Determine status label from contract state
derive_status() {
    local state="$1"
    case "$state" in
        BLOCKED|BLOCKED_SCORED)
            echo "Blocked"
            ;;
        COMPLETE|COMPLETE_SCORED|COMPLETE_PASSED)
            echo "Completed"
            ;;
        *)
            echo "In Progress"
            ;;
    esac
}

# ── Core Operations ─────────────────────────────────────────────────────────

# Validate that session state exists for the given branch
# Returns the session contract.json path on success, exits with error on failure.
discover_contract_files() {
    local branch="$1"
    local session_dir="$PROJECT_ROOT/session/$branch"
    local contract_file="$session_dir/contract.json"

    if [[ ! -f "$contract_file" ]]; then
        log_fail "Session contract.json not found: $contract_file — run the script once to initialize"
        return 1
    fi

    # Return the session contract.json as the single source file
    echo "$contract_file"
}

# Validate session state file and log its state
snapshot_files() {
    local branch="$1"
    local session_dir="$PROJECT_ROOT/session"
    local target_dir="$session_dir/$branch"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would validate session state at: $target_dir/contract.json"
        return 0
    fi

    # Create target directory if missing (first run)
    if [[ ! -d "$target_dir" ]]; then
        mkdir -p "$target_dir"
        log_verbose "Created directory: $target_dir"
        log_pass "Directory created: $target_dir"
    fi

    local contract_file="$target_dir/contract.json"
    if [[ ! -f "$contract_file" ]]; then
        log_fail "Session contract.json not found: $contract_file — run without --snapshot-only first to initialize"
        return 1
    fi

    local state
    state="$(jq -r '.state // "unknown"' "$contract_file" 2>/dev/null || echo "unknown")"
    local score
    score="$(jq -r '.score.combined // 0' "$contract_file" 2>/dev/null || echo "0")"
    log_pass "Session state validated: state=$state, score=${score}/100"
}

# Append a new entry to session/state.md
update_state_log() {
    local branch="$1"
    local state="$2"
    local combined_score="$3"
    local commit_hash="$4"
    local summary="$5"

    local state_file="$PROJECT_ROOT/session/state.md"

    # Format the new row
    local date_str
    date_str="$(get_date)"
    local row="| $date_str | \`$branch\` | $state | ${combined_score}/100 | $commit_hash | $summary |"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would append to $state_file:"
        log_dry "  $row"
        return 0
    fi

    # Create file with header if missing
    if [[ ! -f "$state_file" ]]; then
        log_verbose "Creating new state.md: $state_file"
        cat > "$state_file" <<'HEADER'
# Session State History — Workflow State Engine

> Append-only log of all orchestration state transitions. Newest entries are appended at the bottom.
> Each entry captures a snapshot of the envelope at a key lifecycle event.

## Log Format

```
| Date | Branch | State | Score | PR/Commit | Summary |
|------|--------|-------|-------|-----------|---------|
```

## Entries

| Date | Branch | State | Score | PR/Commit | Summary |
|------|--------|-------|-------|-----------|---------|
HEADER
        # Add empty newline after header
        echo "" >> "$state_file"
        log_pass "Created state.md with header template"
    fi

    # Append the new row
    echo "$row" >> "$state_file"
    log_pass "Appended state log entry for branch '$branch'"
    log_verbose "State: $state, Score: ${combined_score}/100, Commit: $commit_hash"
}

# Add or update the branch row in session/index.md
update_branch_index() {
    local branch="$1"
    local state="$2"
    local combined_score="$3"
    local commit_hash="$4"

    local index_file="$PROJECT_ROOT/session/index.md"
    local date_str
    date_str="$(get_date)"
    local status
    status="$(derive_status "$state")"

    if [[ "$DRY_RUN" == true ]]; then
        local row_preview="| \`$branch\` | ✅ | $status | $state | ${combined_score}/100 | — | $date_str |"
        log_dry "Would update index.md with:"
        log_dry "  $row_preview"
        return 0
    fi

    # Create file with header if missing
    if [[ ! -f "$index_file" ]]; then
        log_verbose "Creating new index.md: $index_file"
        cat > "$index_file" <<'HEADER'
# Session Index — Workflow State Engine

> Master index of all orchestration sessions. Each row represents one branch's orchestration lifecycle.
> Sorted by most recent activity.

| Branch | Active | Status | Last State | Score | PR | Last Activity |
|--------|--------|--------|------------|-------|----|--------------|
HEADER
        echo "" >> "$index_file"
        log_pass "Created index.md with header template"
    fi

    # Determine if branch row already exists and extract any existing PR reference
    local existing_pr="—"
    local branch_exists=false
    local old_row=""

    if [[ -f "$index_file" ]]; then
        # Escape branch name for regex (backticks, pipes are literal, forward slash is the main concern)
        local escaped_branch
        escaped_branch="$(echo "$branch" | sed 's/\//\\\//g')"
        local branch_pattern="| \`${escaped_branch}\` |"
        
        # Check if branch row exists and extract PR column
        branch_exists=false
        while IFS= read -r line; do
            if echo "$line" | grep -q "| \`${branch}\` |"; then
                branch_exists=true
                old_row="$line"
                # Extract PR column (7th pipe-delimited field: |Branch|Active|Status|State|Score|PR|Date|)
                existing_pr=$(echo "$line" | awk -F'|' '{print $7}' | xargs)
                break
            fi
        done < "$index_file"
    fi

    # Build the new row
    local new_row="| \`$branch\` | ✅ | $status | $state | ${combined_score}/100 | $existing_pr | $date_str |"

    if [[ "$branch_exists" == true ]]; then
        # Update existing row using awk (portable across macOS/Linux)
        local tmp_file
        tmp_file="$(mktemp /tmp/snapshot-index.XXXXXX)"
        local awk_script
        awk_script='
        BEGIN { branch = ARGV[1]; new_row = ARGV[2]; replaced = 0 }
        {
            if (index($0, "| `" branch "` |") > 0 && replaced == 0) {
                print new_row
                replaced = 1
            } else {
                print $0
            }
        }
        '
        awk -v branch="$branch" -v new_row="$new_row" '
        BEGIN { replaced = 0 }
        {
            if (index($0, "| `" branch "` |") > 0 && replaced == 0) {
                print new_row
                replaced = 1
            } else {
                print $0
            }
        }
        ' "$index_file" > "$tmp_file"
        mv "$tmp_file" "$index_file"
        log_pass "Updated index.md row for branch '$branch'"
        log_verbose "Old: $old_row"
        log_verbose "New: $new_row"
    else
        # Append new row (insert before trailing blank lines)
        local tmp_file
        tmp_file="$(mktemp /tmp/snapshot-index.XXXXXX)"
        # Remove trailing blank lines, append new row, then one blank line
        awk 'BEGIN { RS=""; ORS="\n\n" } { last = $0 } END { print last }' "$index_file" > /dev/null 2>&1 || true
        # Strip trailing blank lines, add new row
        sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$index_file" 2>/dev/null \
            | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}' > "$tmp_file" 2>/dev/null || cat "$index_file" > "$tmp_file"
        echo "$new_row" >> "$tmp_file"
        echo "" >> "$tmp_file"
        mv "$tmp_file" "$index_file"
        log_pass "Appended new index.md row for branch '$branch'"
        log_verbose "Row: $new_row"
    fi
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                usage
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --snapshot-only)
                SNAPSHOT_ONLY=true
                shift
                ;;
            --branch)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --branch requires a value"
                    exit 1
                fi
                BRANCH_OVERRIDE="$2"
                shift 2
                ;;
            --summary)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --summary requires a value"
                    exit 1
                fi
                SUMMARY_TEXT="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done

    echo "=== Snapshot Contract — Workflow State Engine ==="
    echo "Project root: $PROJECT_ROOT"
    echo "Mode: dry-run=$DRY_RUN, verbose=$VERBOSE, snapshot-only=$SNAPSHOT_ONLY"
    echo ""

    # Step 1: Verify git repo and detect branch
    echo "---"
    echo "Step 1: Detect branch"
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_fail "Not in a git repository — cannot snapshot"
        exit 1
    fi
    local branch
    branch="$(get_branch)"
    log_pass "Branch: $branch"
    log_verbose "Commit: $(get_commit_hash)"

    # Step 2: Initialize session state and discover source files
    echo "Step 2: Initialize session state"
    local session_dir="$PROJECT_ROOT/session/$branch"
    local template_file="$PROJECT_ROOT/contract/contract.template.json"
    if [[ ! -f "$template_file" ]]; then
        log_fail "contract/contract.template.json not found -- nothing to snapshot"
        exit 1
    fi

    # Initialize session state if first run for this branch
    if [[ ! -f "$session_dir/contract.json" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would initialize session state in $session_dir"
        else
            mkdir -p "$session_dir"
            cp "$template_file" "$session_dir/contract.json"
            if [[ -f "$PROJECT_ROOT/contract/state.template.md" ]]; then
                cp "$PROJECT_ROOT/contract/state.template.md" "$session_dir/state.md"
                log_verbose "Copied: state.template.md → $session_dir/state.md"
            fi
            log_info "Initialized session state for branch $branch"
        fi
    fi
    log_pass "Session state found at: $session_dir/contract.json"
    # Validate session contract.json exists
    if ! discover_contract_files "$branch" > /dev/null 2>&1; then
        log_fail "Session state not initialized — run without --snapshot-only first"
        exit 1
    fi
    # Step 3: Extract contract metadata
    echo "Step 3: Extract contract metadata"
    local src_json="$PROJECT_ROOT/session/$branch/contract.json"
    if [[ ! -f "$src_json" ]]; then
        src_json="$PROJECT_ROOT/contract/contract.template.json"
    fi
    state="$(jq -r '.state // "unknown"' "$src_json" 2>/dev/null || echo "unknown")"
    combined_score="$(jq -r '.score.combined // 0' "$src_json" 2>/dev/null || echo "0")"
    log_pass "State: $state | Score: ${combined_score}/100"
    log_verbose "Summary: $SUMMARY_TEXT"

    # Step 4: Validate session state
    echo "---"
    echo "Step 4: Validate session state"
    snapshot_files "$branch"

    if [[ $? -ne 0 ]]; then
        log_fail "Failed to validate session state"
        exit 1
    fi

    # Step 5: Update state.md (skip if --snapshot-only or --dry-run failure above)
    if [[ "$SNAPSHOT_ONLY" != true ]]; then
        echo "---"
        echo "Step 5: Update state history (session/state.md)"
        local commit_hash
        commit_hash="$(get_commit_hash)"
        update_state_log "$branch" "$state" "$combined_score" "$commit_hash" "$SUMMARY_TEXT"

        # Step 6: Update index.md
        echo "---"
        echo "Step 6: Update branch index (session/index.md)"
        update_branch_index "$branch" "$state" "$combined_score" "$commit_hash"
    else
        echo "Step 5-6: Skipped (--snapshot-only)"
        log_info "Skipping state.md and index.md updates (--snapshot-only)"
    fi
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}DRY-RUN — no state files were modified.${NC}"
    elif [[ "$EXIT_CODE" -eq 0 ]]; then
        echo -e "${GREEN}Snapshot completed successfully for branch '$branch'.${NC}"
    else
        echo -e "${RED}Snapshot completed with errors.${NC}"
    fi
}

main "$@"