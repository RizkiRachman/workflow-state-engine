#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# generate-config.sh — Generate downstream agent configuration files
#
# Reads from opencode.json.template (or fallback agent list) and generates
# individual agent config files, or a skills.json mapping agents to skills.
#
# Usage:
#   ./scripts/generate-config.sh                          # Generate all agent configs
#   ./scripts/generate-config.sh --type agent             # Generate agent configs only
#   ./scripts/generate-config.sh --type skill             # Generate skills.json only
#   ./scripts/generate-config.sh --type full              # Generate both
#   ./scripts/generate-config.sh --output ./dist          # Custom output directory
#   ./scripts/generate-config.sh --list                   # List known agents
#   ./scripts/generate-config.sh --help                   # Show usage
#   ./scripts/generate-config.sh --verbose                # Detailed output
#   ./scripts/generate-config.sh --dry-run                # Preview without writing
#
# Exit codes:
#   0 — Success
#   1 — Partial failure
#   2 — Error (missing deps, invalid opts, etc.)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Config ──────────────────────────────────────────────────────────────────
GENERATE_TYPE=""
OUTPUT_DIR=""
LIST_ONLY=false
HELP=false
VERBOSE=false
DRY_RUN=false
EXIT_CODE=0

# Known agents (fallback if opencode.json.template is missing)
KNOWN_AGENTS=(
  "tech-lead"
  "system-analyst"
  "developer"
  "developer-fixer"
  "quality-analyst"
  "system-analyst"
  "developer-explorer"
  "developer-librarian"
  "software-architect"
  "quality-analyst-learner"
  "developer-council"
  "developer-observer"
)

# Color output (disable if not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    BOLD=''
    NC=''
fi

# ── Help ────────────────────────────────────────────────────────────────────
usage() {
    cat <<'USAGE'
generate-config.sh — Generate downstream agent configuration files

SYNOPSIS
    ./scripts/generate-config.sh [OPTIONS]

OPTIONS
    --type TYPE      What to generate: agent (agent configs only),
                     skill (skills.json only), full (both). Default: full
    --output DIR     Output directory (default: .opencode/)
    --list           List known agents and exit without generating
    --help           Show this help message and exit
    --verbose        Detailed output during generation
    --dry-run        Preview what would be generated without writing files

DESCRIPTION
    Generates agent configuration files for downstream consumers.

    Reads opencode.json.template from the project root and extracts the
    `agent` section to produce individual agent config files. If the template
    file does not exist, a minimal configuration is generated from the
    known agents list.

    With --type skill, reads contract/superpowers-contract.json to produce
    a skills.json mapping each agent to its applicable skills.

    With --type full (default), generates both agent configs and skills.json.

EXIT CODES
    0   Success
    1   Partial failure (some artifacts generated, some failed)
    2   Error (missing dependencies, invalid options, etc.)

EXAMPLES
    ./scripts/generate-config.sh
    ./scripts/generate-config.sh --type agent --output ./dist
    ./scripts/generate-config.sh --type skill
    ./scripts/generate-config.sh --type skill --output ./dist
    ./scripts/generate-config.sh --list --verbose
    ./scripts/generate-config.sh --type full --dry-run --verbose

USAGE
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

log_dry() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${CYAN}[DRY-RUN]${NC} $1"
    fi
}

log_section() {
    echo ""
    echo -e "${BOLD}$1${NC}"
    echo "  $(printf '%*s' "$((${#1} + 2))" '' | tr ' ' '─')"
}

# ── Helper functions ────────────────────────────────────────────────────────

# Get unique sorted agent names from opencode.json.template's agent section
extract_agents_from_template() {
    local template="$1"
    jq -r '.agent | keys[]' "$template" 2>/dev/null | sort -u || true
}

# Get unique sorted agent names from known list (deduplicated)
get_known_agents_uniq() {
    printf '%s\n' "${KNOWN_AGENTS[@]}" | sort -u
}

# Generate a single agent config file from template data
generate_agent_config() {
    local agent_name="$1"
    local output_dir="$2"
    local template="$3"
    local output_file="${output_dir}/${agent_name}.json"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would create: ${output_file}"
        return 0
    fi

    # Extract agent config from template if available
    if [[ -n "$template" ]] && jq -e ".agent[\"${agent_name}\"]" "$template" >/dev/null 2>&1; then
        jq --arg name "$agent_name" \
           '.agent[$name] | {agent: $name, config: .}' \
           "$template" > "$output_file" 2>/dev/null || {
            log_fail "Failed to extract config for agent: ${agent_name}"
            return 1
        }
    else
        # Generate minimal config
        cat > "$output_file" <<CONF
{
  "agent": "${agent_name}",
  "config": {
    "model": "YOUR_MODEL_ID",
    "temperature": 0,
    "top_p": 1,
    "steps": 30
  }
}
CONF
    fi

    log_pass "Generated: ${output_file}"
    return 0
}

# Generate skills.json from superpowers-contract.json
generate_skills_config() {
    local output_dir="$1"
    local super_contract="$2"
    local output_file="${output_dir}/skills.json"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would create: ${output_file}"
        log_dry "  Source: ${super_contract}"
        return 0
    fi

    if [[ ! -f "$super_contract" ]]; then
        log_fail "superpowers-contract.json not found at: ${super_contract}"
        return 1
    fi

    # Check if agent_to_skill_mapping exists
    if ! jq -e '.agent_to_skill_mapping' "$super_contract" >/dev/null 2>&1; then
        log_fail "agent_to_skill_mapping not found in: ${super_contract}"
        return 1
    fi

    jq '{agent_to_skill_mapping}' "$super_contract" > "$output_file" 2>/dev/null || {
        log_fail "Failed to extract skills mapping from: ${super_contract}"
        return 1
    }

    log_pass "Generated: ${output_file}"
    return 0
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    local template="$PROJECT_DIR/opencode.json.template"
    local super_contract="$PROJECT_DIR/contract/superpowers-contract.json"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                HELP=true
                shift
                ;;
            --type)
                shift
                GENERATE_TYPE="$1"
                if [[ "$GENERATE_TYPE" != "agent" && "$GENERATE_TYPE" != "skill" && "$GENERATE_TYPE" != "full" ]]; then
                    echo -e "${RED}Error:${NC} --type must be agent, skill, or full (got: ${GENERATE_TYPE})" >&2
                    echo "Try '$(basename "$0") --help' for more info." >&2
                    exit 2
                fi
                shift
                ;;
            --output)
                shift
                OUTPUT_DIR="$1"
                shift
                ;;
            --list)
                LIST_ONLY=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
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
        exit 0
    fi

    # Default type to "full" if not specified
    if [[ -z "$GENERATE_TYPE" ]]; then
        GENERATE_TYPE="full"
    fi

    # Default output directory
    if [[ -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="$PROJECT_DIR/.opencode"
    fi

    # Resolve absolute path for output
    if [[ ! "$OUTPUT_DIR" = /* ]]; then
        OUTPUT_DIR="$PROJECT_DIR/$OUTPUT_DIR"
    fi

    log_section "generate-config.sh — Config Generator"
    echo -e "  Type:           ${CYAN}${GENERATE_TYPE}${NC}"
    echo -e "  Output:         ${CYAN}${OUTPUT_DIR}${NC}"
    echo -e "  Template:       ${CYAN}$(test -f "$template" && echo "found" || echo "missing")${NC}"
    echo -e "  Superpowers:    ${CYAN}$(test -f "$super_contract" && echo "found" || echo "missing")${NC}"
    echo -e "  Verbose:        ${CYAN}${VERBOSE}${NC}"
    echo -e "  Dry-run:        ${CYAN}${DRY_RUN}${NC}"

    # --- List mode ---
    if [[ "$LIST_ONLY" == true ]]; then
        log_section "Known Agents"
        if [[ -f "$template" ]]; then
            echo "  (from opencode.json.template)"
            echo ""
            while IFS= read -r agent; do
                echo "  - ${agent}"
            done <<< "$(extract_agents_from_template "$template")"
        else
            echo "  (from fallback known list)"
            echo ""
            while IFS= read -r agent; do
                echo "  - ${agent}"
            done <<< "$(get_known_agents_uniq)"
        fi
        exit 0
    fi

    # Check for jq
    if ! command -v jq &>/dev/null; then
        log_fail "jq is required but not installed."
        exit 2
    fi

    # Create output directory if needed
    if [[ ! -d "$OUTPUT_DIR" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log_dry "Would create directory: ${OUTPUT_DIR}"
        else
            mkdir -p "$OUTPUT_DIR"
            log_pass "Created output directory: ${OUTPUT_DIR}"
        fi
    fi

    # --- Generate agent configs ---
    if [[ "$GENERATE_TYPE" == "agent" || "$GENERATE_TYPE" == "full" ]]; then
        log_section "Generating Agent Configs"

        local agents=()
        if [[ -f "$template" ]]; then
            log_verbose "Reading agents from: ${template}"
            while IFS= read -r agent; do
                agents+=("$agent")
            done <<< "$(extract_agents_from_template "$template")"
        else
            log_info "opencode.json.template not found — using fallback known agents"
            while IFS= read -r agent; do
                agents+=("$agent")
            done <<< "$(get_known_agents_uniq)"
        fi

        if [[ ${#agents[@]} -eq 0 ]]; then
            log_fail "No agents found (template empty and known agents list empty)"
            EXIT_CODE=2
        else
            log_verbose "Found ${#agents[@]} agents"

            local template_path=""
            [[ -f "$template" ]] && template_path="$template"

            local success_count=0
            local fail_count=0
            for agent in "${agents[@]}"; do
                if generate_agent_config "$agent" "$OUTPUT_DIR" "$template_path"; then
                    success_count=$((success_count + 1))
                else
                    fail_count=$((fail_count + 1))
                fi
            done

            echo ""
            echo -e "  $(printf '%d generated, %d failed' "$success_count" "$fail_count")"

            if [[ "$fail_count" -gt 0 ]]; then
                EXIT_CODE=1
            fi
        fi
    fi

    # --- Generate skills.json ---
    if [[ "$GENERATE_TYPE" == "skill" || "$GENERATE_TYPE" == "full" ]]; then
        log_section "Generating Skills Config"
        if generate_skills_config "$OUTPUT_DIR" "$super_contract"; then
            log_pass "Skills config generated"
        else
            log_fail "Skills config generation failed"
            EXIT_CODE=1
        fi
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_section "Dry-Run Summary"
        log_info "No files were modified (--dry-run was set)"
    else
        log_section "Done"
        log_pass "Output directory: ${OUTPUT_DIR}"
        if [[ "$GENERATE_TYPE" == "agent" || "$GENERATE_TYPE" == "full" ]]; then
            log_pass "Agent configs generated"
        fi
        if [[ "$GENERATE_TYPE" == "skill" || "$GENERATE_TYPE" == "full" ]]; then
            log_pass "Skills config generated"
        fi
    fi

    exit "$EXIT_CODE"
}

main "$@"
