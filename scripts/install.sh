#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# install.sh — Install the Workflow State Engine toolkit
#
# Sets up .opencode/ symlinks, initializes session state from contract templates,
# verifies dependencies, and validates the installation.
#
# Usage:
#   ./scripts/install.sh                    # Run installation
#   ./scripts/install.sh --help             # Show usage
#   ./scripts/install.sh --verbose          # Detailed output
#   ./scripts/install.sh --dry-run          # Show what would be done
#
# Exit codes:
#   0 — Installation successful
#   1 — Partial success (some warnings)
#   2 — Error (requirements not met)
#
# Requirements:
#   - bash 4+
#   - git (in a git repo)
#   - jq (recommended for JSON operations)
#   - bc (for scoring calculations)
#   - python3 (for JSON validation fallsback)
#
# This script is idempotent — safe to run multiple times.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Config ──────────────────────────────────────────────────────────────────
VERBOSE=false
DRY_RUN=false
EXIT_CODE=0
WARNINGS=0

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
install.sh — Install the Workflow State Engine toolkit

SYNOPSIS
    ./scripts/install.sh [OPTIONS]

OPTIONS
    --help       Show this help message and exit
    --verbose    Print detailed output for each operation
    --dry-run    Show what would be done without modifying anything

WHAT IT DOES
  1. Checks required dependencies: jq, bc, python3, git
  2. Creates .opencode/ symlinks pointing to root-level source directories
  3. Creates session/ directory structure if missing
  4. Copies contract/contract.template.json → session/{branch}/contract.json
  5. Copies contract/state.template.md   → session/{branch}/state.md
  6. Validates installation via check-conventions.sh

SYMLINKS CREATED
    .opencode/agents        -> ../agents
    .opencode/skills        -> ../skills
    .opencode/rules         -> ../rules
    .opencode/orchestration -> ../contract
    .opencode/planning      -> ../doc/planning
    .opencode/reports       -> ../doc/reports
    .opencode/usage         -> ../usage
    .opencode/config        -> ../config
    .opencode/AGENTS.md     -> ../agent.md

EXIT CODES
    0   Installation successful
    1   Partial success (some warnings)
    2   Error (requirements not met)

EXAMPLES
    ./scripts/install.sh
    ./scripts/install.sh --verbose
    ./scripts/install.sh --dry-run
USAGE
    exit 0
}

# ── Logging ─────────────────────────────────────────────────────────────────
log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    EXIT_CODE=2
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warn() {
    WARNINGS=$((WARNINGS + 1))
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

# ── Step 1: Check dependencies ──────────────────────────────────────────────
check_dependencies() {
    echo "---"
    echo "Step 1: Check required dependencies"
    local deps_ok=true
    local missing_deps=()

    # git (mandatory)
    if ! command -v git &>/dev/null; then
        missing_deps+=("git")
        deps_ok=false
    fi

    # jq (recommended)
    if ! command -v jq &>/dev/null; then
        log_warn "jq not found — JSON parsing will use python3 fallback"
    fi

    # bc (recommended)
    if ! command -v bc &>/dev/null; then
        log_warn "bc not found — scoring calculations will use python3 fallback"
    fi

    # python3 (recommended)
    if ! command -v python3 &>/dev/null; then
        log_warn "python3 not found — JSON validation and fallback arithmetic unavailable"
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        local dep_list
        dep_list="$(printf "%s, " "${missing_deps[@]}")"
        dep_list="${dep_list%, }"
        log_fail "Missing mandatory dependencies: $dep_list"
        return 1
    fi

    # Verify we're in a git repo
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_fail "Not in a git repository — run this script from the project root"
        return 1
    fi

    log_pass "All mandatory dependencies satisfied"
    log_verbose "  git: $(git --version 2>/dev/null || echo 'found')"
    log_verbose "  jq:  $(jq --version 2>/dev/null || echo 'not found (optional)')"
    log_verbose "  bc:  $(bc --version 2>/dev/null | head -1 || echo 'not found (optional)')"
    log_verbose "  python3: $(python3 --version 2>/dev/null || echo 'not found (optional)')"
    return 0
}

# ── Step 2: Create .opencode/ symlinks ──────────────────────────────────────
create_symlinks() {
    echo "---"
    echo "Step 2: Create .opencode/ symlinks"
    local violations=0

    # Define symlinks: link_name -> target (relative from PROJECT_DIR)
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

    # Ensure .opencode/ directory exists
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would create .opencode/ directory if missing"
    else
        if [[ ! -d "$PROJECT_DIR/.opencode" ]]; then
            mkdir -p "$PROJECT_DIR/.opencode"
            log_verbose "Created directory: .opencode/"
        fi
    fi

    for target_dest in "${!SYMLINKS[@]}"; do
        local link_path="$PROJECT_DIR/$target_dest"
        local link_target="${SYMLINKS[$target_dest]}"

        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would create symlink: $target_dest -> $link_target"
            continue
        fi

        # Remove existing symlink or file
        if [[ -L "$link_path" ]] || [[ -e "$link_path" ]]; then
            rm -f "$link_path"
            log_verbose "Removed existing: $target_dest"
        fi

        # Create parent directory for symlink if needed
        local parent_dir
        parent_dir="$(dirname "$link_path")"
        if [[ ! -d "$parent_dir" ]]; then
            mkdir -p "$parent_dir"
            log_verbose "Created parent directory: $parent_dir"
        fi

        # Create the symlink
        if ln -sfn "$link_target" "$link_path" 2>/dev/null; then
            log_pass "Symlink created: $target_dest -> $link_target"
            log_verbose "  $(ls -la "$link_path")"
        else
            log_fail "Failed to create symlink: $target_dest -> $link_target"
            violations=$((violations + 1))
        fi
    done

    if [[ "$violations" -eq 0 ]]; then
        log_pass "All .opencode/ symlinks created successfully"
    else
        log_fail "$violations symlink(s) failed to create"
    fi

    return "$violations"
}

# ── Step 3: Create session/ directory structure ─────────────────────────────
create_session_dirs() {
    echo "---"
    echo "Step 3: Create session/ directory structure"
    local violations=0

    local session_dir="$PROJECT_DIR/session"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would create session/ directory if missing"
    else
        if [[ ! -d "$session_dir" ]]; then
            mkdir -p "$session_dir"
            log_pass "Created: session/"
        else
            log_pass "session/ already exists"
        fi
    fi

    # Create session/state.md if missing
    local state_md="$session_dir/state.md"
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would create session/state.md if missing"
    else
        if [[ ! -f "$state_md" ]]; then
            cat > "$state_md" <<'HEADER'
# Session State History — Workflow State Engine
> Append-only log of all orchestration state transitions. Newest entries are appended at the bottom.
> Each entry captures a snapshot of the envelope at a key lifecycle event.

| Date | Branch | State | Score | PR/Commit | Summary |
|------|--------|-------|-------|-----------|---------|
HEADER
            log_pass "Created: session/state.md"
        else
            log_verbose "session/state.md already exists"
        fi
    fi

    # Create session/index.md if missing
    local index_md="$session_dir/index.md"
    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would create session/index.md if missing"
    else
        if [[ ! -f "$index_md" ]]; then
            cat > "$index_md" <<'HEADER'
# Session Index — Workflow State Engine
> Master index of all orchestration sessions. Each row represents one branch's orchestration lifecycle.
> Sorted by most recent activity.

| Branch | Active | Status | Last State | Score | PR | Last Activity |
|--------|--------|--------|------------|-------|----|---------------|
HEADER
            log_pass "Created: session/index.md"
        else
            log_verbose "session/index.md already exists"
        fi
    fi

    # Create current branch snapshot directory
    local branch
    branch="$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "unknown")"
    local branch_dir="$session_dir/$branch"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would create branch directory: session/$branch/"
    else
        if [[ ! -d "$branch_dir" ]]; then
            mkdir -p "$branch_dir"
            log_pass "Created: session/$branch/"
        else
            log_verbose "session/$branch/ already exists"
        fi
    fi

    log_pass "Session directory structure ready"
    return "$violations"
}

# ── Step 4: Initialize session state from contract templates ────────────────
initialize_session_state() {
    echo "---"
    echo "Step 4: Initialize session state from contract templates"
    local violations=0

    local branch
    branch="$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "unknown")"
    local branch_dir="$PROJECT_DIR/session/$branch"
    local template_contract="$PROJECT_DIR/contract/contract.template.json"
    local template_state="$PROJECT_DIR/contract/state.template.md"

    # Check template files exist
    if [[ ! -f "$template_contract" ]]; then
        log_fail "Template not found: contract/contract.template.json"
        return 1
    fi

    if [[ ! -f "$template_state" ]]; then
        log_warn "Template not found: contract/state.template.md — will create minimal state.md"
    fi

    # Copy contract.json if it doesn't exist
    local contract_file="$branch_dir/contract.json"
    if [[ ! -f "$contract_file" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would copy: contract/contract.template.json -> session/$branch/contract.json"
        else
            cp "$template_contract" "$contract_file"
            log_pass "Initialized: session/$branch/contract.json"
            log_verbose "  Source: contract/contract.template.json"
        fi
    else
        log_pass "session/$branch/contract.json already exists — skipping"
    fi

    # Copy state.md if it doesn't exist
    local state_file="$branch_dir/state.md"
    if [[ ! -f "$state_file" ]]; then
        if [[ -f "$template_state" ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "Would copy: contract/state.template.md -> session/$branch/state.md"
            else
                cp "$template_state" "$state_file"
                log_pass "Initialized: session/$branch/state.md"
                log_verbose "  Source: contract/state.template.md"
            fi
        else
            if [[ "$DRY_RUN" == true ]]; then
                log_dry "Would create minimal session/$branch/state.md"
            else
                cat > "$state_file" <<'STATE'
# Session State — Workflow State Engine

## Current Focus
<!-- Describe the current focus of work -->

## Last Action
<!-- What was done last -->

## Known Blockers
<!-- List any blockers -->
STATE
                log_pass "Created minimal: session/$branch/state.md"
            fi
        fi
    else
        log_verbose "session/$branch/state.md already exists — skipping"
    fi

    # Copy supporting files if they exist
    local schema_source="$PROJECT_DIR/contract/contract.schema.json"
    local schema_target="$branch_dir/contract.schema.json"
    if [[ -f "$schema_source" ]] && [[ ! -f "$schema_target" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would copy: contract/contract.schema.json -> session/$branch/contract.schema.json"
        else
            cp "$schema_source" "$schema_target"
            log_pass "Copied: contract/contract.schema.json -> session/$branch/"
        fi
    fi

    local superpowers_source="$PROJECT_DIR/contract/superpowers-contract.json"
    local superpowers_target="$branch_dir/superpowers-contract.json"
    if [[ -f "$superpowers_source" ]] && [[ ! -f "$superpowers_target" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would copy: contract/superpowers-contract.json -> session/$branch/superpowers-contract.json"
        else
            cp "$superpowers_source" "$superpowers_target"
            log_pass "Copied: contract/superpowers-contract.json -> session/$branch/"
        fi
    fi

    return "$violations"
}

# ── Step 5: Validate installation ──────────────────────────────────────────
validate_installation() {
    echo "---"
    echo "Step 5: Validate installation"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would run: scripts/check-conventions.sh --skip-old-branches"
        return 0
    fi

    local checker="$PROJECT_DIR/scripts/check-conventions.sh"
    if [[ ! -f "$checker" ]]; then
        log_warn "check-conventions.sh not found — skipping validation"
        return 0
    fi

    log_info "Running check-conventions.sh to validate installation..."

    # Run with --verbose if we're in verbose mode
    local check_args=("--skip-old-branches")
    [[ "$VERBOSE" == true ]] && check_args+=("--verbose")

    if "$checker" "${check_args[@]}"; then
        log_pass "Installation validated — all conventions pass"
        return 0
    else
        log_warn "check-conventions.sh reported violations — review warnings above"
        return 0  # Don't fail installation for warnings
    fi
}

# ── Summary ─────────────────────────────────────────────────────────────────
print_summary() {
    echo "===="
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}DRY-RUN — no files were modified.${NC}"
        return
    fi

    if [[ "$EXIT_CODE" -eq 0 ]]; then
        echo -e "${GREEN}Installation completed successfully.${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Review session/$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "unknown")/contract.json"
        echo "  2. Run  ./scripts/validate-contract.sh  to verify contract integrity"
        echo "  3. Run  ./scripts/drift-detect.sh        to check for drift"
        echo "  4. The toolkit is ready for orchestration sessions"
    elif [[ "$EXIT_CODE" -eq 1 ]]; then
        echo -e "${YELLOW}Installation completed with $WARNINGS warning(s).${NC}"
        echo "Review the warnings above and address any issues."
    else
        echo -e "${RED}Installation failed.${NC}"
        echo "Review the errors above, fix the underlying issues, and re-run."
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
            *)
                echo -e "${RED}Unknown option:${NC} $1" >&2
                echo "Try '$(basename "$0") --help' for more information." >&2
                exit 2
                ;;
        esac
    done

    echo "=== Install — Workflow State Engine ==="
    echo "Project root: $PROJECT_DIR"
    echo "Mode: verbose=$VERBOSE, dry-run=$DRY_RUN"
    echo ""

    # Run installation steps
    check_dependencies || exit 2
    create_symlinks || true  # Don't exit on symlink warnings
    create_session_dirs || true
    initialize_session_state || true
    validate_installation || true

    # Determine final exit code
    if [[ "$EXIT_CODE" -eq 2 ]]; then
        # Fatal error occurred
        :
    elif [[ "$WARNINGS" -gt 0 ]]; then
        EXIT_CODE=1
    else
        EXIT_CODE=0
    fi

    echo ""
    print_summary

    exit "$EXIT_CODE"
}

main "$@"