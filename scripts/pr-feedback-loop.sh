#!/usr/bin/env bash
# pr-feedback-loop.sh — Automated PR feedback loop for config adjustments
# Usage: scripts/pr-feedback-loop.sh [--pr NUMBER] [--mode MODE] [--score N] [--branch B]
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_pass() { echo -e "  ${GREEN}[PASS]${NC} $*"; }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $*"; }
log_info() { echo -e "  ${YELLOW}[INFO]${NC} $*"; }
log_verbose() { [[ "$VERBOSE" == "true" ]] && echo -e "  ${CYAN}[VERB]${NC} $*"; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --pr NUMBER       GitHub PR number
  --mode MODE       analyze|apply|preview (default: preview)
  --score N         PR quality score (0-100)
  --branch B        Branch name (auto-detect)
  --threshold P     Minimum adjustment threshold (default: 5)
  --dry-run         Preview changes without modifying
  --verbose         Verbose output

Modes:
  analyze  Analyze PR score, suggestions, impact
  apply    Apply config adjustments based on analysis
  preview  Preview what adjustments would be made

Adjustments logic:
  If avg PLAN > 90: tighten threshold (raise min_score +5)
  If avg PLAN < 60: loosen threshold (lower min_score -5)
  If block rate > 30%: increase max_retries +1
  If block rate < 10%: decrease max_retries -1

EOF
    exit 0
}

PR_NUMBER=""
MODE="preview"
SCORE=""
BRANCH=""
THRESHOLD=5
DRY_RUN="false"
VERBOSE="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr) PR_NUMBER="$2"; shift ;;
        --mode) MODE="$2"; shift ;;
        --score) SCORE="$2"; shift ;;
        --branch) BRANCH="$2"; shift ;;
        --threshold) THRESHOLD="$2"; shift ;;
        --dry-run) DRY_RUN="true" ;;
        --verbose) VERBOSE="true" ;;
        --help|-h) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
    shift
done

# Auto-detect branch
if [[ -z "$BRANCH" ]]; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
fi

analyze_pr() {
    local contract_file="session/$BRANCH/contract.json"
    local rules_file="rules/rules.json"
    
    if [[ ! -f "$contract_file" ]]; then
        log_info "No contract found at $contract_file"
        return 1
    fi
    
    log_info "=== PR Feedback Analysis ==="
    log_info "Branch: $BRANCH | PR: ${PR_NUMBER:-auto-detected}"
    
    # Collect metrics from metrics-aggregator
    local metrics=$(bash scripts/metrics-aggregator.sh --branch "$BRANCH" --mode summary --json 2>/dev/null || echo "{}")
    local avg_plan=$(echo "$metrics" | jq -r '.avg_plan // 70')
    local block_rate=$(echo "$metrics" | jq -r '.block_rate // 10')
    
    log_verbose "Avg PLAN score: $avg_plan | Block rate: $block_rate%"
    
    # Determine adjustments
    local adjustments=""
    
    if [[ $avg_plan -gt 90 ]]; then
        adjustments+="PLAN_THRESHOLD:+5\n"
        log_info "Avg PLAN > 90 → tightening threshold (+5)"
    elif [[ $avg_plan -lt 60 ]]; then
        adjustments+="PLAN_THRESHOLD:-5\n"
        log_info "Avg PLAN < 60 → loosening threshold (-5)"
    fi
    
    if [[ $block_rate -gt 30 ]]; then
        adjustments+="MAX_RETRIES:+1\n"
        log_info "Block rate > 30% → increasing retries (+1)"
    elif [[ $block_rate -lt 10 ]]; then
        adjustments+="MAX_RETRIES:-1\n"
        log_info "Block rate < 10% → decreasing retries (-1)"
    fi
    
    echo "$adjustments"
}

apply_adjustments() {
    local adjustments="$1"
    local rules_file="rules/rules.json"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY_RUN] Would update $rules_file with:"
        echo "$adjustments" | while read -r line; do
            [[ -z "$line" ]] && continue
            log_info "  $line"
        done
        return 0
    fi
    
    if [[ ! -f "$rules_file" ]]; then
        log_fail "rules/rules.json not found"
        return 1
    fi
    
    echo "$adjustments" | while read -r line; do
        [[ -z "$line" ]] && continue
        local key=$(echo "$line" | cut -d':' -f1)
        local delta=$(echo "$line" | cut -d':' -f2)
        
        case "$key" in
            PLAN_THRESHOLD)
                local current=$(jq -r '.scoring.min_score // 70' "$rules_file")
                local new=$((current + delta))
                jq ".scoring.min_score = $new" "$rules_file" > "$rules_file.tmp" && mv "$rules_file.tmp" "$rules_file"
                log_pass "Updated scoring.min_score: $current → $new"
                ;;
            MAX_RETRIES)
                local current=$(jq -r '.scoring.max_retries // 3' "$rules_file")
                local new=$((current + delta))
                [[ $new -lt 1 ]] && new=1
                jq ".scoring.max_retries = $new" "$rules_file" > "$rules_file.tmp" && mv "$rules_file.tmp" "$rules_file"
                log_pass "Updated scoring.max_retries: $current → $new"
                ;;
        esac
    done
}

main() {
    local adjustments=$(analyze_pr)
    
    case "$MODE" in
        analyze)
            echo "$adjustments"
            ;;
        apply)
            apply_adjustments "$adjustments"
            ;;
        preview)
            log_info "=== Preview Adjustments ==="
            echo "$adjustments" | while read -r line; do
                [[ -z "$line" ]] && continue
                log_info "  $line"
            done
            ;;
        *)
            echo "Unknown mode: $MODE" >&2
            exit 1
            ;;
    esac
}

main