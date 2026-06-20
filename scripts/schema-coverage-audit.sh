#!/usr/bin/env bash
# schema-coverage-audit.sh — Schema ↔ Template Field Coverage Audit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_FILE="$PROJECT_DIR/contract/contract.template.json"
SCHEMA_FILE="$PROJECT_DIR/contract/contract.schema.json"
VERBOSE=false

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

usage() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo "Compare JSON Schema vs template for field coverage gaps."
    echo "  --template PATH    Path to contract template JSON"
    echo "  --schema PATH      Path to contract schema JSON"
    echo "  --verbose          Show all fields grouped by status"
    echo "  --help             Show this help message"
    exit 0
}

# Extract leaf field paths from flat JSON (recursive). Skip $schema.
extract_template_paths() {
    jq -r '
        def leaf:
            [path(..) | select(length > 0)
             | select(.[-1] | type == "string")
             | select(.[0] != "$schema")
             | [.[] | tostring] | join(".")]
            | unique | .[];
        leaf
    ' "$1" | sort -u
}

# Extract property paths from JSON Schema recursively
extract_schema_paths() {
    jq -r '
        def collect($prefix):
            if has("properties") then
                .properties | to_entries[] |
                select(.key != "$schema" and .key != "definitions" and .key != "$defs") |
                .key as $k |
                ($prefix + [$k] | join(".")),
                if .value | has("properties") then
                    (.value | collect($prefix + [$k]))
                elif .value | has("items") and (.value.items | has("properties")) then
                    (.value.items | collect($prefix + [$k]))
                else empty end
            else empty end;
        collect([])
    ' "$1" | sort -u
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --template) TEMPLATE_FILE="$2"; shift 2 ;;
            --schema) SCHEMA_FILE="$2"; shift 2 ;;
            --verbose) VERBOSE=true; shift ;;
            --help|-h) usage ;;
            *) echo "Unknown: $1"; usage ;;
        esac
    done
    [[ -f "$TEMPLATE_FILE" ]] || { echo "ERROR: Template not found: $TEMPLATE_FILE" >&2; exit 2; }
    [[ -f "$SCHEMA_FILE" ]] || { echo "ERROR: Schema not found: $SCHEMA_FILE" >&2; exit 2; }

    mapfile -t tpaths < <(extract_template_paths "$TEMPLATE_FILE")
    mapfile -t spaths < <(extract_schema_paths "$SCHEMA_FILE")

    declare -A in_t in_s
    for p in "${tpaths[@]}"; do in_t["$p"]=1; done
    for p in "${spaths[@]}"; do in_s["$p"]=1; done

    only_t=(); only_s=(); covered=()
    for p in "${tpaths[@]}"; do
        [[ -n "${in_s[$p]:-}" ]] && covered+=("$p") || only_t+=("$p")
    done
    for p in "${spaths[@]}"; do
        [[ -z "${in_t[$p]:-}" ]] && only_s+=("$p")
    done

    total=${#covered[@]}; total=$((total + ${#only_t[@]}))
    cov=0; [[ $total -gt 0 ]] && cov=$(( (${#covered[@]} * 100) / total ))

    echo "=========================================="
    echo " Schema Coverage Audit Report"
    echo "=========================================="
    echo " Template: $TEMPLATE_FILE"
    echo " Schema:   $SCHEMA_FILE"
    echo "------------------------------------------"
    echo " Total fields:     $total"
    echo " Covered:          ${#covered[@]}"
    echo " Coverage:         ${cov}%"
    echo " Missing (schema): ${#only_t[@]}"
    echo " Missing (tmplte): ${#only_s[@]}"
    echo "------------------------------------------"

    [[ ${#only_t[@]} -gt 0 ]] && { echo ""; echo "Fields in template but NOT in schema:"; for p in "${only_t[@]}"; do echo "  - $p"; done; }
    [[ ${#only_s[@]} -gt 0 ]] && { echo ""; echo "Fields in schema but NOT in template:"; for p in "${only_s[@]}"; do echo "  - $p"; done; }
    [[ "$VERBOSE" == true && ${#covered[@]} -gt 0 ]] && { echo ""; echo "Covered fields (${#covered[@]}):"; for p in "${covered[@]}"; do echo "  ✓ $p"; done; }

    echo ""
    if [[ $cov -ge 95 ]]; then
        echo -e "${GREEN}VERDICT: PASS (${cov}% ≥ 95%)${NC}"; exit 0
    elif [[ $cov -ge 80 ]]; then
        echo -e "${YELLOW}VERDICT: WARN (${cov}% ≥ 80%)${NC}"; exit 1
    else
        echo -e "${RED}VERDICT: FAIL (${cov}% < 80%)${NC}"; exit 2
    fi
}

main "$@"