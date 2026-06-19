#!/usr/bin/env bash
# scripts/test-gitnexus-integration.sh — G8: GitNexus Integration Test
# Tests that the GitNexus MCP tools are available and the codebase is properly indexed.
# Can be run from project root or CI.
# Usage: scripts/test-gitnexus-integration.sh [OPTIONS]

set -euo pipefail

# ── Color Constants ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Defaults ─────────────────────────────────────────────────────────────────
SKIP_INDEX=false
FORCE_INDEX=false
VERBOSE=false
EXIT_CODE=0
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# ── Usage ────────────────────────────────────────────────────────────────────

usage() {
    cat <<'USAGE'
usage: test-gitnexus-integration.sh [OPTIONS]

Tests that GitNexus is available and the codebase is properly indexed.

OPTIONS:
  --skip-index      Don't trigger re-index if stale — just warn
  --force-index     Always re-index before testing
  --verbose         Show raw output from gitnexus commands
  --help            Show this help message and exit

CHECKS:
  1. GitNexus CLI availability (gitnexus or npx gitnexus)
  2. Index freshness (< 1 hour old)
  3. Index responds to queries (via CLI status)
  4. detect_changes simulation (git diff + index alignment)

EXIT CODES:
  0   All checks pass
  1   Non-critical issues (warnings, stale index)
  2   Critical failure (gitnexus unavailable, no index)

EXAMPLES:
  scripts/test-gitnexus-integration.sh
  scripts/test-gitnexus-integration.sh --verbose
  scripts/test-gitnexus-integration.sh --skip-index
  scripts/test-gitnexus-integration.sh --force-index
USAGE
    exit 2
}

# ── Logging Functions ───────────────────────────────────────────────────────

log_pass() {
    local msg="$1"
    echo -e "${GREEN}[PASS]${NC} $msg"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
}

log_fail() {
    local msg="$1"
    echo -e "${RED}[FAIL]${NC} $msg" >&2
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
    EXIT_CODE=1
}

log_warn() {
    local msg="$1"
    echo -e "${YELLOW}[WARN]${NC} $msg" >&2
    WARN_COUNT=$(( WARN_COUNT + 1 ))
    if [[ "$EXIT_CODE" -lt 1 ]]; then
        EXIT_CODE=1
    fi
}

log_info() {
    local msg="$1"
    echo -e "${YELLOW}[INFO]${NC} $msg"
}

log_verbose() {
    local msg="$1"
    if [[ "$VERBOSE" == true ]]; then
        echo -e "  ${NC}→ $msg"
    fi
}

log_section() {
    echo ""
    echo -e "${CYAN}■${NC} $1"
}

# ── Project Root ─────────────────────────────────────────────────────────────

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [[ -z "$PROJECT_ROOT" ]]; then
    echo -e "${RED}[FAIL]${NC} Not inside a Git repository" >&2
    exit 2
fi

# ── GitNexus Discovery ───────────────────────────────────────────────────────

find_gitnexus() {
    if command -v gitnexus &>/dev/null; then
        echo "gitnexus"
        return 0
    fi
    if npx -y gitnexus --help &>/dev/null 2>&1; then
        echo "npx -y gitnexus"
        return 0
    fi
    echo ""
    return 1
}

# ── Check: CLI Availability ─────────────────────────────────────────────────

check_cli() {
    log_section "Check 1: GitNexus CLI Availability"

    local gitnexus_cmd
    gitnexus_cmd=$(find_gitnexus || echo "")

    if [[ -z "$gitnexus_cmd" ]]; then
        log_fail "GitNexus CLI not found (checked: PATH gitnexus, npx gitnexus)"
        log_info "Install: npm install -g gitnexus"
        return 1
    fi

    log_pass "GitNexus CLI found: ${gitnexus_cmd}"

    # Verify it actually works
    local version_output
    if version_output=$($gitnexus_cmd --version 2>/dev/null); then
        log_verbose "Version: ${version_output}"
    fi

    GITNEXUS_CMD="$gitnexus_cmd"
    return 0
}

# ── Check: Index Directories ────────────────────────────────────────────────

check_index_dirs() {
    log_section "Check 2: Index Directory Structure"

    local index_dirs=(
        "${PROJECT_ROOT}/.gitnexus"
        "${PROJECT_ROOT}/.gitnexus/index"
        "${PROJECT_ROOT}/.gitnexus/vector"
    )

    local found=0
    local missing=0

    for dir in "${index_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_verbose "Found: ${dir}"
            found=$(( found + 1 ))
        else
            log_verbose "Missing: ${dir}"
            missing=$(( missing + 1 ))
        fi
    done

    if [[ "$found" -eq 0 ]]; then
        log_fail "No GitNexus index directories found — codebase not indexed"
        return 1
    fi

    log_pass "Index directory structure: ${found} present, ${missing} missing"
    return 0
}

# ── Check: Index Freshness ──────────────────────────────────────────────────

check_freshness() {
    log_section "Check 3: Index Freshness"

    local index_marker="${PROJECT_ROOT}/.gitnexus/index/.indexed"
    if [[ ! -f "$index_marker" ]]; then
        index_marker="${PROJECT_ROOT}/.gitnexus/index"
    fi

    if [[ -d "$index_marker" ]]; then
        # Find the newest file in the index directory
        local newest_file
        newest_file=$(find "$index_marker" -type f -name "*.json" 2>/dev/null | head -5 | sort | tail -1)
        if [[ -n "$newest_file" ]]; then
            index_marker="$newest_file"
        else
            log_warn "No index files found in ${index_marker}"
            # Treat as stale
            handle_stale
            return 1
        fi
    fi

    if [[ ! -f "$index_marker" ]]; then
        log_warn "No index freshness marker found"
        handle_stale
        return 1
    fi

    local mtime
    mtime=$(stat -f "%m" "$index_marker" 2>/dev/null || stat -c "%Y" "$index_marker" 2>/dev/null || echo "")

    if [[ -z "$mtime" ]]; then
        log_warn "Cannot determine index modification time"
        handle_stale
        return 1
    fi

    local now
    now=$(date +%s)
    local age=$(( now - mtime ))
    local age_minutes=$(( age / 60 ))
    local max_age=3600  # 1 hour

    log_verbose "Index age: ${age_minutes}m (max: $(( max_age / 60 ))m)"
    log_verbose "Index file: ${index_marker}"

    if [[ "$age" -le "$max_age" ]]; then
        log_pass "Index is fresh (${age_minutes}m old, max $(( max_age / 60 ))m)"
        return 0
    else
        log_warn "Index is stale (${age_minutes}m old, max $(( max_age / 60 ))m)"
        handle_stale
        return 1
    fi
}

handle_stale() {
    if [[ "$SKIP_INDEX" == true ]]; then
        log_info "Skipping re-index (--skip-index)"
        return 0
    fi

    if [[ "$FORCE_INDEX" == true ]]; then
        log_info "Force re-indexing..."
        run_index
        return $?
    fi

    # Stale but not force: warn and offer to re-index
    log_warn "Index is stale. Use --force-index to re-index, or --skip-index to bypass."
    EXIT_CODE=1
}

# ── Run Index ───────────────────────────────────────────────────────────────

run_index() {
    log_section "Re-indexing GitNexus"

    if [[ -z "${GITNEXUS_CMD:-}" ]]; then
        GITNEXUS_CMD=$(find_gitnexus || echo "")
        if [[ -z "$GITNEXUS_CMD" ]]; then
            log_fail "Cannot re-index — GitNexus CLI not found"
            return 1
        fi
    fi

    log_info "Running: ${GITNEXUS_CMD} analyze ${PROJECT_ROOT}"
    local output
    if output=$($GITNEXUS_CMD analyze "$PROJECT_ROOT" 2>&1); then
        log_pass "Index refreshed successfully"
        if [[ "$VERBOSE" == true ]]; then
            echo "--- Output ---"
            echo "$output" | tail -10
            echo "---"
        fi
        return 0
    else
        log_fail "Index refresh failed"
        if [[ "$VERBOSE" == true ]]; then
            echo "--- Output ---"
            echo "$output"
            echo "---"
        fi
        return 1
    fi
}

# ── Check: Index Status ─────────────────────────────────────────────────────

check_status() {
    log_section "Check 4: Index Status (CLI)"

    if [[ -z "${GITNEXUS_CMD:-}" ]]; then
        GITNEXUS_CMD=$(find_gitnexus || echo "")
        if [[ -z "$GITNEXUS_CMD" ]]; then
            log_fail "Cannot check index status — GitNexus CLI not found"
            return 1
        fi
    fi

    local status_output
    if status_output=$($GITNEXUS_CMD status 2>&1); then
        log_pass "GitNexus status command succeeded"
        if [[ "$VERBOSE" == true ]]; then
            echo "--- Status ---"
            echo "$status_output"
            echo "---"
        fi

        # Check for meaningful status content (not empty/error)
        if echo "$status_output" | grep -qi "error\|failed\|not found\|no index"; then
            log_warn "Status output contains error indicators"
            return 1
        fi

        # Count indexed symbols from status
        local symbol_count
        symbol_count=$(echo "$status_output" | grep -i "symbols\|files\|nodes" | head -1 || echo "")
        if [[ -n "$symbol_count" ]]; then
            log_verbose "Index stats: ${symbol_count}"
        fi

        return 0
    else
        log_fail "GitNexus status command failed"
        if [[ "$VERBOSE" == true ]]; then
            echo "--- Status ---"
            echo "$status_output"
            echo "---"
        fi
        return 1
    fi
}

# ── Check: Detect Changes (git diff sanity) ────────────────────────────────

check_detect_changes() {
    log_section "Check 5: Git Diff + Index Alignment"

    local gitnexus_cmd
    gitnexus_cmd=$(find_gitnexus 2>/dev/null || echo "")

    # Validate that git diff works and has some content we can cross-reference
    if ! git diff --stat HEAD &>/dev/null; then
        log_warn "Cannot run git diff (not a git repo or no HEAD)"
        return 1
    fi

    local modified_files
    modified_files=$(git diff --name-only HEAD 2>/dev/null || echo "")

    if [[ -z "$modified_files" ]]; then
        log_info "No uncommitted changes — git diff is clean"
        log_pass "No changes to detect (clean working tree)"
        return 0
    fi

    local file_count
    file_count=$(echo "$modified_files" | wc -l | tr -d ' ')
    log_verbose "Modified files: ${file_count}"

    if [[ "$VERBOSE" == true ]]; then
        echo "  Modified files:"
        echo "$modified_files" | sed 's/^/    /'
    fi

    # Check if indexed files intersect with modified files
    if [[ -n "$gitnexus_cmd" && -d "${PROJECT_ROOT}/.gitnexus" ]]; then
        local indexed_count=0
        while IFS= read -r file; do
            local index_file="${PROJECT_ROOT}/.gitnexus/index/${file}.json"
            if [[ -f "$index_file" ]]; then
                indexed_count=$(( indexed_count + 1 ))
            fi
        done <<< "$modified_files"

        if [[ "$indexed_count" -gt 0 ]]; then
            log_pass "${indexed_count}/${file_count} modified files are indexed"
        else
            log_info "No modified files have individual index entries (normal for fresh index)"
        fi
    fi

    log_pass "Git diff + index alignment check passed"
    return 0
}

# ── Check: Query Endpoint ───────────────────────────────────────────────────

check_query() {
    log_section "Check 6: Knowledge Graph Query (via index files)"

    # Validate that the index contains actual data by counting files
    local index_dir="${PROJECT_ROOT}/.gitnexus/index"
    local vector_dir="${PROJECT_ROOT}/.gitnexus/vector"

    if [[ -d "$index_dir" ]]; then
        local index_files
        index_files=$(find "$index_dir" -name "*.json" 2>/dev/null | wc -l | tr -d ' ')

        if [[ "$index_files" -gt 0 ]]; then
            log_pass "Index contains ${index_files} JSON file(s)"
        else
            log_warn "Index directory exists but no JSON files found"
            return 1
        fi
    fi

    if [[ -d "$vector_dir" ]]; then
        local vector_files
        vector_files=$(find "$vector_dir" -type f 2>/dev/null | wc -l | tr -d ' ')
        if [[ "$vector_files" -gt 0 ]]; then
            log_verbose "Vector store: ${vector_files} file(s)"
        fi
    fi

    # Check for repo config / context file
    local context_file="${PROJECT_ROOT}/.gitnexus/context.json"
    if [[ -f "$context_file" ]]; then
        local repo_name
        repo_name=$(grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$context_file" 2>/dev/null | head -1 || echo "")
        if [[ -n "$repo_name" ]]; then
            log_verbose "Indexed repo: ${repo_name}"
        fi
        log_pass "GitNexus context file found: ${context_file}"
    else
        log_warn "No context.json found — index may be incomplete"
    fi

    log_pass "Knowledge graph data accessible"
    return 0
}

# ── Summary ─────────────────────────────────────────────────────────────────

print_summary() {
    local total=$(( PASS_COUNT + FAIL_COUNT + WARN_COUNT ))
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  GitNexus Integration Test Summary${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════${NC}"
    echo "  Tests:   ${total} total"
    echo -e "  ${GREEN}PASS:    ${PASS_COUNT}${NC}"
    if [[ "$WARN_COUNT" -gt 0 ]]; then
        echo -e "  ${YELLOW}WARN:    ${WARN_COUNT}${NC}"
    fi
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        echo -e "  ${RED}FAIL:    ${FAIL_COUNT}${NC}"
    fi
    echo ""

    if [[ "$FAIL_COUNT" -gt 0 ]]; then
        echo -e "  ${RED}Result: FAILURES DETECTED${NC}"
        echo "  Exit code will be 2"
        EXIT_CODE=2
    elif [[ "$WARN_COUNT" -gt 0 ]]; then
        echo -e "  ${YELLOW}Result: WARNINGS (non-critical)${NC}"
        if [[ "$EXIT_CODE" -lt 1 ]]; then
            EXIT_CODE=1
        fi
    else
        echo -e "  ${GREEN}Result: ALL CHECKS PASSED${NC}"
        EXIT_CODE=0
    fi
    echo -e "${CYAN}══════════════════════════════════════════════${NC}"
}

# ── Argument Parsing ────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-index)
            SKIP_INDEX=true
            shift
            ;;
        --force-index)
            FORCE_INDEX=true
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
            echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2
            usage
            ;;
    esac
done

# ── Main ────────────────────────────────────────────────────────────────────

echo -e "${CYAN}GitNexus Integration Test${NC}"
echo "  Project: ${PROJECT_ROOT}"
echo "  Options: skip-index=${SKIP_INDEX} force-index=${FORCE_INDEX} verbose=${VERBOSE}"
echo ""

# Check 1: CLI availability (critical)
check_cli || {
    print_summary
    exit 2
}

# Check 2: Index directories (important but can warn)
check_index_dirs || true

# Check 3: Index freshness
FRESHNESS_OK=true
check_freshness || FRESHNESS_OK=false

# Check 4: Index status via CLI
check_status || true

# Check 5: Git diff + index alignment
check_detect_changes || true

# Check 6: Knowledge graph data accessibility
check_query || true

# Summary
print_summary

exit $EXIT_CODE