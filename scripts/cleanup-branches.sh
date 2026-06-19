#!/usr/bin/env bash
# scripts/cleanup-branches.sh — G22: Stale Branch Cleanup
# Cleans up stale feature/bugfix branches that are no longer needed.
# Usage: scripts/cleanup-branches.sh [OPTIONS]

set -euo pipefail

# ── Color Constants ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Defaults ─────────────────────────────────────────────────────────────────
DAYS=30
MERGED_ONLY=false
DRY_RUN=false
FORCE=false
CLEAN_SESSIONS=false
EXCLUDE_PATTERNS="main,master,release-"
EXIT_CODE=0

# ── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat <<'USAGE'
usage: cleanup-branches.sh [OPTIONS]

Cleans up stale feature/bugfix branches that are no longer needed.

OPTIONS:
  --dry-run             Preview branches that would be deleted (no actual deletion)
  --days N              Age threshold in days (default: 30)
  --merged-only         Only delete fully-merged branches (skip age check)
  --exclude PATTERNS    Comma-separated branch patterns to keep (default: "main,master,release-")
  --clean-sessions      Also remove session/<branch>/ directories for deleted branches
  --force               Skip confirmation prompt
  --help                Show this help message and exit

EXIT CODES:
  0   Success (or dry-run completed)
  1   Error or no branches to clean

NOTES:
  - Will never delete the currently checked-out branch
  - Will never delete main, master, or branches matching --exclude patterns
  - Uses both git branch merge detection and last-commit age
  - Without --merged-only: deletes branches with no commits in N days
  - With --merged-only: deletes branches fully merged into main

EXAMPLES:
  scripts/cleanup-branches.sh --dry-run
  scripts/cleanup-branches.sh --days 60 --force
  scripts/cleanup-branches.sh --merged-only --dry-run
  scripts/cleanup-branches.sh --merged-only --clean-sessions --force
  scripts/cleanup-branches.sh --exclude "main,develop,release-*,hotfix-*"
USAGE
    exit 2
}

# ── Logging Functions ───────────────────────────────────────────────────────

log_pass() {
    local msg="$1"
    echo -e "${GREEN}[PASS]${NC} $msg"
}

log_fail() {
    local msg="$1"
    echo -e "${RED}[FAIL]${NC} $msg" >&2
    EXIT_CODE=1
}

log_info() {
    local msg="$1"
    echo -e "${YELLOW}[INFO]${NC} $msg"
}

log_dry() {
    local msg="$1"
    echo -e "${BLUE}[DRY-RUN]${NC} $msg"
}

log_section() {
    echo ""
    echo -e "${CYAN}■${NC} $1"
}

log_verbose() {
    local msg="$1"
    echo -e "  ${NC}→ $msg"
}

# ── Glob Match ──────────────────────────────────────────────────────────────

glob_match() {
    local str="$1"
    local pattern="$2"
    # shellcheck disable=SC2053
    [[ "$str" == $pattern ]]
}

# ── Branch Exclusion Check ──────────────────────────────────────────────────

is_excluded() {
    local branch="$1"
    IFS=',' read -ra patterns <<< "$EXCLUDE_PATTERNS"
    for pattern in "${patterns[@]}"; do
        pattern="${pattern// /}"
        if glob_match "$branch" "$pattern"; then
            return 0
        fi
    done
    return 1
}

# ── Get Current Branch ──────────────────────────────────────────────────────

get_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD"
}

# ── Get Branches Merged into Main ──────────────────────────────────────────

get_merged_branches() {
    local main_branch=""
    for candidate in "main" "master"; do
        if git show-ref --verify --quiet "refs/heads/${candidate}"; then
            main_branch="$candidate"
            break
        fi
    done

    if [[ -z "$main_branch" ]]; then
        log_fail "Cannot determine main branch (checked: main, master)"
        return 1
    fi

    git branch --merged "$main_branch" | grep -v "^\*" | grep -v "^  ${main_branch}$" | sed 's/^  //' | sed 's/^ *//'
}

# ── Get Branches with No Recent Commits ─────────────────────────────────────

get_stale_branches() {
    local cutoff_seconds
    cutoff_seconds=$(date -v "-${DAYS}d" +%s 2>/dev/null || date --date="${DAYS} days ago" +%s 2>/dev/null || echo "")

    if [[ -z "$cutoff_seconds" ]]; then
        log_fail "Cannot compute cutoff date (check 'date' compatibility)"
        return 1
    fi

    git for-each-ref --format='%(refname:short) %(committerdate:unix)' refs/heads/ | while read -r branch ts; do
        if is_excluded "$branch"; then
            continue
        fi
        if [[ "$ts" -le "$cutoff_seconds" ]]; then
            echo "$branch"
        fi
    done
}

# ── Delete Branch ───────────────────────────────────────────────────────────

delete_branch() {
    local branch="$1"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would delete branch: ${branch}"
        return 0
    fi

    if git branch -D "$branch" 2>/dev/null; then
        log_pass "Deleted branch: ${branch}"
    else
        log_fail "Failed to delete branch: ${branch}"
    fi
}

# ── Clean Session Directory ────────────────────────────────────────────────

clean_session_dir() {
    local branch="$1"
    local session_dir="session/${branch}"

    if [[ ! -d "$session_dir" ]]; then
        log_verbose "No session directory for branch: ${branch}"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would remove session directory: ${session_dir}"
        return 0
    fi

    if rm -rf "$session_dir"; then
        log_pass "Removed session directory: ${session_dir}"
    else
        log_fail "Failed to remove session directory: ${session_dir}"
    fi
}

# ── Argument Parsing ────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --days)
            shift
            if [[ $# -eq 0 ]]; then
                echo -e "${RED}ERROR: --days requires a number${NC}" >&2
                exit 1
            fi
            DAYS="$1"
            shift
            ;;
        --merged-only)
            MERGED_ONLY=true
            shift
            ;;
        --exclude)
            shift
            if [[ $# -eq 0 ]]; then
                echo -e "${RED}ERROR: --exclude requires a comma-separated list${NC}" >&2
                exit 1
            fi
            EXCLUDE_PATTERNS="$1"
            shift
            ;;
        --clean-sessions)
            CLEAN_SESSIONS=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2
            usage
            ;;
    esac
done

# ── Validation ──────────────────────────────────────────────────────────────

if ! git rev-parse --git-dir &>/dev/null; then
    log_fail "Not inside a Git repository"
    exit 1
fi

if [[ ! "$DAYS" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}ERROR: --days must be a positive integer${NC}" >&2
    exit 1
fi

# ── Main ────────────────────────────────────────────────────────────────────

log_section "Stale Branch Cleanup"
echo "  Mode:        $([[ "$MERGED_ONLY" == true ]] && echo "merged-only" || echo "age-based (${DAYS} days)")"
echo "  Dry run:     $DRY_RUN"
echo "  Clean sess:  $CLEAN_SESSIONS"
echo "  Force:       $FORCE"
echo "  Exclude:     ${EXCLUDE_PATTERNS}"

CURRENT_BRANCH=$(get_current_branch)
log_verbose "Current branch: ${CURRENT_BRANCH}"

MAIN_BRANCH="main"
if ! git show-ref --verify --quiet "refs/heads/main"; then
    if git show-ref --verify --quiet "refs/heads/master"; then
        MAIN_BRANCH="master"
    else
        MAIN_BRANCH=""
    fi
fi

CANDIDATES=()

if [[ "$MERGED_ONLY" == true ]]; then
    log_section "Finding fully-merged branches"
    if [[ -z "$MAIN_BRANCH" ]]; then
        log_fail "Cannot find main/master branch for merge detection"
        exit 1
    fi
    log_verbose "Using main branch: ${MAIN_BRANCH}"

    while IFS= read -r branch; do
        CANDIDATES+=("$branch")
    done < <(get_merged_branches || true)
else
    log_section "Finding stale branches (no commits in ${DAYS} days)"
    while IFS= read -r branch; do
        CANDIDATES+=("$branch")
    done < <(get_stale_branches || true)
fi

FILTERED=()
for branch in "${CANDIDATES[@]}"; do
    if [[ -z "$branch" ]]; then
        continue
    fi
    if is_excluded "$branch"; then
        log_verbose "Excluded (pattern match): ${branch}"
        continue
    fi
    if [[ "$branch" == "$CURRENT_BRANCH" ]]; then
        log_verbose "Skipping current branch: ${branch}"
        continue
    fi
    if [[ -n "$MAIN_BRANCH" && "$branch" == "$MAIN_BRANCH" ]]; then
        log_verbose "Skipping main branch: ${branch}"
        continue
    fi
    FILTERED+=("$branch")
done

if [[ ${#FILTERED[@]} -eq 0 ]]; then
    log_info "No branches to clean"
    exit 0
fi

log_section "Branches to clean (${#FILTERED[@]} total)"
for branch in "${FILTERED[@]}"; do
    echo "  - ${branch}"
done

if [[ "$FORCE" != true && "$DRY_RUN" != true ]]; then
    echo ""
    read -p "Delete ${#FILTERED[@]} branch(es)? [y/N] " -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Cancelled by user"
        exit 0
    fi
fi

for branch in "${FILTERED[@]}"; do
    delete_branch "$branch"
done

if [[ "$CLEAN_SESSIONS" == true ]]; then
    log_section "Cleaning session directories"
    for branch in "${FILTERED[@]}"; do
        clean_session_dir "$branch"
    done
fi

log_section "Summary"
if [[ "$DRY_RUN" == true ]]; then
    log_dry "Would delete ${#FILTERED[@]} branch(es)"
else
    log_pass "Cleaned ${#FILTERED[@]} branch(es)"
fi

exit $EXIT_CODE