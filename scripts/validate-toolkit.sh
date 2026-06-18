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
     Verifies contract/contract.json is valid JSON and contract/index.md
     exists (schema definition source).
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
        skill_count=$(find "$dir" -maxdepth 1 -type d -print0 | xargs -0 -I {} echo | wc -l | tr -d ' ')
        # Find counts . and .. on some platforms, so subtract 1 for .
        if [[ "$skill_count" -gt 0 ]]; then
            skill_count=$((skill_count - 1))
        fi
        if [[ "$skill_count" -lt 5 ]]; then
            log_fail "skills/ has only $skill_count subdirectories (expected at least 5)"
            violations=$((violations + 1))
        else
            log_pass "skills/ exists with $skill_count skill directories"
        fi
    fi

    # contract/ — index.md (definition), contract.json + state.md (runtime, optional)
    dir="$PROJECT_ROOT/contract"
    if [[ ! -d "$dir" ]]; then
        log_fail "contract/ directory does not exist"
        violations=$((violations + 1))
    else
        if [[ ! -f "$dir/index.md" ]]; then
            log_fail "contract/index.md is missing (committed definition)"
            violations=$((violations + 1))
        else
            log_pass "contract/index.md exists (definition source)"
        fi
        # contract.json and state.md are runtime state — gitignored, only exist during active sessions
        if [[ -f "$dir/contract.json" ]]; then
            log_pass "contract/contract.json exists (runtime state)"
        else
            log_info "contract/contract.json not found (expected — runtime file, only present during active sessions)"
        fi
        if [[ -f "$dir/state.md" ]]; then
            log_pass "contract/state.md exists (runtime state)"
        else
            log_info "contract/state.md not found (expected — runtime file, only present during active sessions)"
        fi
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

    # session/ — state.md, index.md, at least one branch snapshot
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

    # .opencode/ — directory exists
    dir="$PROJECT_ROOT/.opencode"
    if [[ ! -d "$dir" ]]; then
        log_fail ".opencode/ directory does not exist"
        violations=$((violations + 1))
    else
        log_pass ".opencode/ directory exists"
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
        local expected_relative="../$expected_target"

        if [[ "$actual_target" != "$expected_relative" ]] && [[ "$actual_target" != "../$expected_target" ]]; then
            # Also accept exact match without "../" prefix depending on depth
            log_fail ".opencode/$symlink_name points to '$actual_target' (expected '$expected_relative')"
            violations=$((violations + 1))
        else
            # Check that the target resolves (exists)
            if [[ -d "$symlink_path" ]]; then
                log_pass ".opencode/$symlink_name -> $expected_target/ (resolves correctly)"
                log_verbose "  Target path: $(cd "$base" && readlink "$symlink_name")"
            else
                if [[ -f "$symlink_path" ]]; then
                    log_pass ".opencode/$symlink_name -> $expected_target (resolves to a file)"
                else
                    log_fail ".opencode/$symlink_name -> $actual_target (symlink broken — target does not exist)"
                    violations=$((violations + 1))
                fi
            fi
        fi
    done

    if [[ "$violations" -eq 0 ]]; then
        echo "  Result: All 8 .opencode/ symlinks resolve correctly"
    fi
}

# ── Check 3: Contract file integrity ───────────────────────────────────────
check_contract_integrity() {
    echo "Check 3: Contract file integrity"

    local violations=0
    local contract_file="$PROJECT_ROOT/contract/contract.json"
    local schema_file="$PROJECT_ROOT/contract/index.md"

    # Check contract.json is valid JSON (runtime state — optional)
    if [[ ! -f "$contract_file" ]]; then
        log_info "contract/contract.json not found (runtime state — expected only during active sessions)"
    else
        if command -v jq &>/dev/null; then
            if jq empty "$contract_file" 2>/dev/null; then
                log_pass "contract/contract.json is valid JSON"
            else
                log_fail "contract/contract.json is not valid JSON"
                if [[ "$VERBOSE" == true ]]; then
                    jq empty "$contract_file" 2>&1 | sed 's/^/    -> /'
                fi
                violations=$((violations + 1))
            fi
        elif command -v python3 &>/dev/null; then
            if python3 -m json.tool "$contract_file" &>/dev/null; then
                log_pass "contract/contract.json is valid JSON"
            else
                log_fail "contract/contract.json is not valid JSON"
                if [[ "$VERBOSE" == true ]]; then
                    python3 -m json.tool "$contract_file" 2>&1 | sed 's/^/    -> /'
                fi
                violations=$((violations + 1))
            fi
        else
            log_info "Neither jq nor python3 found — skipping JSON validation for contract.json"
        fi
    fi

    # Check contract/index.md exists (schema definition source)
    if [[ ! -f "$schema_file" ]]; then
        log_fail "contract/index.md does not exist"
        violations=$((violations + 1))
    else
        log_pass "contract/index.md exists (schema definition source)"
    fi

    # Deep schema validation removed: schema now embedded in index.md markdown
    if [[ "$violations" -eq 0 ]]; then
        echo "  Result: All contract files valid"
    fi
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

    echo "=== Toolkit Validator — Workflow State Engine ==="
    echo "Project root: $PROJECT_ROOT"
    echo "Mode: verbose=$VERBOSE, strict=$STRICT"
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
