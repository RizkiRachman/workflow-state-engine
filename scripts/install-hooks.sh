#!/usr/bin/env bash
# Git hooks installer for workflow-state-engine
# Usage: scripts/install-hooks.sh [--pre-commit-only|--post-commit-only|--uninstall|--status|--dry-run|--help]
set -euo pipefail

# ── Color helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

HOOKS_DIR=".githooks"
REQUIRED_HOOKS=("pre-commit" "post-commit")

# ── Help ─────────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${CYAN}install-hooks.sh${NC} — Git hook installer for workflow-state-engine

${CYAN}Usage:${NC}
    $(basename "$0")                         Install all hooks
    $(basename "$0") --pre-commit-only       Install only pre-commit
    $(basename "$0") --post-commit-only      Install only post-commit
    $(basename "$0") --uninstall             Remove hooks (reset to default)
    $(basename "$0") --status                Show hook installation status
    $(basename "$0") --dry-run               Preview installation without changes
    $(basename "$0") --help                  Show this help

${CYAN}What it does:${NC}
  - Sets git core.hooksPath to ${HOOKS_DIR}/
  - Ensures hooks are executable (chmod +x)
  - On --uninstall: unsets core.hooksPath (reverts to .git/hooks/)
EOF
    exit 0
}

# ── Helpers ───────────────────────────────────────────────────────────────────
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
action(){ echo -e "${CYAN}[DRY-RUN]${NC} $*"; }

check_git_repo() {
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        error "Not in a git repository."
        exit 1
    fi
}

check_jq() {
    if ! command -v jq &>/dev/null; then
        warn "jq not found — contract validation step skipped."
    fi
}

get_hooks_path() {
    git config --get core.hooksPath 2>/dev/null || echo ""
}

set_hooks_path() {
    local target="$1"
    git config core.hooksPath "$target"
    info "core.hooksPath set to '$target'"
}

unset_hooks_path() {
    git config --unset core.hooksPath 2>/dev/null || true
    info "core.hooksPath unset (reverted to default .git/hooks/)"
}

install_hook() {
    local hook="$1"
    local src="${HOOKS_DIR}/${hook}"

    if [[ ! -f "$src" ]]; then
        warn "Hook file '${src}' not found — skipping."
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        action "Would chmod +x ${src}"
        return
    fi

    chmod +x "$src"
    info "Installed hook: ${src}"
}

install_all() {
    local current
    current=$(get_hooks_path)

    if [[ "$current" == "${HOOKS_DIR}/" ]]; then
        info "Hooks already installed at ${HOOKS_DIR}/"
        # Still ensure executability
        for hook in "${REQUIRED_HOOKS[@]}"; do
            install_hook "$hook"
        done
        exit 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        action "Would set core.hooksPath to ${HOOKS_DIR}/"
        for hook in "${REQUIRED_HOOKS[@]}"; do
            action "Would chmod +x ${HOOKS_DIR}/${hook}"
        done
        exit 0
    fi

    set_hooks_path "${HOOKS_DIR}/"
    for hook in "${REQUIRED_HOOKS[@]}"; do
        install_hook "$hook"
    done
}

do_uninstall() {
    if [[ "$DRY_RUN" == "true" ]]; then
        action "Would unset core.hooksPath"
        exit 0
    fi

    local current
    current=$(get_hooks_path)

    if [[ -z "$current" ]]; then
        warn "No custom hooks path configured — nothing to uninstall."
        exit 0
    fi

    if [[ "$current" != "${HOOKS_DIR}/" ]]; then
        warn "hooksPath is '${current}', not '${HOOKS_DIR}/'. Unsetting anyway."
    fi

    unset_hooks_path
    info "Hooks uninstalled. Default .git/hooks/ will be used."
}

do_status() {
    echo ""
    echo -e "${CYAN}Hook Installation Status${NC}"
    echo "──────────────────────────────"

    local current
    current=$(get_hooks_path)

    if [[ -z "$current" ]]; then
        echo -e "  hooksPath: ${YELLOW}(not set)${NC} — using default ${CYAN}.git/hooks/${NC}"
    else
        echo -e "  hooksPath: ${CYAN}${current}${NC}"
    fi

    echo ""
    echo -e " ${CYAN}Hook files in ${HOOKS_DIR}/${NC}"
    echo "  ────────────────────────"

    for hook in "${REQUIRED_HOOKS[@]}"; do
        local file="${HOOKS_DIR}/${hook}"
        if [[ -f "$file" ]]; then
            if [[ -x "$file" ]]; then
                echo -e "  ✓ ${hook}  ${GREEN}(present, executable)${NC}"
            else
                echo -e "  ⚠ ${hook}  ${YELLOW}(present, NOT executable)${NC}"
            fi
        else
            echo -e "  ✗ ${hook}  ${RED}(missing)${NC}"
        fi
    done

    echo ""
}

# ── Parse args ───────────────────────────────────────────────────────────────
MODE="all"
DRY_RUN="false"

for arg in "$@"; do
    case "$arg" in
        --help|-h)        usage ;;
        --pre-commit-only) MODE="pre-commit" ;;
        --post-commit-only) MODE="post-commit" ;;
        --uninstall)      MODE="uninstall" ;;
        --status)         MODE="status" ;;
        --dry-run)        DRY_RUN="true" ;;
        *)
            error "Unknown option: $arg"
            echo "Run '$(basename "$0") --help' for usage."
            exit 1
            ;;
    esac
done

# ── Main ──────────────────────────────────────────────────────────────────────
check_git_repo
check_jq

case "$MODE" in
    all)
        install_all
        ;;
    pre-commit|post-commit)
        if [[ "$DRY_RUN" == "true" ]]; then
            action "Would install only ${HOOKS_DIR}/${MODE}"
            exit 0
        fi
        # Set hooks path if not already set
        local current
        current=$(get_hooks_path)
        if [[ -z "$current" ]]; then
            set_hooks_path "${HOOKS_DIR}/"
        fi
        install_hook "$MODE"
        ;;
    uninstall)
        do_uninstall
        ;;
    status)
        do_status
        ;;
esac
