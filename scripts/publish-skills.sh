#!/usr/bin/env bash
# publish-skills.sh — Generate skills catalog from superpowers-contract.json (G9)
# Reads contract/superpowers-contract.json and generates a markdown catalog
# (skills/CATALOG.md) and/or a JSON index (skills/skills.json) with all skills,
# descriptions, usage guidelines, and installation instructions.
#   ./scripts/publish-skills.sh                          # Generate catalog (default)
#   ./scripts/publish-skills.sh --help                    # Show usage
#   ./scripts/publish-skills.sh --type catalog            # Generate CATALOG.md only
#   ./scripts/publish-skills.sh --type json               # Generate skills.json only
#   ./scripts/publish-skills.sh --type full               # Generate both
#   ./scripts/publish-skills.sh --output /path/to/skills   # Custom output dir
#   ./scripts/publish-skills.sh --dry-run                 # Show what would be done
#   ./scripts/publish-skills.sh --verbose                 # Detailed output
#   0 — Published successfully
#   1 — Partial success (some files missing or warnings)
#   2 — Error (source missing, write failure, critical issues)
#   3 — Usage displayed
# Requirements:
#   - bash 4+
#   - jq (for parsing superpowers-contract.json)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Color output (disable if not a terminal) ---
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    CYAN=''
    NC=''
fi

# --- Defaults ---
VERBOSE=false
DRY_RUN=false
OUTPUT_DIR="$PROJECT_ROOT/skills"
OUTPUT_TYPE="catalog"   # catalog | json | full
EXIT_CODE=0

# --- Source contract ---
CONTRACT_FILE="$PROJECT_ROOT/contract/superpowers-contract.json"

# --- Logging functions ---
log_pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $1" >&2; EXIT_CODE=1; }
log_info() { echo -e "  ${YELLOW}[INFO]${NC} $1"; }
log_verbose() { if [[ "$VERBOSE" == true ]]; then echo -e "  ${CYAN}[VERB]${NC} $1"; fi; }
log_dry()   { echo -e "  ${CYAN}[DRY-RUN]${NC} $1"; }

# --- Usage ---
usage() {
    cat <<'USAGE'
publish-skills.sh — Generate skills catalog from superpowers-contract.json (G9)

Reads the superpowers contract and generates a markdown catalog and/or JSON
index of all available skills, their descriptions, usage, and installation.

Usage:
    ./scripts/publish-skills.sh [OPTIONS]

Options:
    --type TYPE     Output type: catalog (default), json, full
                    catalog = CATALOG.md only
                    json    = skills.json only
                    full    = both CATALOG.md and skills.json
    --output PATH   Output directory (default: skills/)
    --dry-run       Show what would be done without modifying anything
    --verbose       Print detailed output for each step
    --help          Show this usage information

Exit codes:
    0 — Published successfully
    1 — Partial success (some files missing or warnings)
    2 — Error (source missing, write failure, critical issues)

Examples:
    ./scripts/publish-skills.sh
    ./scripts/publish-skills.sh --type full --verbose
    ./scripts/publish-skills.sh --type json
    ./scripts/publish-skills.sh --output /tmp/skills --dry-run
USAGE
    exit 3
}

# --- Dependency checks ---
check_deps() {
    local missing=false

    if ! command -v jq &>/dev/null; then
        log_fail "jq is required but not installed"
        missing=true
    fi

    if [[ "$missing" == true ]]; then
        log_fail "Missing required dependencies. Install jq first."
        exit 2
    fi

    log_pass "All dependencies available (jq)"
}

# --- Read skills from contract ---
# Returns JSON array of skill objects from the contract's skills array.
read_skills() {
    local contract="$1"

    if [[ ! -f "$contract" ]]; then
        log_fail "Contract file not found: $contract"
        exit 2
    fi

    local skills_json
    # Skills live under "superpowers_skills" key. Fall back to "skills" for
    # backward compatibility with other contract versions.
    skills_json="$(jq -c '.superpowers_skills // .skills // []' "$contract" 2>/dev/null || true)"

    if [[ -z "$skills_json" || "$skills_json" == "[]" ]]; then
        log_fail "No skills found in contract (skills array is empty or missing)"
        exit 2
    fi

    local count
    count="$(echo "$skills_json" | jq length 2>/dev/null || echo "0")"
    log_pass "Read ${count} skills from: $contract" >&2
    echo "$skills_json"
}

# --- Get skill field safely ---
get_skill_field() {
    local json="$1"
    local field="$2"
    local default="${3:-}"

    local val
    val="$(echo "$json" | jq -r ".${field} // \"$default\"" 2>/dev/null || echo "$default")"
    echo "$val"
}

# --- Discover skill directories on disk ---
discover_skill_dirs() {
    local skills_root="$1"
    local -a dirs=()

    if [[ ! -d "$skills_root" ]]; then
        log_verbose "Skills directory does not exist: $skills_root" >&2
        echo ""
        return 0
    fi

    local entry
    for entry in "$skills_root"/*/; do
        local dirname
        dirname="$(basename "$entry")"
        dirs+=("$dirname")
    done

    echo "${dirs[@]}"
}

# --- Check which skills exist on disk ---
check_skill_on_disk() {
    local skill_name="$1"
    local skills_root="$2"

    local dir_name="${skill_name// /-}"
    dir_name="$(echo "$dir_name" | tr '[:upper:]' '[:lower:]')"

    if [[ -f "$skills_root/$dir_name/SKILL.md" ]]; then
        echo "installed"
    elif [[ -d "$skills_root/$dir_name" ]]; then
        echo "exists"
    else
        echo "missing"
    fi
}

# --- Generate CATALOG.md ---
generate_catalog() {
    local skills_json="$1"
    local output_file="$2"
    local skills_root="$3"
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local skill_count
    skill_count="$(echo "$skills_json" | jq length)"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would write catalog to: $output_file"
        log_dry "  Skills: $skill_count"
        return 0
    fi

    mkdir -p "$(dirname "$output_file")"

    # Write header
    cat > "$output_file" <<HEADER
# Skills Catalog — Workflow State Engine

> Auto-generated from \`contract/superpowers-contract.json\`.
> Generated: $timestamp
> Total skills: $skill_count

This catalog lists every skill available to agents in the Workflow State Engine
orchestration framework. Skills provide specialized instructions and workflows
for specific tasks (analysis, planning, coding, review, debugging, etc.).

## Table of Contents

HEADER

    # Write TOC
    echo "$skills_json" | jq -c '.[]' | while IFS= read -r skill; do
        local name
        name="$(get_skill_field "$skill" "name" "unnamed")"
        local anchor
        anchor="$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"
        echo "- [$name](#$anchor)" >> "$output_file"
    done

    echo "" >> "$output_file"
    echo "---" >> "$output_file"
    echo "" >> "$output_file"

    # Write each skill section
    echo "$skills_json" | jq -c '.[]' | while IFS= read -r skill; do
        local name purpose when_to_use skill_cmd tools appliesto status
        name="$(get_skill_field "$skill" "name" "unnamed")"
        purpose="$(get_skill_field "$skill" "purpose" "No description provided.")"
        when_to_use="$(get_skill_field "$skill" "when_to_use" "No usage guidance.")"
        skill_cmd="$(get_skill_field "$skill" "skill_cmd" "")"
        tools="$(get_skill_field "$skill" "tools" "")"
        appliesto="$(echo "$skill" | jq -r '.applies_to // [] | join(", ")' 2>/dev/null || echo "")"
        status="$(check_skill_on_disk "$name" "$skills_root")"

        cat >> "$output_file" <<SECTION
## ${name}

**Status:** ${status}
SECTION

        if [[ -n "$appliesto" ]]; then
            echo "" >> "$output_file"
            echo "**Applies to:** ${appliesto}" >> "$output_file"
        fi

        cat >> "$output_file" <<SECTION

**Purpose:** ${purpose}

**When to use:** ${when_to_use}

SECTION

        if [[ -n "$skill_cmd" ]]; then
            cat >> "$output_file" <<SECTION
**Load command:** \`${skill_cmd}\`

SECTION
        fi

        if [[ -n "$tools" ]]; then
            echo "**Tools:**" >> "$output_file"
            echo "$tools" | jq -r '.[]' 2>/dev/null | while IFS= read -r tool; do
                echo "- \`${tool}\`" >> "$output_file"
            done
            echo "" >> "$output_file"
        fi

        # Installation instructions based on status
        if [[ "$status" == "missing" ]]; then
            cat >> "$output_file" <<INSTALL
**Installation:** This skill is not present on disk. To add it, place a
\`SKILL.md\` file in \`skills/$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')/\`.

INSTALL
        elif [[ "$status" == "exists" ]]; then
            cat >> "$output_file" <<INSTALL
**Installation:** Skill directory exists but \`SKILL.md\` is missing. Ensure
the skill has a \`SKILL.md\` file at the root of its directory.

INSTALL
        fi

        echo "---" >> "$output_file"
        echo "" >> "$output_file"
    done

    # Append footer
    cat >> "$output_file" <<FOOTER
---
> Generated by \`scripts/publish-skills.sh\`. Re-run to regenerate.
FOOTER

    log_pass "Catalog generated: $output_file"
}

# --- Generate skills.json ---
generate_json() {
    local skills_json="$1"
    local output_file="$2"
    local skills_root="$3"
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local skill_count
    skill_count="$(echo "$skills_json" | jq length)"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would write skills.json to: $output_file"
        log_dry "  Skills: $skill_count"
        return 0
    fi

    mkdir -p "$(dirname "$output_file")"

    # Build enriched JSON with disk status
    local enriched
    enriched="$(
        echo "$skills_json" | jq -c '
            [.[] | {
                name: .name,
                purpose: .purpose,
                when_to_use: (.when_to_use // ""),
                skill_cmd: (.skill_cmd // ""),
                applies_to: (.applies_to // []),
                tools: (.tools // [])
            }]
        '
    )"

    local output_json
    output_json="$(
        jq -n \
            --arg ts "$timestamp" \
            --argjson skills "$enriched" \
            --arg count "$skill_count" \
            '{
                "$schema": "skills.schema.json",
                "generated_at": $ts,
                "total_skills": ($count | tonumber),
                "skills": $skills
            }'
    )"

    echo "$output_json" > "$output_file"
    log_pass "skills.json generated: $output_file ($skill_count skills)"
}

# --- Generate both ---
generate_full() {
    local skills_json="$1"
    local output_dir="$2"
    local skills_root="$3"

    generate_catalog "$skills_json" "$output_dir/CATALOG.md" "$skills_root"
    generate_json "$skills_json" "$output_dir/skills.json" "$skills_root"
}

# --- Print summary ---
print_summary() {
    local output_type="$1"
    local output_dir="$2"
    local skill_count="$3"

    echo ""
    echo "=== Publish Summary — Workflow State Engine Skills ==="
    echo "  Output type: $output_type"
    echo "  Output dir:  $output_dir/"
    echo "  Skills:      $skill_count"
    echo ""

    case "$output_type" in
        catalog) echo "  Files:       CATALOG.md" ;;
        json)    echo "  Files:       skills.json" ;;
        full)    echo "  Files:       CATALOG.md, skills.json" ;;
    esac
    echo ""

    if [[ "$EXIT_CODE" -eq 0 ]]; then
        echo -e "  ${GREEN}Publish: PASS${NC}"
    else
        echo -e "  ${YELLOW}Publish: PARTIAL (exit code 1)${NC}"
    fi
}

# --- Argument parsing ---
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                usage
                ;;
            --type)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --type requires an argument (catalog|json|full)" >&2
                    exit 2
                fi
                case "$2" in
                    catalog|json|full)
                        OUTPUT_TYPE="$2"
                        ;;
                    *)
                        echo "Error: --type must be catalog, json, or full (got: $2)" >&2
                        exit 2
                        ;;
                esac
                shift 2
                ;;
            --output)
                if [[ -z "${2:-}" ]]; then
                    echo "Error: --output requires a path argument" >&2
                    exit 2
                fi
                OUTPUT_DIR="$2"
                shift 2
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
                echo "Unknown option: $1" >&2
                echo "Use --help for usage information." >&2
                exit 2
                ;;
        esac
    done
}

# === MAIN ===
main() {
    parse_args "$@"

    echo "=== Publish Skills — Workflow State Engine ==="
    echo ""

    # Step 1: Check dependencies
    echo "Step 1: Check dependencies"
    check_deps
    echo ""

    # Step 2: Read contract
    echo "Step 2: Read superpowers-contract.json"
    local skills_json
    skills_json="$(read_skills "$CONTRACT_FILE")"
    local skill_count
    skill_count="$(echo "$skills_json" | jq length)"
    log_pass "Loaded $skill_count skills from contract"
    echo ""

    # Step 3: Discover installed skills
    echo "Step 3: Discover installed skills on disk"
    local -a installed_dirs
    IFS=' ' read -r -a installed_dirs <<< "$(discover_skill_dirs "$PROJECT_ROOT/skills")"
    log_pass "Found ${#installed_dirs[@]} skill directories on disk"
    if [[ "$VERBOSE" == true ]] && [[ "${#installed_dirs[@]}" -gt 0 ]]; then
        for d in "${installed_dirs[@]}"; do
            echo "    skills/$d/"
        done
    fi
    echo ""

    # Step 4: Generate output
    echo "Step 4: Generate output ($OUTPUT_TYPE)"
    case "$OUTPUT_TYPE" in
        catalog)
            generate_catalog "$skills_json" "$OUTPUT_DIR/CATALOG.md" "$OUTPUT_DIR"
            ;;
        json)
            generate_json "$skills_json" "$OUTPUT_DIR/skills.json" "$OUTPUT_DIR"
            ;;
        full)
            generate_full "$skills_json" "$OUTPUT_DIR" "$OUTPUT_DIR"
            ;;
    esac
    echo ""

    # Step 5: Summary
    print_summary "$OUTPUT_TYPE" "$OUTPUT_DIR" "$skill_count"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${CYAN}DRY-RUN — no files were modified.${NC}"
    fi

    if [[ "$EXIT_CODE" -ne 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
