#!/usr/bin/env bash
# validate-meta-contract.sh — Multi-service meta-contract validation
# Validates cross-service orchestration contracts: ensures service types,
# score thresholds, and ponytail debt limits are consistent across services.
#   ./scripts/validate-meta-contract.sh [OPTIONS]
#   --dir DIR            Root dir containing service contract subdirs (default: session/)
#   --services LIST      Comma-separated service names to validate (e.g. "api,dashboard,deployer")
#   --help               Show usage
#   0 — All contracts valid
#   1 — Validation warnings
#   2 — Validation failures (blocking)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$PROJECT_DIR/session"
SERVICES=""
VERBOSE=false
EXIT_CODE=0

if [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; NC=''
fi

usage() {
    cat <<EOF
${CYAN}validate-meta-contract.sh${NC} — Multi-service meta-contract validation
Usage: $(basename "$0") [OPTIONS]
  --dir DIR         Root dir containing service contract subdirs (default: session/)
  --services LIST   Comma-separated service names (e.g. "api,dashboard,deployer")
  --verbose         Detailed output
  --help            Show this help
Exit codes:
  0   All contracts valid
  1   Validation warnings
  2   Validation failures (blocking)
Examples:
  $(basename "$0") --services api,dashboard
  $(basename "$0") --dir session/ --services api,deployer --verbose
EOF
    exit 2
}

log_pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $1"; EXIT_CODE=2; }
log_warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; [[ $EXIT_CODE -eq 0 ]] && EXIT_CODE=1; }
log_info() { if [[ "$VERBOSE" == true ]]; then echo -e "  ${CYAN}[INFO]${NC} $1"; fi; }

validate_service_contract() {
    local service="$1"
    local contract_file="$ROOT_DIR/$service/contract.json"
    local passed=true

    log_info "Validating service: $service"

    if [[ ! -f "$contract_file" ]]; then
        log_warn "Service '$service': No contract.json found at $contract_file"
        return
    fi

    if ! command -v jq &>/dev/null; then
        log_fail "jq not available — cannot parse contracts"
        return
    fi

    local state score
    state=$(jq -r '.state // "unknown"' "$contract_file" 2>/dev/null || echo "unknown")
    score=$(jq -r '.score.combined // 0' "$contract_file" 2>/dev/null || echo "0")

    log_info "  State: $state, Score: $score"

    # Check 1: Verify contract is valid JSON
    if ! jq . "$contract_file" >/dev/null 2>&1; then
        log_fail "Service '$service': Invalid JSON in contract"
        passed=false
    fi

    # Check 2: State must be a valid machine state
    local valid_states='INIT PLAN PLAN_SCORED PONYTAIL_CHECK EXECUTE EXECUTE_SCORED REVIEW REVIEW_SCORED COMPLETE BLOCKED'
    if ! echo "$valid_states" | grep -qw "$state"; then
        log_fail "Service '$service': Invalid state '$state'"
        passed=false
    fi

    # Check 3: Service type must be defined in contract
    local service_type
    service_type=$(jq -r '.service_type // empty' "$contract_file" 2>/dev/null || echo "")
    local valid_types='Core UI Support Infrastructure'
    if [[ -n "$service_type" ]]; then
        if ! echo "$valid_types" | grep -qw "$service_type"; then
            log_warn "Service '$service': Unknown service_type '$service_type' (expected: Core|UI|Support|Infrastructure)"
        fi
    fi

    # Check 4: Score thresholds per service type
    local min_score=0
    case "$service_type" in
        Core|Infrastructure) min_score=75 ;;
        UI) min_score=70 ;;
        Support) min_score=65 ;;
        *) min_score=50 ;;
    esac
    if (( $(echo "$score < $min_score" | bc -l 2>/dev/null || echo 1) )); then
        if [[ "$score" != "0" && "$state" != "INIT" && "$state" != "BLOCKED" ]]; then
            log_warn "Service '$service' ($service_type): Score $score below minimum $min_score"
        fi
    fi

    # Check 5: Debt items within service-type limits
    local max_debt=5
    case "$service_type" in
        Core) max_debt=3 ;;
        UI) max_debt=5 ;;
        Support) max_debt=8 ;;
        Infrastructure) max_debt=2 ;;
    esac
    local debt_count
    debt_count=$(jq '.ponytail.debt_items | length // 0' "$contract_file" 2>/dev/null || echo "0")
    if [[ "$debt_count" -gt "$max_debt" ]]; then
        log_warn "Service '$service' ($service_type): Debt items $debt_count exceeds max $max_debt"
    fi

    if [[ "$passed" == true ]]; then
        log_pass "Service '$service': Valid ($service_type, state=$state, score=$score)"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir) ROOT_DIR="$2"; shift 2 ;;
        --services) SERVICES="$2"; shift 2 ;;
        --verbose) VERBOSE=true; shift ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

echo "=== Meta-Contract Validation ==="
echo "Root dir: $ROOT_DIR"

if [[ -z "$SERVICES" ]]; then
    # Auto-detect services from session/ subdirectories
    for d in "$ROOT_DIR"/*/; do
        local name
        name=$(basename "$d")
        [[ -f "$d/contract.json" ]] && SERVICES_LIST+=("$name")
    done
else
    IFS=',' read -ra SERVICES_LIST <<< "$SERVICES"
fi

if [[ ${#SERVICES_LIST[@]} -eq 0 ]]; then
    log_info "No services found in $ROOT_DIR — nothing to validate"
    echo -e "${GREEN}Meta-contract validation: Nothing to validate.${NC}"
    exit 0
fi

echo "Services: ${SERVICES_LIST[*]}"
echo ""

for svc in "${SERVICES_LIST[@]}"; do
    svc=$(echo "$svc" | xargs)  # trim whitespace
    validate_service_contract "$svc"
    echo ""
done

if [[ $EXIT_CODE -eq 0 ]]; then
    echo -e "${GREEN}All meta-contracts valid.${NC}"
elif [[ $EXIT_CODE -eq 1 ]]; then
    echo -e "${YELLOW}Meta-contract validation completed with warnings.${NC}"
else
    echo -e "${RED}Meta-contract validation FAILED.${NC}"
fi

exit $EXIT_CODE