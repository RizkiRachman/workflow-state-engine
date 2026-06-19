#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# revert-threshold.sh — Revert Threshold Metric (G30)
#
# Calculates and reports the revert threshold metric — how complex/reversible
# the current changes are. Analyzes git diff (staged + unstaged) to measure
# files_changed, tokens_changed, services_affected, schema_changes, and
# computes a complexity_score.
#
# Compares against thresholds from rules.json → decisions.confidence_journal.revert_threshold
# and built-in warning (moderate) / block (high) thresholds.
#
# Usage:
#   ./scripts/revert-threshold.sh                    # Analyze all changes
#   ./scripts/revert-threshold.sh --staged-only      # Staged changes only
#   ./scripts/revert-threshold.sh --verbose           # Detailed breakdown
#   ./scripts/revert-threshold.sh --json              # Machine-readable JSON
#   ./scripts/revert-threshold.sh --help              # Show this message
#
# Exit codes:
#   0 — Safe to revert (complexity below warning threshold)
#   1 — Warning (complexity above warning threshold)
#   2 — Blocked (complexity too high — too risky to revert)
#
# Requirements:
#   - bash 4+
#   - git (for diff analysis)
#   - jq (for threshold config from rules.json)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Config ──────────────────────────────────────────────────────────────────
STAGED_ONLY=false
VERBOSE=false
JSON_MODE=false
EXIT_CODE=0

# ── Complexity thresholds (loaded from rules.json or defaults) ──────────────
WARNING_THRESHOLD=0
BLOCK_THRESHOLD=0
WARNING_LABEL="moderate"
BLOCK_LABEL="high"

# Weight factors
WEIGHT_FILES=3
WEIGHT_TOKENS=0.05
WEIGHT_SERVICES=5
WEIGHT_SCHEMA=15

# ── Colors ──────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; NC=''
fi

# ── Help ────────────────────────────────────────────────────────────────────
usage() {
    cat <<'USAGE'
revert-threshold.sh — Revert Threshold Metric (G30)

SYNOPSIS
    ./scripts/revert-threshold.sh [OPTIONS]
    ./scripts/revert-threshold.sh --staged-only
    ./scripts/revert-threshold.sh --verbose
    ./scripts/revert-threshold.sh --json

OPTIONS
    --help              Show this help message and exit
    --staged-only       Only analyze staged changes (skip unstaged)
    --verbose           Show detailed breakdown of complexity factors
    --json              Output results as machine-readable JSON

METRICS
    files_changed       Count of modified files (staged + unstaged)
    tokens_changed      Approximate lines added/changed/removed
    services_affected   Unique top-level directory prefixes
    schema_changes      Whether migration files or contract JSON changed
    complexity_score    Weighted sum: files*3 + tokens*0.05 + services*5 + schema*15

THRESHOLDS
    Loaded from rules.json → decisions.confidence_journal.revert_threshold.threshold
    Defaults: warning ≥ 30 (moderate), blocked ≥ 60 (high)

EXIT CODES
    0   Safe to revert (complexity below warning threshold)
    1   Warning (complexity above warning threshold)
    2   Blocked (complexity too high — too risky to revert)

EXAMPLES
    ./scripts/revert-threshold.sh
    ./scripts/revert-threshold.sh --staged-only --verbose
    ./scripts/revert-threshold.sh --json
USAGE
    exit 0
}

# ── Logging ─────────────────────────────────────────────────────────────────
log_pass() {
    local msg="$1"
    if [[ "$JSON_MODE" == true ]]; then echo "[PASS] $msg" >&2
    else echo -e "  ${GREEN}[PASS]${NC} $msg"; fi
}

log_fail() {
    local msg="$1"
    if [[ "$JSON_MODE" == true ]]; then echo "[FAIL] $msg" >&2
    else echo -e "  ${RED}[FAIL]${NC} $msg"; fi
}

log_warn() {
    local msg="$1"
    if [[ "$JSON_MODE" == true ]]; then echo "[WARN] $msg" >&2
    else echo -e "  ${YELLOW}[WARN]${NC} $msg"; fi
}

log_info() {
    local msg="$1"
    if [[ "$VERBOSE" == true ]]; then
        if [[ "$JSON_MODE" == true ]]; then echo "[INFO] $msg" >&2
        else echo -e "  ${CYAN}[INFO]${NC} $msg"; fi
    fi
}

log_verbose() {
    local msg="$1"
    if [[ "$VERBOSE" == true ]]; then
        if [[ "$JSON_MODE" == true ]]; then echo "  :: $msg" >&2
        else echo "  :: $msg"; fi
    fi
}

log_section() {
    local msg="$1"
    if [[ "$JSON_MODE" == true ]]; then echo "== $msg" >&2
    else echo -e "\n${BOLD}==${NC} ${BOLD}$msg${NC}"; fi
}

# ── Helpers ─────────────────────────────────────────────────────────────────
get_branch() {
    git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "unknown"
}

get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

load_thresholds() {
    local rules_file="$PROJECT_DIR/rules/rules.json"
    local default_warning=30
    local default_block=60

    if [[ ! -f "$rules_file" ]]; then
        WARNING_THRESHOLD=$default_warning
        BLOCK_THRESHOLD=$default_block
        WARNING_LABEL="moderate"
        BLOCK_LABEL="high"
        return
    fi

    if ! command -v jq &>/dev/null; then
        WARNING_THRESHOLD=$default_warning
        BLOCK_THRESHOLD=$default_block
        WARNING_LABEL="moderate"
        BLOCK_LABEL="high"
        return
    fi

    local config_threshold
    config_threshold=$(jq -r '.decisions.confidence_journal.revert_threshold.threshold // empty' "$rules_file" 2>/dev/null || echo "")
    if [[ -z "$config_threshold" ]]; then
        WARNING_THRESHOLD=$default_warning
        BLOCK_THRESHOLD=$default_block
        return
    fi

    WARNING_THRESHOLD=$config_threshold
    BLOCK_THRESHOLD=$((config_threshold * 2))
    log_verbose "Thresholds from rules.json: warning=${WARNING_THRESHOLD} (${WARNING_LABEL}), blocked=${BLOCK_THRESHOLD} (${BLOCK_LABEL})"
}

# ── Metrics ─────────────────────────────────────────────────────────────────
count_files_changed() {
    local diff_scope="$1"
    if [[ -z "$diff_scope" ]]; then
        local unstaged
        unstaged=$(git -C "$PROJECT_DIR" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
        local untracked
        untracked=$(git -C "$PROJECT_DIR" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
        echo $((unstaged + untracked))
    else
        git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' '
    fi
}

count_tokens_changed() {
    local diff_scope="$1"
    local stat_line
    if [[ -z "$diff_scope" ]]; then
        stat_line=$(git -C "$PROJECT_DIR" diff --stat 2>/dev/null | tail -1 || echo "")
    else
        stat_line=$(git -C "$PROJECT_DIR" diff --cached --stat 2>/dev/null | tail -1 || echo "")
    fi

    local insertions=0 deletions=0
    if echo "$stat_line" | grep -q "insertion"; then
        insertions=$(echo "$stat_line" | sed -n 's/.*\([0-9][0-9]*\) insertion.*/\1/p' || echo 0)
    fi
    if echo "$stat_line" | grep -q "deletion"; then
        deletions=$(echo "$stat_line" | sed -n 's/.*\([0-9][0-9]*\) deletion.*/\1/p' || echo 0)
    fi
    echo $((insertions + deletions))
}

count_services_affected() {
    local diff_scope="$1"
    local files
    if [[ -z "$diff_scope" ]]; then
        files=$(git -C "$PROJECT_DIR" diff --name-only 2>/dev/null; git -C "$PROJECT_DIR" ls-files --others --exclude-standard 2>/dev/null)
    else
        files=$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null)
    fi
    if [[ -z "$files" ]]; then echo 0; return; fi
    echo "$files" | grep -v '^$' | sed 's|/.*||' | sort -u | grep -v '^\.' | wc -l | tr -d ' '
}

detect_schema_changes() {
    local diff_scope="$1"
    local changed_files
    if [[ -z "$diff_scope" ]]; then
        changed_files=$(git -C "$PROJECT_DIR" diff --name-only 2>/dev/null; git -C "$PROJECT_DIR" ls-files --others --exclude-standard 2>/dev/null)
    else
        changed_files=$(git -C "$PROJECT_DIR" diff --cached --name-only 2>/dev/null)
    fi
    if [[ -z "$changed_files" ]]; then echo "false"; return; fi

    local patterns=("contract/" "rules/" "migration/" "migrations/" "schema" "V[0-9]" "changelog/")
    for p in "${patterns[@]}"; do
        if echo "$changed_files" | grep -qE "$p"; then
            log_verbose "Schema change detected matching: $p"
            echo "true"
            return
        fi
    done
    echo "false"
}

calculate_complexity() {
    local files="$1" tokens="$2" services="$3" schema="$4"
    local file_score=$((files * WEIGHT_FILES))
    local token_score=$((tokens / 20))  # approximate 0.05 * tokens
    local service_score=$((services * WEIGHT_SERVICES))
    local schema_score=0
    [[ "$schema" == "true" ]] && schema_score=$WEIGHT_SCHEMA
    echo $((file_score + token_score + service_score + schema_score))
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help) usage ;;
            --staged-only) STAGED_ONLY=true; shift ;;
            --verbose) VERBOSE=true; shift ;;
            --json) JSON_MODE=true; shift ;;
            *) echo "Unknown option: $1"; echo "Use --help for usage information."; exit 1 ;;
        esac
    done

    local branch
    branch="$(get_branch)"
    local diff_scope=""
    [[ "$STAGED_ONLY" == true ]] && diff_scope="--cached"

    load_thresholds

    if [[ "$JSON_MODE" == false ]]; then
        echo -e "\n${BOLD}Revert Threshold — ${branch}${NC}\n"
    fi

    log_section "Collecting Metrics"
    local files_changed
    files_changed=$(count_files_changed "$diff_scope")
    log_info "Files changed: $files_changed"

    local tokens_changed
    tokens_changed=$(count_tokens_changed "$diff_scope")
    log_info "Lines changed: $tokens_changed"

    local services_affected
    services_affected=$(count_services_affected "$diff_scope")
    log_info "Services affected: $services_affected"

    local schema_changes
    schema_changes=$(detect_schema_changes "$diff_scope")
    log_info "Schema changes: $schema_changes"

    local complexity_score
    complexity_score=$(calculate_complexity "$files_changed" "$tokens_changed" "$services_affected" "$schema_changes")
    log_info "Complexity score: $complexity_score"

    if [[ "$VERBOSE" == true ]]; then
        log_section "Breakdown"
        log_verbose "Files (${files_changed} × ${WEIGHT_FILES})         = $((files_changed * WEIGHT_FILES))"
        log_verbose "Tokens (${tokens_changed} × ~0.05)     = $((tokens_changed / 20))"
        log_verbose "Services (${services_affected} × ${WEIGHT_SERVICES})    = $((services_affected * WEIGHT_SERVICES))"
        local sv=0; [[ "$schema_changes" == "true" ]] && sv=$WEIGHT_SCHEMA
        log_verbose "Schema (${schema_changes} × ${WEIGHT_SCHEMA})     = $sv"
        log_verbose "Warning threshold: ${WARNING_THRESHOLD} (${WARNING_LABEL})"
        log_verbose "Block threshold:   ${BLOCK_THRESHOLD} (${BLOCK_LABEL})"
    fi

    local verdict="safe"
    local verdict_label="Safe to revert"
    EXIT_CODE=0

    if [[ "$complexity_score" -ge "$BLOCK_THRESHOLD" ]]; then
        verdict="blocked"
        verdict_label="BLOCKED — Too risky to revert"
        EXIT_CODE=2
    elif [[ "$complexity_score" -ge "$WARNING_THRESHOLD" ]]; then
        verdict="warning"
        verdict_label="Warning — Review required before revert"
        EXIT_CODE=1
    fi

    if [[ "$JSON_MODE" == true ]]; then
        local ts
        ts="$(get_timestamp)"
        # Construct minimal JSON without jq dependency
        echo "{\"timestamp\":\"$ts\",\"branch\":\"$branch\",\"metrics\":{\"files_changed\":$files_changed,\"tokens_changed\":$tokens_changed,\"services_affected\":$services_affected,\"schema_changes\":$schema_changes},\"complexity_score\":$complexity_score,\"thresholds\":{\"warning\":$WARNING_THRESHOLD,\"block\":$BLOCK_THRESHOLD},\"verdict\":\"$verdict\",\"exit_code\":$EXIT_CODE}"
    else
        echo ""
        log_section "Verdict"
        echo -e "  Complexity: ${BOLD}$complexity_score${NC}"
        echo "  Warning >${WARNING_THRESHOLD} (${WARNING_LABEL}), Blocked ≥${BLOCK_THRESHOLD} (${BLOCK_LABEL})"
        echo -e "  ${BOLD}Result:${NC} ${verdict_label}"
        echo ""
        echo "  Metrics: files=$files_changed, tokens=$tokens_changed, services=$services_affected, schema=$schema_changes"
    fi

    exit "$EXIT_CODE"
}

main "$@"