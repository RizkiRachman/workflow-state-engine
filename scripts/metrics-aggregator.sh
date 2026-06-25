#!/usr/bin/env bash
# metrics-aggregator.sh — Cross-session quality metrics aggregation
# Usage: scripts/metrics-aggregator.sh [--mode MODE] [--days N] [--branch B] [--json]
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
  --mode MODE      summary|by-state|timeline|quality (default: summary)
  --days N         Lookback window (default: 30)
  --branch B       Filter to specific branch
  --json           Machine-readable output
  --verbose        Verbose output

Modes:
  summary   Aggregate overview (total iterations, avg score, pass rate)
  by-state  Distribution of state outcomes (COMPLETE/BLOCKED/RETRY)
  timeline  Chronological score sequence by branch
  quality   Composite quality score (avg × pass_rate / block_rate)

EOF
    exit 0
}

MODE="summary"
DAYS=30
BRANCH=""
JSON="false"
VERBOSE="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) MODE="$2"; shift ;;
        --days) DAYS="$2"; shift ;;
        --branch) BRANCH="$2"; shift ;;
        --json) JSON="true" ;;
        --verbose) VERBOSE="true" ;;
        --help|-h) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
    shift
done

collect_metrics() {
    local branch_filter="$1"
    local metrics=""
    local now=$(date +%s)
    local cutoff=$((now - DAYS * 86400))
    
    for branch_dir in session/*/; do
        [[ -d "$branch_dir" ]] || continue
        local br=$(basename "$branch_dir")
        [[ -n "$branch_filter" && "$branch_filter" != "$br" ]] && continue
        
        local contract="$branch_dir/contract.json"
        [[ -f "$contract" ]] || continue
        
        local state=$(jq -r '.state // "UNKNOWN"' "$contract" 2>/dev/null)
        local score=$(jq -r '.score // 0' "$contract" 2>/dev/null)
        local timestamp=$(jq -r '.timestamp // .created_at // empty' "$contract" 2>/dev/null)
        local epoch=$(date -d "$timestamp" +%s 2>/dev/null || echo "0")
        
        [[ "$epoch" -lt "$cutoff" ]] && continue
        
        echo "$timestamp|$br|$state|$score"
    done | sort -t'|' -k1
}

mode_summary() {
    local metrics="$1"
    local total=$(echo "$metrics" | wc -l | tr -d ' ')
    local completes=$(echo "$metrics" | grep -c '|COMPLETE|' || echo "0")
    local blocked=$(echo "$metrics" | grep -c '|BLOCKED|' || echo "0")
    local avg_score=$(echo "$metrics" | cut -d'|' -f4 | awk '{sum+=$1; count++} END {printf "%.1f", sum/count}')
    local pass_rate=$((completes * 100 / total))
    local block_rate=$((blocked * 100 / total))
    
    if [[ "$JSON" == "true" ]]; then
        echo "{\"total\":$total,\"avg_score\":$avg_score,\"pass_rate\":$pass_rate,\"block_rate\":$block_rate}"
    else
        log_info "=== Summary Metrics ==="
        printf "  Total sessions:  %d\n" $total
        printf "  Avg score:       %.1f\n" $avg_score
        printf "  Pass rate:       %d%%\n" $pass_rate
        printf "  Block rate:      %d%%\n" $block_rate
    fi
}

mode_by_state() {
    local metrics="$1"
    local total=$(echo "$metrics" | wc -l | tr -d ' ')
    local completes=$(echo "$metrics" | grep -c '|COMPLETE|' || echo "0")
    local blocked=$(echo "$metrics" | grep -c '|BLOCKED|' || echo "0")
    local retry=$(echo "$metrics" | grep -c '|RETRY|' || echo "0")
    local other=$((total - completes - blocked - retry))
    
    if [[ "$JSON" == "true" ]]; then
        echo "{\"COMPLETE\":$completes,\"BLOCKED\":$blocked,\"RETRY\":$retry,\"OTHER\":$other}"
    else
        log_info "=== State Distribution ==="
        printf "  COMPLETE: %d (%.1f%%)\n" $completes $(echo "$completes * 100 / $total" | bc -l)
        printf "  BLOCKED:  %d (%.1f%%)\n" $blocked $(echo "$blocked * 100 / $total" | bc -l)
        printf "  RETRY:    %d (%.1f%%)\n" $retry $(echo "$retry * 100 / $total" | bc -l)
        printf "  OTHER:    %d (%.1f%%)\n" $other $(echo "$other * 100 / $total" | bc -l)
    fi
}

mode_timeline() {
    local metrics="$1"
    if [[ "$JSON" == "true" ]]; then
        echo "$metrics" | while IFS='|' read -r ts br st sc; do
            echo "{\"timestamp\":\"$ts\",\"branch\":\"$br\",\"state\":\"$st\",\"score\":$sc}"
        done | jq -s '.'
    else
        log_info "=== Score Timeline ==="
        echo "$metrics" | while IFS='|' read -r ts br st sc; do
            printf "  %-20s | %-30s | %-8s | %3d\n" "$ts" "$br" "$st" "$sc"
        done
    fi
}

mode_quality() {
    local metrics="$1"
    local total=$(echo "$metrics" | wc -l | tr -d ' ')
    local completes=$(echo "$metrics" | grep -c '|COMPLETE|' || echo "0")
    local blocked=$(echo "$metrics" | grep -c '|BLOCKED|' || echo "1")
    local avg_score=$(echo "$metrics" | cut -d'|' -f4 | awk '{sum+=$1; count++} END {printf "%.1f", sum/count}')
    local pass_rate=$((completes * 100 / total))
    local block_rate=$((blocked * 100 / total))
    [[ $block_rate -eq 0 ]] && block_rate=1
    local quality=$(echo "$avg_score * $pass_rate / $block_rate" | bc -l | cut -d'.' -f1)
    
    if [[ "$JSON" == "true" ]]; then
        echo "{\"quality_score\":$quality,\"avg_score\":$avg_score,\"pass_rate\":$pass_rate,\"block_rate\":$block_rate}"
    else
        log_info "=== Composite Quality Score ==="
        printf "  Quality:     %d (avg_score × pass_rate / block_rate)\n" $quality
        printf "  Avg score:   %.1f\n" $avg_score
        printf "  Pass rate:   %d%%\n" $pass_rate
        printf "  Block rate:  %d%%\n" $block_rate
    fi
}

main() {
    local metrics=$(collect_metrics "$BRANCH")
    
    if [[ -z "$metrics" ]]; then
        log_info "No metrics found in session/*/"
        exit 0
    fi
    
    case "$MODE" in
        summary) mode_summary "$metrics" ;;
        by-state) mode_by_state "$metrics" ;;
        timeline) mode_timeline "$metrics" ;;
        quality) mode_quality "$metrics" ;;
        *) echo "Unknown mode: $MODE" >&2; exit 1 ;;
    esac
}

main