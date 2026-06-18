#!/usr/bin/env bash
# shellcheck disable=SC2086
# collect-metrics.sh — Aggregate per-iteration metrics into cumulative report
# Reads all tasks/iter-*/metrics.json files and produces cumulative JSON.
#   bash scripts/collect-metrics.sh                    # Auto-detect iter dirs
#   bash scripts/collect-metrics.sh --help             # Show usage
#   bash scripts/collect-metrics.sh --pattern PATTERN  # Glob pattern (default: tasks/iter-*/metrics.json)
#   bash scripts/collect-metrics.sh --output FILE      # Output file (default: stdout)
#   0 — Success
#   1 — No metrics files found
#   2 — Usage displayed / invalid args

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATTERN="$PROJECT_ROOT/tasks/iter-*/metrics.json"
OUTPUT_FILE=""
VERBOSE=false

if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN='' RED='' YELLOW='' NC=''
fi

log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }

usage() {
    cat <<'USAGE'
Usage: collect-metrics.sh [OPTIONS]

Aggregate per-iteration metrics into a cumulative JSON report.

Options:
  --help                Show this help and exit
  --pattern PATTERN     Glob pattern for metrics files (default: tasks/iter-*/metrics.json)
  --output FILE         Write output to file (default: stdout)
  --verbose             Detailed processing output

Output JSON structure:
{
  "iterations": [ ... ],           // Array of 10 per-iteration metric objects
  "summary": {
    "total_iterations": 10,
    "total_blocked": 0,
    "total_passed": 10,
    "avg_score_plan": 85.0,
    "avg_score_execute": 82.0,
    "avg_score_review": 88.0,
    "min_score": 70,
    "max_score": 94,
    "score_trajectory": "improving|stable|declining",
    "permission_comparison": {
      "bypass": { "avg_score": 85.0, "avg_duration_ms": 120000, "blocked_count": 0, "violations": 0 },
      "normal": { "avg_score": 88.0, "avg_duration_ms": 150000, "blocked_count": 0, "violations": 0 }
    }
  }
}
USAGE
    exit 2
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help) usage ;;
            --pattern) PATTERN="$2"; shift 2 ;;
            --output) OUTPUT_FILE="$2"; shift 2 ;;
            --verbose) VERBOSE=true; shift ;;
            *)
                echo "Error: Unknown option: $1"
                usage ;;
        esac
    done
}

# Calculate average from array of numbers
calc_avg() {
    local sum=0 count=0
    for val in "$@"; do
        sum=$(echo "$sum + $val" | bc 2>/dev/null || echo "$((sum + val))")
        count=$((count + 1))
    done
    if [[ "$count" -eq 0 ]]; then echo 0; return; fi
    echo "scale=1; $sum / $count" | bc 2>/dev/null || echo "$((sum / count))"
}

# Determine score trajectory from array of scores
calc_trajectory() {
    local scores=("$@")
    local count=${#scores[@]}
    if [[ "$count" -lt 2 ]]; then
        echo "insufficient_data"
        return
    fi
    local first_half=0 second_half=0
    local mid=$((count / 2))
    for ((i = 0; i < mid; i++)); do
        first_half=$(echo "$first_half + ${scores[$i]}" | bc 2>/dev/null || echo "$((first_half + scores[i]))")
    done
    for ((i = mid; i < count; i++)); do
        second_half=$(echo "$second_half + ${scores[$i]}" | bc 2>/dev/null || echo "$((second_half + scores[i]))")
    done
    local avg_first=0 avg_second=0
    if [[ "$mid" -gt 0 ]]; then
        avg_first=$(echo "scale=1; $first_half / $mid" | bc 2>/dev/null || echo "0")
    fi
    local second_count=$((count - mid))
    if [[ "$second_count" -gt 0 ]]; then
        avg_second=$(echo "scale=1; $second_half / $second_count" | bc 2>/dev/null || echo "0")
    fi
    if (echo "$avg_second > $avg_first" | bc -l 2>/dev/null | grep -q 1); then
        echo "improving"
    elif (echo "$avg_second < $avg_first" | bc -l 2>/dev/null | grep -q 1); then
        echo "declining"
    else
        echo "stable"
    fi
}

main() {
    parse_args "$@"

    # Expand glob pattern
    # shellcheck disable=SC2206
    local files=($PATTERN)
    if [[ ${#files[@]} -eq 0 ]] || [[ ! -f "${files[0]}" ]]; then
        log_fail "No metrics files found matching: $PATTERN"
        exit 1
    fi

    if [[ "$VERBOSE" == true ]]; then
        log_info "Found ${#files[@]} metrics file(s)"
    fi

    # Extract and aggregate data
    local iterations_json="["
    local first=true
    local plan_scores=() exec_scores=() review_scores=()
    local bypass_scores=() normal_scores=()
    local bypass_durations=() normal_durations=()
    local bypass_blocked=0 normal_blocked=0
    local bypass_violations=0 normal_violations=0
    local all_scores=()
    local total_blocked=0

    for f in "${files[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            iterations_json+=","
        fi

        local content
        content=$(cat "$f")
        iterations_json+="$content"

        # Extract scores and metrics
        local perm_mode blocked plan_score exec_score review_score duration violations

        perm_mode=$(echo "$content" | jq -r '.permissions_mode' 2>/dev/null || echo "unknown")
        blocked=$(echo "$content" | jq -r '.blocked' 2>/dev/null || echo "false")
        plan_score=$(echo "$content" | jq -r '.phases.PLAN.score_combined // 0' 2>/dev/null || echo "0")
        exec_score=$(echo "$content" | jq -r '.phases.EXECUTE.score_combined // 0' 2>/dev/null || echo "0")
        review_score=$(echo "$content" | jq -r '.phases.REVIEW.score_combined // 0' 2>/dev/null || echo "0")
        duration=$(echo "$content" | jq -r '.duration_ms // 0' 2>/dev/null || echo "0")
        violations=$(echo "$content" | jq -r '.contract_compliance.field_access_violations + .contract_compliance.writing_order_violations' 2>/dev/null || echo "0")

        plan_scores+=("$plan_score")
        exec_scores+=("$exec_score")
        review_scores+=("$review_score")
        all_scores+=("$plan_score")

        if [[ "$blocked" == "true" ]]; then
            total_blocked=$((total_blocked + 1))
        fi

        if [[ "$perm_mode" == "bypass" ]]; then
            bypass_scores+=("$plan_score")
            bypass_durations+=("$duration")
            if [[ "$blocked" == "true" ]]; then
                bypass_blocked=$((bypass_blocked + 1))
            fi
            bypass_violations=$((bypass_violations + violations))
        else
            normal_scores+=("$plan_score")
            normal_durations+=("$duration")
            if [[ "$blocked" == "true" ]]; then
                normal_blocked=$((normal_blocked + 1))
            fi
            normal_violations=$((normal_violations + violations))
        fi
    done
    iterations_json+="]"

    # Compute summary stats
    local avg_plan avg_exec avg_review min_score max_score trajectory
    avg_plan=$(calc_avg "${plan_scores[@]}")
    avg_exec=$(calc_avg "${exec_scores[@]}")
    avg_review=$(calc_avg "${review_scores[@]}")

    min_score="${all_scores[0]}"
    max_score="${all_scores[0]}"
    for s in "${all_scores[@]}"; do
        if (echo "$s < $min_score" | bc -l 2>/dev/null | grep -q 1); then min_score="$s"; fi
        if (echo "$s > $max_score" | bc -l 2>/dev/null | grep -q 1); then max_score="$s"; fi
    done

    trajectory=$(calc_trajectory "${all_scores[@]}")

    local avg_bypass_score avg_normal_score
    local avg_bypass_dur avg_normal_dur
    avg_bypass_score=$(calc_avg "${bypass_scores[@]}")
    avg_normal_score=$(calc_avg "${normal_scores[@]}")
    avg_bypass_dur=$(calc_avg "${bypass_durations[@]}")
    avg_normal_dur=$(calc_avg "${normal_durations[@]}")

    # Build output JSON
    local output_json
    output_json=$(cat <<JSON
{
  "iterations": $iterations_json,
  "summary": {
    "total_iterations": ${#files[@]},
    "total_blocked": $total_blocked,
    "total_passed": $((${#files[@]} - total_blocked)),
    "avg_score_plan": $avg_plan,
    "avg_score_execute": $avg_exec,
    "avg_score_review": $avg_review,
    "min_score": $min_score,
    "max_score": $max_score,
    "score_trajectory": "$trajectory",
    "permission_comparison": {
      "bypass": {
        "avg_score": $avg_bypass_score,
        "avg_duration_ms": $avg_bypass_dur,
        "blocked_count": $bypass_blocked,
        "violations": $bypass_violations
      },
      "normal": {
        "avg_score": $avg_normal_score,
        "avg_duration_ms": $avg_normal_dur,
        "blocked_count": $normal_blocked,
        "violations": $normal_violations
      }
    }
  }
}
JSON
    )

    # Validate JSON
    if echo "$output_json" | jq . >/dev/null 2>&1; then
        if [[ -n "$OUTPUT_FILE" ]]; then
            echo "$output_json" | jq . > "$OUTPUT_FILE"
            log_pass "Metrics aggregated and saved to: $OUTPUT_FILE"
        else
            echo "$output_json" | jq .
        fi
    else
        log_fail "Generated invalid JSON — check input files"
        exit 1
    fi
}

main "$@"
