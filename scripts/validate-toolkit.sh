#!/usr/bin/env bash
# shellcheck disable=SC2086
# validate-toolkit.sh — Validate project toolkit structure is intact
#   ./scripts/validate-toolkit.sh          # Run all checks
#   ./scripts/validate-toolkit.sh --help   # Show usage
#   ./scripts/validate-toolkit.sh --verbose  # Detailed output
#   ./scripts/validate-toolkit.sh --strict   # Fail on first violation
# Exit codes:
#   0 — All checks pass
#   1 — One or more violations found
# Requirements:
#   - bash 4+
#   - jq (for JSON schema validation)
# This script is idempotent — safe to run multiple times.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERBOSE=false
STRICT=false
EXIT_CODE=0
VIOLATIONS=0
CHECK_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Consumer mode — validates from a consumer's perspective
CONSUMER_MODE=false
# Auto-detect: if parent dir has .opencode/ symlinks pointing back to us
if [ -L "../.opencode/agents" ] 2>/dev/null; then
    target="$(readlink "../.opencode/agents" 2>/dev/null)"
    if echo "$target" | grep -qE "^\\.\\./$(basename "$PROJECT_ROOT")/agents"; then
        CONSUMER_MODE=true
    fi
fi
CONSUMER_ROOT="$PROJECT_ROOT"

# Color output (disable if not a terminal)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

usage() {
    cat <<'EOF'
validate-toolkit.sh — Validate project toolkit structure

Usage:
    ./scripts/validate-toolkit.sh [OPTIONS]

Options:
    --help       Show this usage message
    --verbose    Print detailed output for each check
    --strict     Exit immediately on first violation
    --consumer   Validate from consumer's perspective (checks consumer root)

Checks performed:
  1. Required directories exist
     Verifies agents/, skills/, contract/, config/, scripts/, doc/,
     rules/, usage/, .opencode/ all have expected contents.
  2. Symlinks in .opencode/ resolve correctly
     Verifies .opencode/agents -> agents/, .opencode/skills -> skills/,
     .opencode/rules -> rules/, .opencode/orchestration -> contract/,
     .opencode/usage -> usage/,
     .opencode/config -> config/.
  3. Contract file integrity
 Verifies contract/contract.schema.json is valid JSON schema and all
 committed definition files exist.
  4. Agent file consistency
     Verifies each .md file in agents/ has a proper heading.
  5. Cross-references
     Verifies internal links in agent.md and paths in _governance.md
     resolve to actual files.

Exit codes:
  0 — All checks pass
  1 — One or more violations found
EOF
    exit 0
}

log_pass() {
    local msg="$1"
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "${GREEN}[PASS]${NC} $msg"
}

log_fail() {
    local msg="$1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    VIOLATIONS=$((VIOLATIONS + 1))
    EXIT_CODE=1
    echo -e "${RED}[FAIL]${NC} $msg"
    if [[ "$STRICT" == true ]]; then
        echo "[STRICT] Aborting on first violation."
        exit 1
    fi
}

log_info() {
    local msg="$1"
    CHECK_COUNT=$((CHECK_COUNT + 1))
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${YELLOW}[INFO]${NC} $msg"
    fi
}

log_verbose() {
    local msg="$1"
    if [[ "$VERBOSE" == true ]]; then
        echo "  [..] $msg"
    fi
}

# ── Check 1: Required directories exist ────────────────────────────────────
check_required_dirs() {
    echo "Check 1: Required directories exist"

    local violations=0
    local dir

    # opencode.json — must exist with no remaining placeholders
    local opencode_root="$PROJECT_ROOT"
    if [ "$CONSUMER_MODE" = true ]; then
        opencode_root="$CONSUMER_ROOT"
    fi
    if [[ -f "$opencode_root/opencode.json" ]]; then
        local placeholder_count
        placeholder_count=$(grep -c 'YOUR_' "$opencode_root/opencode.json" 2>/dev/null || true)
        if [[ "$placeholder_count" -gt 0 ]]; then
            if grep -q 'YOUR_FIRECRAWL_API_KEY' "$opencode_root/opencode.json" 2>/dev/null; then
                log_info "opencode.json has YOUR_FIRECRAWL_API_KEY placeholder (update with real key)"
            fi
            log_fail "opencode.json has $placeholder_count placeholder(s) (YOUR_*) — replace with actual values"
            violations=$((violations + 1))
        else
            log_pass "opencode.json exists with no remaining placeholders"
        fi
    else
        if [ "$CONSUMER_MODE" = true ]; then
            log_fail "opencode.json does not exist at consumer root ($opencode_root)"
        else
            log_fail "opencode.json does not exist at project root"
        fi
        violations=$((violations + 1))
    fi

    # agents/ — at least 10 .md files
    dir="$PROJECT_ROOT/agents"
    if [[ ! -d "$dir" ]]; then
        log_fail "agents/ directory does not exist"
        violations=$((violations + 1))
    else
        local agent_count
        agent_count=$(find "$dir" -maxdepth 1 -name '*.md' -print0 | xargs -0 -I {} echo | wc -l | tr -d ' ')
        if [[ "$agent_count" -lt 10 ]]; then
            log_fail "agents/ has only $agent_count .md files (expected at least 10)"
            violations=$((violations + 1))
        else
            log_pass "agents/ exists with $agent_count .md files"
        fi
    fi

    # skills/ — at least 5 subdirectories
    dir="$PROJECT_ROOT/skills"
    if [[ ! -d "$dir" ]]; then
        log_fail "skills/ directory does not exist"
        violations=$((violations + 1))
    else
        local skill_count
        skill_count=$(find "$dir" -maxdepth 1 -type d -not -name '.' -not -name '..' | wc -l | tr -d ' ')
        if [[ "$skill_count" -lt 5 ]]; then
            log_fail "skills/ has only $skill_count subdirectories (expected at least 5)"
            violations=$((violations + 1))
        else
            log_pass "skills/ exists with $skill_count skill directories"
        fi
    fi

    # contract/ — committed definition files (all version-controlled)
    dir="$PROJECT_ROOT/contract"
    if [[ ! -d "$dir" ]]; then
        log_fail "contract/ directory does not exist"
        violations=$((violations + 1))
    else
        local def_files=("README.md" "contract.schema.json" "superpowers-contract.json" "state.md")
        for f in "${def_files[@]}"; do
            if [[ ! -f "$dir/$f" ]]; then
                log_fail "contract/$f is missing"
                violations=$((violations + 1))
            else
                log_pass "contract/$f exists"
            fi
        done
    fi
    # config/ — at least 2 .json files
    dir="$PROJECT_ROOT/config"
    if [[ ! -d "$dir" ]]; then
        log_fail "config/ directory does not exist"
        violations=$((violations + 1))
    else
        local json_count
        json_count=$(find "$dir" -maxdepth 1 -name '*.json' -print0 | xargs -0 -I {} echo | wc -l | tr -d ' ')
        if [[ "$json_count" -lt 2 ]]; then
            log_fail "config/ has only $json_count .json files (expected at least 2)"
            violations=$((violations + 1))
        else
            log_pass "config/ exists with $json_count .json files"
        fi
    fi

    # scripts/ — check-conventions.sh, scan-ponytail-debt.sh, archive-sessions.sh
    dir="$PROJECT_ROOT/scripts"
    if [[ ! -d "$dir" ]]; then
        log_fail "scripts/ directory does not exist"
        violations=$((violations + 1))
    else
        local s_violations=0
        for f in check-conventions.sh scan-ponytail-debt.sh archive-sessions.sh; do
            if [[ ! -f "$dir/$f" ]]; then
                log_fail "scripts/$f is missing"
                s_violations=$((s_violations + 1))
                violations=$((violations + 1))
            fi
        done
        if [[ "$s_violations" -eq 0 ]]; then
            log_pass "scripts/ has all required scripts"
        fi
    fi

    # session/ — skipped in consumer mode (session/ lives at consumer root)
    if [ "$CONSUMER_MODE" = true ]; then
        log_info "session/ — skipped in consumer mode (session/ lives at consumer root)"
    else
        dir="$PROJECT_ROOT/session"
        if [[ ! -d "$dir" ]]; then
            log_fail "session/ directory does not exist"
            violations=$((violations + 1))
        else
            local ssn_violations=0
            for f in state.md index.md; do
                if [[ ! -f "$dir/$f" ]]; then
                    log_fail "session/$f is missing"
                    ssn_violations=$((ssn_violations + 1))
                    violations=$((violations + 1))
                fi
            done
            # Check at least one branch snapshot dir
            local snapshot_count
            snapshot_count=$(find "$dir" -maxdepth 2 -type f -name 'contract.json' -print0 2>/dev/null | xargs -0 -I {} echo | wc -l | tr -d ' ')
            if [[ "$snapshot_count" -eq 0 ]]; then
                log_fail "session/ has no branch snapshot directories (no contract.json found at depth 2)"
                violations=$((violations + 1))
            fi
            if [[ "$ssn_violations" -eq 0 && "$snapshot_count" -ge 1 ]]; then
                log_pass "session/ exists with $snapshot_count branch snapshot(s) and required files"
            fi
        fi
    fi

    # doc/ — workflow.md
    dir="$PROJECT_ROOT/doc"
    if [[ ! -d "$dir" ]]; then
        log_fail "doc/ directory does not exist"
        violations=$((violations + 1))
    else
        if [[ ! -f "$dir/workflow.md" ]]; then
            log_fail "doc/workflow.md is missing"
            violations=$((violations + 1))
        else
            log_pass "doc/ exists with workflow.md"
        fi
    fi

    # rules/ — rules.json
    dir="$PROJECT_ROOT/rules"
    if [[ ! -d "$dir" ]]; then
        log_fail "rules/ directory does not exist"
        violations=$((violations + 1))
    else
        if [[ ! -f "$dir/rules.json" ]]; then
            log_fail "rules/rules.json is missing"
            violations=$((violations + 1))
        else
            log_pass "rules/ exists with rules.json"
        fi
    fi

    # usage/ — at least 5 .md files
    dir="$PROJECT_ROOT/usage"
    if [[ ! -d "$dir" ]]; then
        log_fail "usage/ directory does not exist"
        violations=$((violations + 1))
    else
        local usage_count
        usage_count=$(find "$dir" -maxdepth 1 -name '*.md' -print0 | xargs -0 -I {} echo | wc -l | tr -d ' ')
        if [[ "$usage_count" -lt 5 ]]; then
            log_fail "usage/ has only $usage_count .md files (expected at least 5)"
            violations=$((violations + 1))
        else
            log_pass "usage/ exists with $usage_count .md files"
        fi
    fi

    # .opencode/ — directory exists (at CONSUMER_ROOT in consumer mode)
    local opencode_dir="$PROJECT_ROOT/.opencode"
    if [ "$CONSUMER_MODE" = true ]; then
        opencode_dir="$CONSUMER_ROOT/.opencode"
    fi
    if [[ ! -d "$opencode_dir" ]]; then
        log_fail "$(basename "$opencode_dir")/ directory does not exist"
        violations=$((violations + 1))
    else
        log_pass "$(basename "$opencode_dir")/ directory exists"
    fi

    if [[ "$violations" -eq 0 ]]; then
        echo "  Result: All required directories present"
    fi
}

# ── Check 2: Symlinks in .opencode/ resolve correctly ──────────────────────
check_opencode_symlinks() {
    echo "Check 2: Symlinks in .opencode/ resolve correctly"

    local violations=0
    local base="$PROJECT_ROOT/.opencode"
    local submodule_rel=""
    if [ "$CONSUMER_MODE" = true ]; then
        base="$CONSUMER_ROOT/.opencode"
        submodule_rel="$(basename "$PROJECT_ROOT")"
    fi

    if [[ ! -d "$base" ]]; then
        log_info ".opencode/ directory missing — skipping symlink checks"
        return
    fi

    # Map of symlink name -> expected target (relative from .opencode/)
    declare -A symlink_targets=(
        ["agents"]="agents"
        ["skills"]="skills"
        ["rules"]="rules"
        ["orchestration"]="contract"
        ["usage"]="usage"
        ["config"]="config"
        ["plugins"]="plugins"
    )

    for symlink_name in "${!symlink_targets[@]}"; do
        local symlink_path="$base/$symlink_name"
        local expected_target="${symlink_targets[$symlink_name]}"

        if [[ ! -L "$symlink_path" ]]; then
            if [[ -e "$symlink_path" ]]; then
                log_fail ".opencode/$symlink_name exists but is NOT a symlink"
                violations=$((violations + 1))
            else
                log_fail ".opencode/$symlink_name does not exist (expected symlink -> $expected_target/)"
                violations=$((violations + 1))
            fi
            continue
        fi

        # Get the symlink target
        local actual_target
        actual_target=$(readlink "$symlink_path" 2>/dev/null)

        # Compare expected vs actual — differs between engine and consumer mode
        local target_mismatch=false
        if [ "$CONSUMER_MODE" = true ]; then
            # Consumer: symlinks point to ../.workflow-engine/agents (or .workflow-engine/agents)
            if [[ "$actual_target" != "../$submodule_rel/$expected_target" ]] && [[ "$actual_target" != "$submodule_rel/$expected_target" ]]; then
                target_mismatch=true
            fi
        else
            # Engine: symlinks point to ../agents (or agents)
            if [[ "$actual_target" != "../$expected_target" ]] && [[ "$actual_target" != "$expected_target" ]]; then
                target_mismatch=true
            fi
        fi

        if [ "$target_mismatch" = true ]; then
            log_fail ".opencode/$symlink_name points to '$actual_target' (expected '$expected_target')"
            violations=$((violations + 1))
        fi

        # Check that the target resolves (exists)
        if [[ -d "$symlink_path" ]]; then
            log_pass ".opencode/$symlink_name -> $expected_target/ (resolves correctly)"
            log_verbose "  Target path: $(cd "$(dirname "$symlink_path")" && readlink "$(basename "$symlink_path")")"
        elif [[ -f "$symlink_path" ]]; then
            log_pass ".opencode/$symlink_name -> $expected_target (resolves to a file)"
        else
            log_fail ".opencode/$symlink_name -> $actual_target (symlink broken — target does not exist)"
            violations=$((violations + 1))
        fi
    done

    if [[ "$violations" -eq 0 ]]; then
        echo "  Result: All 7 .opencode/ symlinks resolve correctly"
    fi
}

# ── Check 3: Contract file integrity ───────────────────────────────────────
check_contract_integrity() {
    echo "Check 3: Contract file integrity"
    local violations=0
    local schema_file="$PROJECT_ROOT/contract/contract.schema.json"
    
    # Check contract.schema.json is valid JSON
    if [[ ! -f "$schema_file" ]]; then
        log_fail "contract/contract.schema.json does not exist"
        violations=$((violations + 1))
    else
        if command -v jq &>/dev/null; then
            if jq empty "$schema_file" 2>/dev/null; then
                log_pass "contract/contract.schema.json is valid JSON"
            else
                log_fail "contract/contract.schema.json is not valid JSON"
                violations=$((violations + 1))
            fi
        elif command -v python3 &>/dev/null; then
            if python3 -m json.tool "$schema_file" &>/dev/null; then
                log_pass "contract/contract.schema.json is valid JSON"
            else
                log_fail "contract/contract.schema.json is not valid JSON"
                violations=$((violations + 1))
            fi
        else
            log_info "Neither jq nor python3 found — skipping JSON validation"
        fi
    fi
    
    if [[ "$violations" -eq 0 ]]; then
        echo "  Result: Contract schema valid"
    fi
    return "$violations"
}

# ── Check 4: Agent file consistency ────────────────────────────────────────
check_agent_consistency() {
    echo "Check 4: Agent file consistency"

    local violations=0
    local agent_dir="$PROJECT_ROOT/agents"

    if [[ ! -d "$agent_dir" ]]; then
        log_info "No agents/ directory found — skipping agent file checks"
        return
    fi

    # Check each .md file has at least one "# " heading
    # (files may have YAML front matter starting with "---")
    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$agent_dir" -maxdepth 1 -name '*.md' -print0)

    local no_heading=0
    for f in "${files[@]}"; do
        local basename_f
        basename_f=$(basename "$f")
        # Search for a "# " or "## " heading anywhere in the file
        if ! grep -qm1 '^#\{1,6\} ' "$f" 2>/dev/null; then
            log_fail "$basename_f has no '#' heading"
            no_heading=$((no_heading + 1))
            violations=$((violations + 1))
        fi
    done

    # Check opencode.json references agents if it exists
    local opencode_json="$PROJECT_ROOT/.opencode/opencode.json"
    if [[ -f "$opencode_json" ]]; then
        log_verbose "Checking agent references in opencode.json..."
        # Count agent files referenced in opencode.json
        local referenced=0
        local not_referenced=0
        for f in "${files[@]}"; do
            local basename_f
            basename_f=$(basename "$f")
            # Check if the filename appears in opencode.json
            if grep -qF "$basename_f" "$opencode_json" 2>/dev/null; then
                referenced=$((referenced + 1))
            else
                # Skip _governance.md — it's an include, not a standalone agent
                if [[ "$basename_f" != "_governance.md" ]]; then
                    if [[ "$VERBOSE" == true ]]; then
                        log_verbose "  $basename_f not referenced in opencode.json"
                    fi
                    not_referenced=$((not_referenced + 1))
                fi
            fi
        done

        if [[ "$not_referenced" -gt 0 ]]; then
            log_info "$not_referenced agent(s) not explicitly referenced in opencode.json (agents loaded via .opencode/agents/ symlink)"
        fi
        log_verbose "$referenced agent(s) found in opencode.json references"
        log_pass "opencode.json exists and references can resolve"
    else
        log_info "No opencode.json found — skipping agent reference check"
    fi

    if [[ "$no_heading" -eq 0 ]]; then
        log_pass "All agent files have proper headings"
    fi
}

# ── Check 5: Cross-references ──────────────────────────────────────────────
check_cross_references() {
    echo "Check 5: Cross-references"

    local violations=0

    # 5a: Internal links in agent.md
    local agent_md="$PROJECT_ROOT/agent.md"
    if [[ -f "$agent_md" ]]; then
        log_verbose "Checking internal links in agent.md..."

        # Extract relative markdown links: [text](./path) or [text](.opencode/path)
        # Exclude anchor-only links (#section)
        local broken_links=0
        while IFS= read -r link; do
            [[ -z "$link" ]] && continue
            # Skip anchor-only links
            if echo "$link" | grep -qE '^#'; then
                continue
            fi
            # Skip external URLs
            if echo "$link" | grep -qE '^https?://'; then
                continue
            fi

            local resolved="$PROJECT_ROOT/$link"
            # Handle relative links (./ prefix)
            if echo "$link" | grep -qE '^\./'; then
                resolved="$PROJECT_ROOT/${link#./}"
            fi

            if [[ ! -f "$resolved" ]] && [[ ! -d "$resolved" ]]; then
                broken_links=$((broken_links + 1))
                log_fail "agent.md: link '$link' does not resolve (looked for '$resolved')"
                violations=$((violations + 1))
            else
                log_verbose "  agent.md: '$link' -> OK"
            fi
        done < <(grep -oP '\]\(([^)]+)\)' "$agent_md" 2>/dev/null | sed 's/^](//;s/)$//' || true)

        if [[ "$broken_links" -eq 0 ]]; then
            log_pass "All internal links in agent.md resolve correctly"
        fi
    else
        log_info "No agent.md found — skipping cross-reference check"
    fi

    # 5b: File paths in _governance.md
    local gov_md="$PROJECT_ROOT/agents/_governance.md"
    if [[ -f "$gov_md" ]]; then
        log_verbose "Checking file paths in _governance.md..."

        # Extract inline code file paths (backtick-wrapped paths with . or /)
        local broken_paths=0
        while IFS= read -r path; do
            [[ -z "$path" ]] && continue
            # Skip non-path references (commands, etc.)
            if ! echo "$path" | grep -qE '[/.]'; then
                continue
            fi
            # Skip if it's a lean-ctx command or git command
            if echo "$path" | grep -qE '^(lean-ctx |git )'; then
                continue
            fi

            local resolved="$PROJECT_ROOT/$path"
            # Handle .opencode/ paths — they're relative to project root
            if [[ -f "$resolved" ]] || [[ -d "$resolved" ]]; then
                log_verbose "  _governance.md: '$path' -> OK"
            else
                # Try without .opencode/ prefix (some paths use contract/ instead)
                local alt_resolved="$PROJECT_ROOT/${path#.opencode/orchestration/}"
                if [[ "$path" == ".opencode/orchestration/"* ]]; then
                    # Map .opencode/orchestration/ -> contract/
                    alt_resolved="$PROJECT_ROOT/contract/${path#.opencode/orchestration/}"
                    if [[ -f "$alt_resolved" ]] || [[ -d "$alt_resolved" ]]; then
                        log_verbose "  _governance.md: '$path' -> OK (via contract/)"
                        continue
                    fi
                fi
                broken_paths=$((broken_paths + 1))
                log_fail "_governance.md: path '$path' does not resolve"
                violations=$((violations + 1))
            fi
        done < <(grep -oP '`[^`]+`' "$gov_md" 2>/dev/null | sed 's/^`//;s/`$//' || true)

        if [[ "$broken_paths" -eq 0 ]]; then
            log_pass "All file paths in _governance.md resolve correctly"
        fi
    else
        log_info "No _governance.md found — skipping path check"
    fi

    if [[ "$violations" -eq 0 ]]; then
        echo "  Result: All cross-references resolve"
    fi
}

# ── Summary ─────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo "=== Summary ==="
    echo "Passed: ${PASS_COUNT}, Failed: ${FAIL_COUNT}, Skipped: ${CHECK_COUNT}"
    if [[ "$VIOLATIONS" -eq 0 ]]; then
        echo -e "${GREEN}All checks passed.${NC}"
    else
        echo -e "${RED}${VIOLATIONS} violation(s) found.${NC}"
    fi
}

# ── Argument parsing ────────────────────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                usage
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --strict)
                STRICT=true
                shift
                ;;
            --consumer)
                CONSUMER_MODE=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage info."
                exit 1
                ;;
        esac
    done
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    # Set CONSUMER_ROOT if consumer mode was enabled (via flag or auto-detect)
    if [ "$CONSUMER_MODE" = true ]; then
        CONSUMER_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"
    fi

    echo "=== Toolkit Validator — Workflow State Engine ==="
    echo "Project root: $PROJECT_ROOT"
    if [ "$CONSUMER_MODE" = true ]; then
        echo "Consumer root: $CONSUMER_ROOT"
    fi
    echo "Mode: verbose=$VERBOSE, strict=$STRICT, consumer=$CONSUMER_MODE"
    echo ""

    check_required_dirs
    echo ""
    check_opencode_symlinks
    echo ""
    check_contract_integrity
    echo ""
    check_agent_consistency
    echo ""
    check_cross_references

    print_summary
    exit $EXIT_CODE
}

main "$@"
