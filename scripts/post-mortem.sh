#!/usr/bin/env bash
# post-mortem.sh — BLOCKED state post-mortem analysis
# Usage: scripts/post-mortem.sh [--branch B] [--mode MODE] [--json]
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
  --branch B        Branch to analyze (auto-detect)
  --mode MODE       quick|deep|report (default: quick)
  --json            Machine-readable output
  --verbose         Verbose output

Modes:
  quick   Single-session analysis
  deep    Cross-reference similar BLOCKED patterns across sessions
  report  Full written report (outputs to session/{branch}/post-mortem.json)

Analysis includes:
  - What caused BLOCKED (score < 50? retry >= 3?)
  - Agent that was active
  - Decision chain leading up to it
  - Recommendations to prevent recurrence

EOF
    exit 0
}

BRANCH=""
MODE="quick"
JSON="false"
VERBOSE="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch) BRANCH="$2"; shift ;;
        --mode) MODE="$2"; shift ;;
        --json) JSON="true" ;;
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

analyze_quick() {
    local contract_file="session/$BRANCH/contract.json"
    
    if [[ ! -f "$contract_file" ]]; then
        log_info "No contract found at $contract_file"
        return 1
    fi
    
    local state=$(jq -r '.state // "UNKNOWN"' "$contract_file")
    if [[ "$state" != "BLOCKED" ]]; then
        log_info "Branch $BRANCH is not BLOCKED (state: $state)"
        return 0
    fi
    
    log_info "=== BLOCKED Post-Mortem ($BRANCH) ==="
    
    local score=$(jq -r '.score // 0' "$contract_file")
    local retries=$(jq -r '.retries // 0' "$contract_file")
    local agent=$(jq -r '.orchestration_contract.planning.primary_agent // "unknown"' "$contract_file" 2>/dev/null || echo "unknown")
    local phase=$(jq -r '.orchestration_contract.planning.current_phase // "unknown"' "$contract_file" 2>/dev/null || echo "unknown")
    
    # Determine cause
    local cause=""
    if [[ $score -lt 50 ]]; then
        cause="SCORE_TOO_LOW"
        log_fail "Cause: Score below threshold ($score < 50)"
    elif [[ $retries -ge 3 ]]; then
        cause="MAX_RETRIES_EXHAUSTED"
        log_fail "Cause: Max retries exhausted ($retries >= 3)"
    else
        cause="UNKNOWN"
        log_info "Cause: Unknown (score=$score, retries=$retries)"
    fi
    
    log_info "Agent: $agent | Phase: $phase | Score: $score | Retries: $retries"
    
    # Recommendations
    log_info "=== Recommendations ==="
    case "$cause" in
        SCORE_TOO_LOW)
            log_info "1. Review agent capabilities for $agent"
            log_info "2. Check if planning phase had sufficient context"
            log_info "3. Consider lowering min_score in rules.json"
            ;;
        MAX_RETRIES_EXHAUSTED)
            log_info "1. Investigate root cause of repeated failures"
            log_info "2. Check MCP server health (mcp-health.sh)"
            log_info "3. Consider increasing max_retries in rules.json"
            ;;
    esac
    
    if [[ "$JSON" == "true" ]]; then
        jq -n --arg br "$BRANCH" --arg cause "$cause" --arg agent "$agent" \
            '{branch:$br, cause:$cause, agent:$agent, score:$score, retries:$retries}'
    fi
}

analyze_deep() {
    log_info "=== Deep Post-Mortem ==="
    
    # Find similar BLOCKED patterns across all sessions
    local blocked_sessions=""
    for branch_dir in session/*/; do
        [[ -d "$branch_dir" ]] || continue
        local contract="$branch_dir/contract.json"
        [[ -f "$contract" ]] || continue
        
        local state=$(jq -r '.state // ""' "$contract")
        [[ "$state" == "BLOCKED" ]] && blocked_sessions+="$(basename $branch_dir)\n"
    done
    
    local count=$(echo "$blocked_sessions" | grep -c '^' || echo "0")
    log_info "Found $count BLOCKED sessions across branches"
    
    # Cross-reference by agent and cause
    while read -r br; do
        [[ -z "$br" ]] && continue
        local contract="session/$br/contract.json"
        local agent=$(jq -r '.orchestration_contract.planning.primary_agent // "unknown"' "$contract")
        local score=$(jq -r '.score // 0' "$contract")
        echo "$br|$agent|$score"
    done <<< "$blocked_sessions" | sort -t'|' -k2
    
    if [[ "$JSON" == "true" ]]; then
        echo "{\"blocked_count\":$count,\"branches\":[$(echo "$blocked_sessions" | jq -R . | jq -s .)]}"
    fi
}

analyze_report() {
    local output_file="session/$BRANCH/post-mortem.json"
    
    analyze_quick > /tmp/post-mortem-quick.txt
    
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local cause=$(grep "Cause:" /tmp/post-mortem-quick.txt | head -1)
    local agent=$(grep "Agent:" /tmp/post-mortem-quick.txt | head -1)
    local recommendations=$(grep -A3 "Recommendations" /tmp/post-mortem-quick.txt)
    
    jq -n --arg ts "$timestamp" --arg br "$BRANCH" \
        '{timestamp:$ts, branch:$br, analysis:"see quick output", status:"generated"}' > "$output_file"
    
    log_pass "Post-mortem report saved to $output_file"
}

main() {
    case "$MODE" in
        quick) analyze_quick ;;
        deep) analyze_deep ;;
        report) analyze_report ;;
        *) echo "Unknown mode: $MODE" >&2; exit 1 ;;
    esac
}

main