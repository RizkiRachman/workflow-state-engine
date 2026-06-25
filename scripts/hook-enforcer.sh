#!/usr/bin/env bash
set -euo pipefail

log_pass() { echo -e "\033[32m✓ $1\033[0m"; }
log_fail() { echo -e "\033[31m✗ $1\033[0m"; }
log_info() { echo -e "\033[34mℹ $1\033[0m"; }
log_verbose() { [[ "${VERBOSE:-0}" == "1" ]] && echo -e "\033[33m⋯ $1\033[0m"; }

usage() {
    cat << EOF
Usage: hook-enforcer.sh [OPTIONS] --hook TYPE

Git hook enforcement mechanism.

OPTIONS:
  --hook TYPE           Hook type: pre-commit|post-commit|pre-push|post-merge|pre-flight|post-flight (required)
  --directory DIR       Project directory (default: .)
  --enforce-mode MODE   Enforcement mode: audit|warn|block (default: warn)
  --contract FILE       Contract file for hook-level validation
  --skip-hooks          Skip hook execution (for emergency override)
  --repair              Repair missing/broken hooks
  --verify              Verify hooks are properly installed
  --dry-run             Show what would happen without executing hooks
  --verbose             Show detailed hook output
  --json                Output results as JSON
  --help                Show this help

HOOK TYPES:
  pre-commit    Run pre-commit hooks (ponytail, blast-radius, schema)
  post-commit   Run post-commit hooks (gitnexus re-index, graphify update)
  pre-push      Run pre-push hooks (validation, branch check)
  post-merge    Run post-merge hooks (session update, re-index)
  pre-flight    Run pre-flight validation before any operation
  post-flight   Run post-flight cleanup after operation

EXAMPLES:
  hook-enforcer.sh --hook pre-commit
  hook-enforcer.sh --hook post-commit --contract session/main/contract.json
  hook-enforcer.sh --repair
  hook-enforcer.sh --verify
EOF
}

HOOK_TYPE=""
DIRECTORY="."
ENFORCE_MODE="warn"
CONTRACT_FILE=""
SKIP_HOOKS=0
REPAIR=0
VERIFY=0
DRY_RUN=0
VERBOSE=0
JSON_OUTPUT=0

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --hook) HOOK_TYPE="$2"; shift 2 ;;
            --directory) DIRECTORY="$2"; shift 2 ;;
            --enforce-mode) ENFORCE_MODE="$2"; shift 2 ;;
            --contract) CONTRACT_FILE="$2"; shift 2 ;;
            --skip-hooks) SKIP_HOOKS=1; shift ;;
            --repair) REPAIR=1; shift ;;
            --verify) VERIFY=1; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            --verbose) VERBOSE=1; shift ;;
            --json) JSON_OUTPUT=1; shift ;;
            --help|-h) usage; exit 0 ;;
            *) log_fail "Unknown argument: $1"; usage; exit 1 ;;
        esac
    done
}

get_timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
get_epoch_ms() { date +%s%3N; }

verify_hooks() {
    log_info "Verifying git hooks installation..."
    local hooks_dir=".git/hooks"
    local required_hooks="pre-commit post-commit post-merge"
    local missing=0
    for hook in $required_hooks; do
        if [[ -f "$hooks_dir/$hook" ]]; then
            log_pass "Hook $hook installed"
        else
            log_fail "Hook $hook missing"
            missing=$((missing + 1))
        fi
    done
    if [[ "$missing" -gt 0 ]]; then
        log_fail "$missing hooks missing"
        return 1
    fi
    log_pass "All hooks verified"
    return 0
}

repair_hooks() {
    log_info "Repairing git hooks..."
    local hooks_dir=".git/hooks"
    mkdir -p "$hooks_dir"
    for hook in pre-commit post-commit post-merge; do
        local hook_path="$hooks_dir/$hook"
        if [[ ! -f "$hook_path" ]]; then
            ln -s "../../.githooks/$hook" "$hook_path" 2>/dev/null || \
            ln -s "../scripts/pre-commit-ponytail.sh" "$hook_path" 2>/dev/null || \
            echo "#!/usr/bin/env bash" > "$hook_path"
            chmod +x "$hook_path"
            log_pass "Repaired hook: $hook"
        fi
    done
    log_pass "Hooks repaired"
}

run_hook() {
    log_info "Running hook: $HOOK_TYPE"
    if [[ "$SKIP_HOOKS" -eq 1 ]]; then
        log_info "Hooks skipped (override)"
        return 0
    fi
    local exit_code=0
    case "$HOOK_TYPE" in
        pre-commit)
            if [[ -f "scripts/pre-commit-ponytail.sh" ]]; then
                bash scripts/pre-commit-ponytail.sh || exit_code=1
            fi
            ;;
        post-commit)
            bash scripts/gitnexus-analyze.sh 2>/dev/null || true
            graphify update . 2>/dev/null || true
            ;;
        post-merge)
            bash scripts/snapshot-contract.sh --snapshot-only 2>/dev/null || true
            bash scripts/gitnexus-analyze.sh 2>/dev/null || true
            ;;
        pre-flight)
            if [[ -f "$CONTRACT_FILE" ]]; then
                bash scripts/validate-contract.sh --file "$CONTRACT_FILE" || exit_code=1
            fi
            ;;
        post-flight)
            bash scripts/snapshot-contract.sh 2>/dev/null || true
            ;;
        *)
            log_fail "Unknown hook type: $HOOK_TYPE"
            return 1
            ;;
    esac
    if [[ "$exit_code" -eq 0 ]]; then
        log_pass "Hook $HOOK_TYPE passed"
    else
        case "$ENFORCE_MODE" in
            audit) log_info "Hook $HOOK_TYPE failed (audit mode)" ;;
            warn) log_fail "Hook $HOOK_TYPE failed (warn mode)" ;;
            block) log_fail "Hook $HOOK_TYPE failed (block mode)"; return 1 ;;
        esac
    fi
    return $exit_code
}

main() {
    parse_args "$@"
    local start_ms
    start_ms=$(get_epoch_ms)
    local result=0
    if [[ "$VERIFY" -eq 1 ]]; then
        verify_hooks || result=1
    elif [[ "$REPAIR" -eq 1 ]]; then
        repair_hooks
    elif [[ -n "$HOOK_TYPE" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log_info "Dry run: would execute hook $HOOK_TYPE"
        else
            run_hook || result=1
        fi
    else
        log_fail "Missing --hook, --verify, or --repair"
        usage
        exit 1
    fi
    local elapsed_ms=$(( $(get_epoch_ms) - start_ms ))
    if [[ "$JSON_OUTPUT" -eq 1 ]]; then
        jq -n --arg hook "$HOOK_TYPE" --arg result "$result" --arg elapsed "$elapsed_ms" \
            '{hook: $hook, result: (if $result == "0" then "pass" else "fail" end), elapsed_ms: ($elapsed | tonumber)}'
    fi
    exit $result
}

main "$@"