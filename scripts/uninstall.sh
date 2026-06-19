#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# uninstall.sh — Uninstall the Workflow State Engine toolkit
#
# Removes .opencode/ symlinks created by install.sh and optionally
# removes session/ data. Asks for confirmation before destructive operations.
#
# Usage:
#   ./scripts/uninstall.sh                  # Interactive uninstall with prompts
#   ./scripts/uninstall.sh --help           # Show usage
#   ./scripts/uninstall.sh --verbose        # Detailed output
#   ./scripts/uninstall.sh --dry-run        # Show what would be done
#   ./scripts/uninstall.sh --force          # Skip all confirmation prompts
#
# Exit codes:
#   0 — Uninstall successful
#   1 — Partial success (some operations skipped or warnings)
#   2 — Error
#
# This script is idempotent — safe to run multiple times.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Config ──────────────────────────────────────────────────────────────────
VERBOSE=false
DRY_RUN=false
FORCE=false
EXIT_CODE=0
REMOVED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0
REMOVE_SESSION=false

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
uninstall.sh — Uninstall the Workflow State Engine toolkit

SYNOPSIS
    ./scripts/uninstall.sh [OPTIONS]

OPTIONS
    --help       Show this help message and exit
    --verbose    Print detailed output for each operation
    --dry-run    Show what would be done without modifying anything
    --force      Skip all confirmation prompts (non-interactive)

WHAT IT DOES
  1. Removes .opencode/ symlinks created by install.sh
  2. Asks whether to keep or remove session/ directory data

SYMLINKS REMOVED
    .opencode/agents
    .opencode/skills
    .opencode/rules
    .opencode/orchestration
    .opencode/planning
    .opencode/reports
    .opencode/usage
    .opencode/config
    .opencode/AGENTS.md

EXIT CODES
    0   Uninstall successful
    1   Partial success (some operations skipped or warnings)
    2   Error

EXAMPLES
    ./scripts/uninstall.sh                  # Interactive (prompts for confirmation)
    ./scripts/uninstall.sh --force          # Non-interactive
    ./scripts/uninstall.sh --dry-run        # Preview only
    ./scripts/uninstall.sh --verbose        # Detailed output
USAGE
    exit 0
}

# ── Logging ─────────────────────────────────────────────────────────────────
log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    [[ "$EXIT_CODE" -lt 2 ]] && EXIT_CODE=2
    FAILED_COUNT=$((FAILED_COUNT + 1))
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_verbose() {
    [[ "$VERBOSE" == true ]] && echo "  $1"
}

log_dry() {
    [[ "$DRY_RUN" == true ]] && echo -e "${CYAN}[DRY-RUN]${NC} $1"
}

# ── Confirmation prompt ────────────────────────────────────────────────────
confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [[ "$FORCE" == true ]]; then
        return 0
    fi

    local yes_no
    if [[ "$default" == "y" ]]; then
        yes_no="Y/n"
    else
        yes_no="y/N"
    fi

    local response
    echo ""
    echo -e "${YELLOW}?${NC} $prompt [$yes_no] "
    read -r response

    if [[ -z "$response" ]]; then
        response="$default"
    fi

    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ── Step 1: Remove .opencode/ symlinks ─────────────────────────────────────
remove_symlinks() {
    echo "---"
    echo "Step 1: Remove .opencode/ symlinks"

    # Define symlinks to remove: link_name -> target (for display only)
    declare -A SYMLINKS=(
        [".opencode/agents"]="../agents"
        [".opencode/skills"]="../skills"
        [".opencode/rules"]="../rules"
        [".opencode/orchestration"]="../contract"
        [".opencode/planning"]="../doc/planning"
        [".opencode/reports"]="../doc/reports"
        [".opencode/usage"]="../usage"
        [".opencode/config"]="../config"
        [".opencode/AGENTS.md"]="../agent.md"
    )

    for link_name in "${!SYMLINKS[@]}"; do
        local link_path="$PROJECT_DIR/$link_name"

        if [[ ! -L "$link_path" ]] && [[ ! -e "$link_path" ]]; then
            log_verbose "$link_name not found — skipping"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi

        # Warn if it's a real file/dir (not a symlink)
        if [[ ! -L "$link_path" ]] && [[ -e "$link_path" ]]; then
            log_warn "$link_name exists but is NOT a symlink — will not remove"
            SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
            continue
        fi

        local target
        target="$(readlink "$link_path" 2>/dev/null || echo "unknown")"

        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would remove symlink: $link_name -> $target"
            REMOVED_COUNT=$((REMOVED_COUNT + 1))
            continue
        fi

        if rm -f "$link_path" 2>/dev/null; then
            log_pass "Removed symlink: $link_name -> $target"
            REMOVED_COUNT=$((REMOVED_COUNT + 1))
        else
            log_fail "Failed to remove: $link_name"
        fi
    done

    # Remove .opencode/AGENTS.md separately (it's a symlink to agent.md)
    local agents_link="$PROJECT_DIR/.opencode/AGENTS.md"
    if [[ -L "$agents_link" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would remove symlink: .opencode/AGENTS.md -> $(readlink "$agents_link")"
            REMOVED_COUNT=$((REMOVED_COUNT + 1))
        else
            if rm -f "$agents_link" 2>/dev/null; then
                log_pass "Removed symlink: .opencode/AGENTS.md"
                REMOVED_COUNT=$((REMOVED_COUNT + 1))
            else
                log_fail "Failed to remove: .opencode/AGENTS.md"
            fi
        fi
    else
        log_verbose ".opencode/AGENTS.md not found or not a symlink — skipping"
    fi

    # Clean up empty .opencode/ directory if all symlinks are gone
    if [[ "$DRY_RUN" != true ]]; then
        if [[ -d "$PROJECT_DIR/.opencode" ]]; then
            local remaining
            remaining="$(find "$PROJECT_DIR/.opencode" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"
            if [[ "$remaining" -eq 0 ]]; then
                rmdir "$PROJECT_DIR/.opencode" 2>/dev/null || true
                log_pass "Removed empty directory: .opencode/"
            elif [[ "$remaining" -eq 1 ]] && [[ -d "$PROJECT_DIR/.opencode/node_modules" ]]; then
                # .opencode/node_modules is a real directory, leave it
                log_verbose ".opencode/node_modules/ found — keeping .opencode/ directory"
            else
                log_verbose "$remaining item(s) remaining in .opencode/ — directory preserved"
            fi
        fi
    fi

    if [[ "$REMOVED_COUNT" -gt 0 ]]; then
        log_pass "Removed $REMOVED_COUNT symlink(s)"
    fi
    if [[ "$SKIPPED_COUNT" -gt 0 ]]; then
        log_info "$SKIPPED_COUNT item(s) skipped (already missing or not a symlink)"
    fi
}

# ── Step 2: Handle session/ directory ──────────────────────────────────────
handle_session_data() {
    echo "---"
    echo "Step 2: Session data"

    local session_dir="$PROJECT_DIR/session"

    if [[ ! -d "$session_dir" ]]; then
        log_info "session/ directory not found — nothing to handle"
        return 0
    fi

    # Count session data
    local branch_count
    branch_count="$(find "$session_dir" -maxdepth 2 -type d 2>/dev/null | wc -l | tr -d ' ')"
    local file_count
    file_count="$(find "$session_dir" -type f 2>/dev/null | wc -l | tr -d ' ')"
    local size
    size="$(du -sh "$session_dir" 2>/dev/null | cut -f1 || echo "unknown")"

    log_info "session/ directory found: $branch_count item(s), $file_count file(s), $size"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would prompt to keep or remove session/ data"
        return 0
    fi

    # Ask user what to do
    if confirm "Keep session/ directory data? (say No to remove)" "y"; then
        log_pass "Keeping session/ data"
        REMOVE_SESSION=false
    else
        if confirm "Are you sure you want to DELETE all session data? This includes contract history for all branches." "n"; then
            REMOVE_SESSION=true
        else
            log_info "Session data preservation confirmed — keeping session/"
            REMOVE_SESSION=false
        fi
    fi

    if [[ "$REMOVE_SESSION" == true ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would remove session/ directory"
            return 0
        fi

        if rm -rf "$session_dir" 2>/dev/null; then
            log_pass "Removed session/ directory and all data"
            REMOVED_COUNT=$((REMOVED_COUNT + 1))
        else
            log_fail "Failed to remove session/ directory"
        fi
    fi
}

# ── Summary ─────────────────────────────────────────────────────────────────
print_summary() {
    echo "===="
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}DRY-RUN — no files were modified.${NC}"
        echo "  Would remove: $REMOVED_COUNT symlinks"
        if [[ "$REMOVE_SESSION" == true ]]; then
            echo "  Would remove: session/ directory"
        fi
        return
    fi

    if [[ "$EXIT_CODE" -eq 0 ]]; then
        echo -e "${GREEN}Uninstall completed successfully.${NC}"
        echo ""
        if [[ "$REMOVED_COUNT" -gt 0 ]]; then
            echo "  Removed $REMOVED_COUNT symlinks"
        fi
        if [[ "$REMOVE_SESSION" == true ]]; then
            echo "  Removed session/ directory"
        else
            echo "  Preserved session/ directory"
        fi
        if [[ "$SKIPPED_COUNT" -gt 0 ]]; then
            echo "  $SKIPPED_COUNT items skipped"
        fi
        echo ""
        echo "Manual cleanup (if desired):"
        echo "  - Check for any remaining toolkit files in .opencode/"
        echo "  - Remove contract/ directory if this project is no longer needed"
    elif [[ "$EXIT_CODE" -eq 1 ]]; then
        echo -e "${YELLOW}Uninstall completed with warnings.${NC}"
    else
        echo -e "${RED}Uninstall encountered errors.${NC}"
        echo "Review the errors above, fix any issues, and re-run if needed."
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
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            *)
                echo -e "${RED}Unknown option:${NC} $1" >&2
                echo "Try '$(basename "$0") --help' for more information." >&2
                exit 2
                ;;
        esac
    done

    echo "=== Uninstall — Workflow State Engine ==="
    echo "Project root: $PROJECT_DIR"
    echo "Mode: verbose=$VERBOSE, dry-run=$DRY_RUN, force=$FORCE"
    echo ""

    if [[ "$DRY_RUN" != true ]]; then
        # Confirm uninstall (unless --force or --dry-run)
        if ! confirm "This will remove the toolkit symlinks. Continue?" "n"; then
            echo ""
            echo -e "${YELLOW}Uninstall cancelled by user.${NC}"
            exit 0
        fi
    fi

    # Run uninstall steps
    remove_symlinks || true
    handle_session_data || true

    # Determine final exit code
    if [[ "$FAILED_COUNT" -gt 0 ]]; then
        EXIT_CODE=2
    elif [[ "$SKIPPED_COUNT" -gt 0 ]] || [[ "$REMOVED_COUNT" -eq 0 ]]; then
        EXIT_CODE=1
    else
        EXIT_CODE=0
    fi

    echo ""
    print_summary

    exit "$EXIT_CODE"
}

main "$@"