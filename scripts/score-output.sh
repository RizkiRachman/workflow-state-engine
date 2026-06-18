#!/usr/bin/env bash
# score-output.sh — Tier 1 scoring pipeline for orchestration contracts
#
# Automated Tier 1 rule-based checks from rules/rules.json scoring.tier1.
# Outputs JSON for consumption by Tier 2 (LLM-as-Judge) or direct verdict.
#
# Usage:
#   ./scripts/score-output.sh --file session/branch/contract.json
#   ./scripts/score-output.sh --file session/branch/contract.json --schema-invalid --permissions-violated
#   ./scripts/score-output.sh --file session/branch/contract.json --output /tmp/score.json
#
# Flags (all default to false — pass):
#   --schema-invalid           deduction -15
#   --permissions-violated   deduction -40
#   --blast-high             deduction -40
#   --writing-order-wrong    deduction -15
#   --fields-missing         deduction -15
#   --over-engineered        deduction -15
#
# Output JSON:
#   {"tier1":{"deductions":{...},"subtotal":N},"combined":N,"verdict":"PASS|RETRY|BLOCKED"}
#
# Exit codes:
#   0 = PASS   (combined ≥ 70)
#   1 = RETRY  (combined 50-69)
#   1 = BLOCKED (combined < 50)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Defaults ----------------------------------------------------------------
CONTRACT_FILE=""
OUTPUT_FILE=""
VERBOSE=false

# Deduction amounts from rules/rules.json scoring.tier1
declare -r DEDUCT_SCHEMA_VALID=15
declare -r DEDUCT_PERMISSIONS_VIOLATED=40
declare -r DEDUCT_BLAST_HIGH=40
declare -r DEDUCT_WRITING_ORDER_WRONG=15
declare -r DEDUCT_FIELDS_MISSING=15
declare -r DEDUCT_OVER_ENGINEERED=15
declare -r SUBTOTAL_THRESHOLD=70
declare -r MAX_SCORE=100

# Flag state (default: all false = no deductions)
SCHEMA_VALID=false
PERMISSIONS_VIOLATED=false
BLAST_HIGH=false
WRITING_ORDER_WRONG=false
FIELDS_MISSING=false
OVER_ENGINEERED=false

# --- Functions ---------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [FLAGS...]

Automated Tier 1 rule-based scoring for orchestration contracts.
Implements the scoring.tier1 rules from rules/rules.json.

Options:
  --file PATH         Contract JSON file to validate (required)
  --output PATH       Write JSON output to file (optional)
  --help              Show this help message and exit

Scoring Flags (each flag triggers a deduction from 100):
  --schema-invalid           deduct ${DEDUCT_SCHEMA_VALID} (schema validation failed)
  --permissions-violated   deduct ${DEDUCT_PERMISSIONS_VIOLATED} (agent violated permissions)
  --blast-high             deduct ${DEDUCT_BLAST_HIGH} (blast radius HIGH/CRITICAL)
  --writing-order-wrong    deduct ${DEDUCT_WRITING_ORDER_WRONG} (wrong file creation order)
  --fields-missing         deduct ${DEDUCT_FIELDS_MISSING} (required fields missing)
  --over-engineered        deduct ${DEDUCT_OVER_ENGINEERED} (YAGNI violations detected)

Scoring Logic:
  - All flags default to false (pass, no deduction)
  - Flag present = deduction applied
  - Subtotals below ${SUBTOTAL_THRESHOLD} skip Tier 2 (LLM-as-Judge)
  - Verdict thresholds: ≥${SUBTOTAL_THRESHOLD}=PASS, 50-69=RETRY, <50=BLOCKED

Exit Codes:
  0  = PASS (combined ≥ ${SUBTOTAL_THRESHOLD})
  1  = RETRY or BLOCKED (combined < ${SUBTOTAL_THRESHOLD})

Examples:
  $(basename "$0") --file session/branch/contract.json
  $(basename "$0") --file session/branch/contract.json --schema-invalid
  $(basename "$0") --file contract/contract.template.json --schema-invalid --blast-high
  $(basename "$0") --file contract.json --output /tmp/score.json --fields-missing --over-engineered
EOF
    exit 0
}

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# --- Parse arguments ---------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)
            CONTRACT_FILE="$2"
            shift 2
            ;;
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --schema-invalid)
            SCHEMA_VALID=true
            shift
            ;;
        --permissions-violated)
            PERMISSIONS_VIOLATED=true
            shift
            ;;
        --blast-high)
            BLAST_HIGH=true
            shift
            ;;
        --writing-order-wrong)
            WRITING_ORDER_WRONG=true
            shift
            ;;
        --fields-missing)
            FIELDS_MISSING=true
            shift
            ;;
        --over-engineered)
            OVER_ENGINEERED=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            die "Unknown option: $1. Use --help for usage."
            ;;
    esac
done

# --- Validate arguments ------------------------------------------------------

if [[ -z "$CONTRACT_FILE" ]]; then
    die "Missing required argument: --file <path>. Use --help for usage."
fi

if [[ ! -f "$CONTRACT_FILE" ]]; then
    die "File not found: $CONTRACT_FILE"
fi

# --- Compute Tier 1 score ----------------------------------------------------

# Build deductions map (only include flagged items)
DEDUCTIONS_MAP=""
DEDUCTION_TOTAL=0

if [[ "$SCHEMA_VALID" == true ]]; then
    DEDUCTIONS_MAP="${DEDUCTIONS_MAP}\"schema_invalid\":${DEDUCT_SCHEMA_VALID},"
    DEDUCTION_TOTAL=$((DEDUCTION_TOTAL + DEDUCT_SCHEMA_VALID))
fi

if [[ "$PERMISSIONS_VIOLATED" == true ]]; then
    DEDUCTIONS_MAP="${DEDUCTIONS_MAP}\"permissions_violated\":${DEDUCT_PERMISSIONS_VIOLATED},"
    DEDUCTION_TOTAL=$((DEDUCTION_TOTAL + DEDUCT_PERMISSIONS_VIOLATED))
fi

if [[ "$BLAST_HIGH" == true ]]; then
    DEDUCTIONS_MAP="${DEDUCTIONS_MAP}\"blast_high\":${DEDUCT_BLAST_HIGH},"
    DEDUCTION_TOTAL=$((DEDUCTION_TOTAL + DEDUCT_BLAST_HIGH))
fi

if [[ "$WRITING_ORDER_WRONG" == true ]]; then
    DEDUCTIONS_MAP="${DEDUCTIONS_MAP}\"writing_order_wrong\":${DEDUCT_WRITING_ORDER_WRONG},"
    DEDUCTION_TOTAL=$((DEDUCTION_TOTAL + DEDUCT_WRITING_ORDER_WRONG))
fi

if [[ "$FIELDS_MISSING" == true ]]; then
    DEDUCTIONS_MAP="${DEDUCTIONS_MAP}\"fields_missing\":${DEDUCT_FIELDS_MISSING},"
    DEDUCTION_TOTAL=$((DEDUCTION_TOTAL + DEDUCT_FIELDS_MISSING))
fi

if [[ "$OVER_ENGINEERED" == true ]]; then
    DEDUCTIONS_MAP="${DEDUCTIONS_MAP}\"over_engineered\":${DEDUCT_OVER_ENGINEERED},"
    DEDUCTION_TOTAL=$((DEDUCTION_TOTAL + DEDUCT_OVER_ENGINEERED))
fi

# Remove trailing comma from deductions map, or set to empty object
if [[ -n "$DEDUCTIONS_MAP" ]]; then
    DEDUCTIONS_MAP="{${DEDUCTIONS_MAP%?}}"
else
    DEDUCTIONS_MAP="{}"
fi

SUBTOTAL=$((MAX_SCORE - DEDUCTION_TOTAL))
if [[ $SUBTOTAL -lt 0 ]]; then
    SUBTOTAL=0
fi

# --- Determine verdict -------------------------------------------------------

# Tier 1 subtotal < threshold → combined = subtotal (skip Tier 2)
# Tier 1 subtotal ≥ threshold → output subtotal for Tier 2 consumption
COMBINED=$SUBTOTAL

if [[ $COMBINED -ge $SUBTOTAL_THRESHOLD ]]; then
    VERDICT="PASS"
    EXIT_CODE=0
elif [[ $COMBINED -ge 50 ]]; then
    VERDICT="RETRY"
    EXIT_CODE=1
else
    VERDICT="BLOCKED"
    EXIT_CODE=1
fi

# --- Build JSON output -------------------------------------------------------

# Build JSON manually for portability (no jq dependency)
JSON_OUTPUT="{\"tier1\":{\"deductions\":${DEDUCTIONS_MAP},\"subtotal\":${SUBTOTAL}},\"combined\":${COMBINED},\"verdict\":\"${VERDICT}\"}"

# --- Output ------------------------------------------------------------------

# Always print to stdout
echo "$JSON_OUTPUT"

# Optionally write to file
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$JSON_OUTPUT" > "$OUTPUT_FILE"
    [[ "$VERBOSE" == true ]] && echo "[INFO] Score written to: $OUTPUT_FILE" >&2
fi

exit $EXIT_CODE