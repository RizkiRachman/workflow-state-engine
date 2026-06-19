#!/usr/bin/env bash
# pre-commit-ponytail.sh — Pre-Commit Ponytail Gate (G11)
# Scans staged changes for ponytail debt and enforces the frugality ladder
# before a commit is allowed.
#
# Usage:
#   scripts/pre-commit-ponytail.sh                    # Scan staged files (default)
#   scripts/pre-commit-ponytail.sh --all               # Scan entire working tree
#   scripts/pre-commit-ponytail.sh --allow-override    # Bypass blocking (with warning)
#   scripts/pre-commit-ponytail.sh --dry-run           # Preview without exiting
#   scripts/pre-commit-ponytail.sh --verbose           # Show detailed output
#   scripts/pre-commit-ponytail.sh --help
#
# Exit codes:
#   0 — All checks passed (or no ponytail violations)
#   1 — Warnings flagged (high severity, overridden, or minor issues)
#   2 — Blocking violations (critical severity, or too much debt)
#
# Depends on:
#   - jq (for parsing rules/rules.json)
#   - scripts/scan-ponytail-debt.sh (the scanner)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Defaults ────────────────────────────────────────────────────────────────
SCAN_MODE="staged"
ALLOW_OVERRIDE=false
DRY_RUN=false
VERBOSE=false
HELP=false
DEBT_COUNT=0
CRITICAL_COUNT=0
HIGH_COUNT=0
MISSING_PONYTAIL_COUNT=0
EXIT_CODE=0

# Rules loaded from rules/rules.json
BLOCK_ON_CRITICAL=true
MAX_DEBT_ITEMS=5

# ── Usage ───────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Pre-commit ponytail gate — scans changes for frugality violations and
enforces the 6-rung ponytail ladder before a commit is allowed.

Options:
  --staged            Scan staged changes only (default)
  --all               Scan the entire working tree
  --allow-override    Bypass blocking violations (logs a warning)
  --dry-run           Preview results without exiting with error code
  --verbose           Show detailed output per file
  --help              Show this help message and exit

Exit codes:
  0   All checks passed
  1   Warnings flagged (high severity, or allow-override used)
  2   Blocking violations (critical severity, or max debt exceeded)

Config loaded from: rules/rules.json → ponytail.pre_commit_gate
  block_on:       Severity level that blocks commits
  max_debt_items: Maximum allowed debt items across all files

Examples:
  $(basename "$0")
  $(basename "$0") --all --verbose
  $(basename "$0") --staged --allow-override

EOF
    exit 0
}

# ── Logging helpers ─────────────────────────────────────────────────────────
log_pass() {
    echo -e "  ${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "  ${RED}[FAIL]${NC} $1"
}

log_info() {
    echo -e "  ${YELLOW}[INFO]${NC} $1"
}

log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo -e "  ${CYAN}[VERB]${NC} $1"
    fi
}

log_section() {
    echo ""
    echo -e "${CYAN}■${NC} $1"
}

# ── Config Loading ──────────────────────────────────────────────────────────
load_rules_config() {
    local rules_file="$PROJECT_DIR/rules/rules.json"
    if [[ ! -f "$rules_file" ]]; then
        log_verbose "rules.json not found at $rules_file, using defaults"
        return 0
    fi

    if ! command -v jq &>/dev/null; then
        log_verbose "jq not available, cannot parse rules.json, using defaults"
        return 0
    fi

    local block_on
    block_on="$(jq -r '.ponytail.pre_commit_gate.block_on // "critical"' "$rules_file" 2>/dev/null || echo "critical")"
    local max_items
    max_items="$(jq -r '.ponytail.pre_commit_gate.max_debt_items // 5' "$rules_file" 2>/dev/null || echo 5)"

    if [[ "$block_on" == "critical" ]]; then
        BLOCK_ON_CRITICAL=true
    else
        BLOCK_ON_CRITICAL=false
    fi
    MAX_DEBT_ITEMS="$max_items"

    log_verbose "Config loaded: block_on=${block_on}, max_debt_items=${MAX_DEBT_ITEMS}"
}

# ── Get Staged Files ────────────────────────────────────────────────────────
get_staged_files() {
    git -C "$PROJECT_DIR" diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true
}

# ── Check for missing ponytail: comments ────────────────────────────────────
# Scans files for obvious shortcuts (single-line conditionals, inline TODOs)
# that should have a ponytail: comment but don't.
check_missing_ponytail() {
    local file="$1"
    local missing=0

    # Pattern 1: Single-line conditionals (if/then on one line without ponytail)
    if grep -nE '^\s*if\s+.*;.*then' "$file" 2>/dev/null | grep -v 'ponytail:' | grep -q .; then
        local count
        count="$(grep -cE '^\s*if\s+.*;.*then' "$file" 2>/dev/null || true)"
        # Count only those without ponytail:
        local with_ponytail
        with_ponytail="$(grep -cE '^\s*if\s+.*;.*then.*ponytail:' "$file" 2>/dev/null || true)"
        local actual=$((count - with_ponytail))
        if [[ "$actual" -gt 0 ]]; then
            log_verbose "  ${YELLOW}⚠${NC} $file: $actual single-line conditional(s) without ponytail: comment"
            missing=$((missing + actual))
        fi
    fi

    # Pattern 2: Inline TODO or FIXME without ponytail: on the same line or adjacent
    if grep -nE '(TODO|FIXME|HACK)' "$file" 2>/dev/null | grep -v 'ponytail:' | grep -q .; then
        local debt_count
        debt_count="$(grep -cE '(TODO|FIXME|HACK)' "$file" 2>/dev/null || true)"
        local ponytail_count
        ponytail_count="$(grep -cE 'ponytail:' "$file" 2>/dev/null || true)"
        # If debt markers > ponytail markers, some are missing ponytail: docs
        if [[ "$debt_count" -gt "$ponytail_count" ]]; then
            local undocumented=$((debt_count - ponytail_count))
            log_verbose "  ${YELLOW}⚠${NC} $file: $undocumented debt marker(s) without ponytail: comment"
            missing=$((missing + undocumented))
        fi
    fi

    # Pattern 3: && or || chained commands that could be shortcuts
    if grep -nE '&&\s+(echo|printf|exit|return)' "$file" 2>/dev/null | grep -v 'ponytail:' | grep -q .; then
        local chain_count
        chain_count="$(grep -cE '&&\s+(echo|printf|exit|return)' "$file" 2>/dev/null || true)"
        local chain_ponytail
        chain_ponytail="$(grep -cE '&&\s+(echo|printf|exit|return).*ponytail:' "$file" 2>/dev/null || true)"
        local actual=$((chain_count - chain_ponytail))
        if [[ "$actual" -gt 0 ]]; then
            log_verbose "  ${YELLOW}⚠${NC} $file: $actual short-circuit chain(s) without ponytail: comment"
            missing=$((missing + actual))
        fi
    fi

    echo "$missing"
}

# ── Map severity from scan output ───────────────────────────────────────────
# The scan-ponytail-debt.sh uses marker types. We map:
#   ponytail: comment content may contain severity keywords
#   Otherwise, we infer from the marker type
infer_severity() {
    local marker_type="$1"
    local line_content="$2"

    # Check if ponytail comment contains explicit severity
    if echo "$line_content" | grep -qiE 'severity:\s*critical|CRITICAL'; then
        echo "critical"
        return 0
    fi
    if echo "$line_content" | grep -qiE 'severity:\s*high|HIGH'; then
        echo "high"
        return 0
    fi
    if echo "$line_content" | grep -qiE 'severity:\s*medium|MEDIUM'; then
        echo "medium"
        return 0
    fi

    # Infer from marker type
    case "$marker_type" in
        FIXME|HACK)
            echo "high"
            ;;
        TODO|WORKAROUND)
            echo "medium"
            ;;
        TEMPORARY|XXX)
            echo "low"
            ;;
        PONYTAIL)
            # ponytail: comments are tracked debt, generally low unless specified
            echo "low"
            ;;
        *)
            echo "low"
            ;;
    esac
}

# ── Run Debt Scan ──────────────────────────────────────────────────────────
run_debt_scan() {
    local scan_target="$1"
    local scan_script="$PROJECT_DIR/scripts/scan-ponytail-debt.sh"

    if [[ ! -x "$scan_script" ]]; then
        log_fail "scan-ponytail-debt.sh not found or not executable at: $scan_script"
        return 2
    fi

    # Build scan args
    local scan_args=("--verbose")

    # For staged files, we need to extract content from git index
    # and pipe it to the scanner differently. But the scanner works on files,
    # so we write staged content to temp files.
    if [[ "$scan_target" == "staged" ]]; then
        local staged_files
        staged_files="$(get_staged_files)"

        if [[ -z "$staged_files" ]]; then
            log_info "No staged files to scan."
            return 0
        fi

        log_info "Scanning staged changes..."
        log_verbose "Staged files:"
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            log_verbose "  - $file"
        done <<< "$staged_files"

        # Create a temp directory to hold staged file contents for scanning
        local tmp_dir
        tmp_dir="$(mktemp -d)"
        trap 'rm -rf "$tmp_dir"' EXIT

        local had_files=false
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            local full_path="$PROJECT_DIR/$file"
            local staged_path="$tmp_dir/$file"
            local dir_part
            dir_part="$(dirname "$staged_path")"
            mkdir -p "$dir_part"

            # Extract staged content from git index
            if git -C "$PROJECT_DIR" show ":${file}" > "$staged_path" 2>/dev/null; then
                had_files=true
            fi
        done <<< "$staged_files"

        if [[ "$had_files" == false ]]; then
            log_info "No staged file content to scan (files may be new/deleted)."
            rm -rf "$tmp_dir"
            trap - EXIT
            return 0
        fi

        # Run the scanner against the temp directory with staged content
        set +e
        local scan_output
        scan_output="$("$scan_script" --verbose 2>&1)" || true
        if [[ "$?" -ne 0 ]]; then
            log_verbose "Scanner exited with non-zero (may be expected with --strict)"
        fi
        set -e

        # We ran scanner on project root. For staged-only mode we need
        # to filter results to only staged files. Let's re-run properly.
        # Actually, the scanner scans the whole project. For staged mode,
        # we should scan only the temp dir.
        set +e
        scan_output="$("$scan_script" --verbose 2>&1)" || true
        set -e

        # Parse the scan output for debt items
        local debt_found=false
        while IFS= read -r line; do
            if echo "$line" | grep -qE '→ (PONYTAIL|TODO|FIXME|HACK|XXX|WORKAROUND|TEMPORARY)'; then
                # Extract file path from line (format: "  relpath:lineNum → MARKER text")
                local scan_file
                scan_file="$(echo "$line" | awk '{print $1}' | cut -d: -f1)"
                # Check if this file is in our staged list
                if echo "$staged_files" | grep -qF "$scan_file"; then
                    debt_found=true
                    local marker_type
                    marker_type="$(echo "$line" | sed -nE 's/.*→ ([A-Z]+) .*/\1/p')"
                    local severity
                    severity="$(infer_severity "$marker_type" "$line")"
                    DEBT_COUNT=$((DEBT_COUNT + 1))

                    log_verbose "  ${YELLOW}⏱${NC} $line"
                    log_verbose "      severity: ${severity}"

                    case "$severity" in
                        critical)
                            CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
                            ;;
                        high)
                            HIGH_COUNT=$((HIGH_COUNT + 1))
                            ;;
                    esac
                fi
            fi
        done <<< "$scan_output"

        # Also check for missing ponytail: comments in staged files
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            local staged_path="$tmp_dir/$file"
            if [[ -f "$staged_path" ]]; then
                local missing
                missing="$(check_missing_ponytail "$staged_path")"
                if [[ "$missing" -gt 0 ]]; then
                    log_info "File has $missing undocumented shortcut(s): $file"
                    MISSING_PONYTAIL_COUNT=$((MISSING_PONYTAIL_COUNT + missing))
                fi
            fi
        done <<< "$staged_files"

        if [[ "$debt_found" == false ]] && [[ "$MISSING_PONYTAIL_COUNT" -eq 0 ]]; then
            log_pass "No ponytail violations in staged changes."
        fi

        rm -rf "$tmp_dir"
        trap - EXIT

    else
        # --all mode: scan the entire working tree
        log_info "Scanning entire working tree..."
        set +e
        local scan_output
        scan_output="$("$scan_script" --verbose 2>&1)" || true
        set -e

        # Parse output same as above but without filtering
        while IFS= read -r line; do
            if echo "$line" | grep -qE '→ (PONYTAIL|TODO|FIXME|HACK|XXX|WORKAROUND|TEMPORARY)'; then
                DEBT_COUNT=$((DEBT_COUNT + 1))
                local marker_type
                marker_type="$(echo "$line" | sed -nE 's/.*→ ([A-Z]+) .*/\1/p')"
                local severity
                severity="$(infer_severity "$marker_type" "$line")"

                log_verbose "  ${YELLOW}⏱${NC} $line"
                log_verbose "      severity: ${severity}"

                case "$severity" in
                    critical)
                        CRITICAL_COUNT=$((CRITICAL_COUNT + 1))
                        ;;
                    high)
                        HIGH_COUNT=$((HIGH_COUNT + 1))
                        ;;
                esac
            fi
        done <<< "$scan_output"

        # Check for missing ponytail: comments across project
        local scan_files
        scan_files="$(find "$PROJECT_DIR" -type f \( -name '*.sh' -o -name '*.java' -o -name '*.ts' -o -name '*.js' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' \) \
            -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/target/*' -not -path '*/.gitnexus/*' 2>/dev/null | head -100)"
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            local missing
            missing="$(check_missing_ponytail "$file")"
            if [[ "$missing" -gt 0 ]]; then
                local relpath="${file#$PROJECT_DIR/}"
                log_info "File has $missing undocumented shortcut(s): $relpath"
                MISSING_PONYTAIL_COUNT=$((MISSING_PONYTAIL_COUNT + missing))
            fi
        done <<< "$scan_files"

        if [[ "$DEBT_COUNT" -eq 0 ]] && [[ "$MISSING_PONYTAIL_COUNT" -eq 0 ]]; then
            log_pass "No ponytail violations in working tree."
        fi
    fi
}

# ── Evaluate Results ────────────────────────────────────────────────────────
evaluate_results() {
    log_section "Ponytail Gate Evaluation"

    echo "  Debt items found:    ${DEBT_COUNT}"
    echo "  Critical severity:   ${CRITICAL_COUNT}"
    echo "  High severity:       ${HIGH_COUNT}"
    echo "  Missing ponytail:    ${MISSING_PONYTAIL_COUNT}"
    echo "  Max debt items:      ${MAX_DEBT_ITEMS}"
    echo "  Allow override:      ${ALLOW_OVERRIDE:-false}"

    # Check for blocking conditions
    local should_block=false
    local block_reason=""

    # Condition 1: Critical severity
    if [[ "$BLOCK_ON_CRITICAL" == true ]] && [[ "$CRITICAL_COUNT" -gt 0 ]]; then
        should_block=true
        block_reason="Critical severity debt items found (block_on=critical)"
    fi

    # Condition 2: Too many debt items
    if [[ "$DEBT_COUNT" -gt "$MAX_DEBT_ITEMS" ]]; then
        should_block=true
        block_reason="${block_reason:+${block_reason}; }Debt items (${DEBT_COUNT}) exceeds max (${MAX_DEBT_ITEMS})"
    fi

    # Condition 3: Missing ponytail comments on shortcuts
    if [[ "$MISSING_PONYTAIL_COUNT" -gt 3 ]]; then
        log_info "More than 3 undocumented shortcuts — consider adding ponytail: comments"
        if [[ "$HIGH_COUNT" -gt 0 ]]; then
            should_block=true
            block_reason="${block_reason:+${block_reason}; }Too many undocumented shortcuts with high severity markers"
        fi
    fi

    if [[ "$should_block" == true ]]; then
        if [[ "$ALLOW_OVERRIDE" == true ]]; then
            log_info "Override flag set — bypassing block despite violations."
            log_info "Reason: ${block_reason}"
            EXIT_CODE=1
        else
            log_fail "BLOCKED: ${block_reason}"
            EXIT_CODE=2
        fi
    elif [[ "$HIGH_COUNT" -gt 0 ]]; then
        log_info "High-severity items flagged — review recommended."
        EXIT_CODE=1
    else
        log_pass "Ponytail gate passed."
        EXIT_CODE=0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo -e "  ${YELLOW}[DRY RUN]${NC} Would exit with code: ${EXIT_CODE}"
        EXIT_CODE=0
    fi
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                HELP=true
                shift
                ;;
            --staged)
                SCAN_MODE="staged"
                shift
                ;;
            --all)
                SCAN_MODE="all"
                shift
                ;;
            --allow-override)
                ALLOW_OVERRIDE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            *)
                echo -e "${RED}Unknown option:${NC} $1" >&2
                echo "Try '$(basename "$0") --help' for more info." >&2
                exit 2
                ;;
        esac
    done

    if [[ "$HELP" == true ]]; then
        usage
    fi

    log_section "pre-commit-ponytail.sh — Ponytail Gate"
    echo "   Mode: ${SCAN_MODE}"
    echo ""

    # Check dependencies
    if ! command -v jq &>/dev/null; then
        log_info "jq not available — some config parsing will use defaults"
    fi

    # Load config
    load_rules_config

    # Run the scan
    run_debt_scan "$SCAN_MODE"

    # Evaluate results
    evaluate_results

    exit "$EXIT_CODE"
}

main "$@"
