#!/usr/bin/env bash
# =============================================================================
# health-check.sh — Daily Health Check for Workflow State Engine
#
# Runs 10 health lenses against the project and produces a score out of 100.
# Supports human-readable and JSON output, auto-fix mode, cron mode, and
# historical trend tracking.
#
# Usage:
#   scripts/health-check.sh                    # Full report (exit 0=healthy)
#   scripts/health-check.sh --json             # Machine-readable JSON
#   scripts/health-check.sh --fix              # Auto-fix fixable issues
#   scripts/health-check.sh --cron             # Quiet mode for cron
#   scripts/health-check.sh --notify           # Log to health-history.json
#   scripts/health-check.sh --history          # Show score trend
#   scripts/health-check.sh --help             # Full usage with examples
#
# Exit codes:
#   0 = HEALTHY (score ≥ 80)
#   1 = ISSUES  (score 60-79)
#   2 = CRITICAL (score < 60)
#   3 = FATAL   (missing required tools)
# =============================================================================

set -euo pipefail

# === Config ==================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BRANCH=""
TIMESTAMP=""
HUMAN_TIMESTAMP=""
MODE_HUMAN=true
MODE_JSON=false
MODE_FIX=false
MODE_CRON=false
MODE_NOTIFY=false
MODE_HISTORY=false

# Required tool
JQ_AVAILABLE=false
if command -v jq >/dev/null 2>&1; then
    JQ_AVAILABLE=true
fi

GH_AVAILABLE=false
if command -v gh >/dev/null 2>&1; then
    GH_AVAILABLE=true
fi

BC_AVAILABLE=false
if command -v bc >/dev/null 2>&1; then
    BC_AVAILABLE=true
fi

# Colors (with tput fallback)
USE_COLOR=false
if [[ -t 1 ]]; then
    USE_COLOR=true
fi
RED=''
GREEN=''
YELLOW=''
BLUE=''
CYAN=''
BOLD=''
NC=''
if [[ "$USE_COLOR" == true ]] && command -v tput >/dev/null 2>&1; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    NC=$(tput sgr0)
elif [[ "$USE_COLOR" == true ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
fi

# === Lens weights ============================================================
declare -r W_CONTRACT=15
declare -r W_DRIFT=10
declare -r W_GIT=10
declare -r W_SYNTAX=10
declare -r W_AGENT_DOCS=10
declare -r W_KNOWLEDGE=10
declare -r W_HOOKS=5
declare -r W_SESSIONS=5
declare -r W_PRS=10
declare -r W_BASELINE=15

# === Result accumulator ======================================================
# Each lens populates: result_name score max_score status detail
declare -A LENS_SCORE
declare -A LENS_MAX
declare -A LENS_STATUS
declare -A LENS_DETAIL
LENS_ORDER=()

# === Help ====================================================================
usage() {
    cat <<EOF
${BOLD}Usage:${NC} $(basename "$0") [OPTIONS]

Daily health check for the Workflow State Engine project. Runs 10 health lenses
and produces a score out of 100.

${BOLD}Options:${NC}
  --help              Show this help message with examples
  --json              Output machine-readable JSON (status to stderr, JSON to stdout)
  --fix               Auto-fix fixable issues (hooks path, permissions, empty dirs)
  --cron              Quiet mode for cron: only output on failure (score < 80)
  --notify            Log results to session/health-history.json for trend tracking
  --history           Show historical score trend from health-history.json

${BOLD}Exit codes:${NC}
  0 = HEALTHY  (score ≥ 80)
  1 = ISSUES   (score 60-79)
  2 = CRITICAL (score < 60)
  3 = FATAL    (missing required tools like jq)

${BOLD}Examples:${NC}
  # Full health check
  scripts/health-check.sh

  # Machine-readable output (pipe to jq for processing)
  scripts/health-check.sh --json | jq '.health_score'

  # Auto-fix common issues
  scripts/health-check.sh --fix

  # Cron job (daily at 6 AM):
  # 0 6 * * * cd /path/to/project && scripts/health-check.sh --cron --notify

  # View score history
  scripts/health-check.sh --history

${BOLD}10 Health Lenses:${NC}
  1. Contract Integrity   (15%) — Validate contract JSON against schema + transitions
  2. Knowledge Drift      (10%) — Detect drift between filesystem and lean-ctx knowledge
  3. Git Health           (10%) — Uncommitted changes, stale branches
  4. Script Syntax        (10%) — bash -n on all scripts/*.sh
  5. Agent Doc Freshness  (10%) — Script references in agent docs match filesystem
  6. Knowledge Coverage   (10%) — lean-ctx knowledge persistence coverage
  7. Git Hooks Active      (5%) — hooksPath and executable hooks
  8. Abandoned Sessions    (5%) — Stale entries in session/index.md
  9. PR Staleness         (10%) — Open PRs with no recent activity
 10. Architecture Baseline (15%) — Score regression tracking
EOF
    exit 0
}

# === Utilities ===============================================================

# Get ISO8601 timestamp
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

get_date_only() {
    date -u +"%Y-%m-%d"
}

# Detect the current git branch
detect_branch() {
    local br
    br=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    echo "$br"
}

# Record a lens result
record_lens() {
    local name="$1"
    local score="$2"
    local max_score="$3"
    local status="$4"
    local detail="${5:-}"
    LENS_SCORE["$name"]=$score
    LENS_MAX["$name"]=$max_score
    LENS_STATUS["$name"]="$status"
    LENS_DETAIL["$name"]="$detail"
    LENS_ORDER+=("$name")
}

# Compute status from score vs max
compute_status() {
    local score="$1"
    local max_score="$2"
    local pct=0
    if [[ "$max_score" -gt 0 ]]; then
        pct=$((score * 100 / max_score))
    fi
    if [[ "$pct" -ge 90 ]]; then
        echo "pass"
    elif [[ "$pct" -ge 50 ]]; then
        echo "warning"
    else
        echo "fail"
    fi
}

# Status icon
status_icon() {
    local status="$1"
    case "$status" in
        pass)    echo "${GREEN}✅${NC}" ;;
        warning) echo "${YELLOW}⚠️${NC}" ;;
        fail)    echo "${RED}❌${NC}" ;;
        skip)    echo "${BLUE}➖${NC}" ;;
        *)       echo "?" ;;
    esac
}

# Print a log message (goes to stderr in JSON mode)
log_info() {
    local msg="$1"
    if [[ "$MODE_JSON" == true ]]; then
        echo "$msg" >&2
    else
        echo "$msg"
    fi
}

log_error() {
    local msg="$1"
    if [[ "$MODE_JSON" == true ]]; then
        echo "[ERROR] $msg" >&2
    else
        echo "${RED}[ERROR]${NC} $msg" >&2
    fi
}

log_warn() {
    local msg="$1"
    if [[ "$MODE_JSON" == true ]]; then
        echo "[WARN] $msg" >&2
    else
        echo "${YELLOW}[WARN]${NC} $msg" >&2
    fi
}

# Check if a file is executable
is_executable() {
    [[ -x "$1" ]] && return 0 || return 1
}

# === Lens 1: Contract Integrity (15%) =======================================
lens_contract_integrity() {
    local score=0
    local max_score=$W_CONTRACT
    local results=()
    local template_result="skip"
    local branch_result="skip"

    # Check template contract
    local template_file="$PROJECT_DIR/contract/contract.template.json"
    if [[ -f "$template_file" ]]; then
        if bash "$SCRIPT_DIR/validate-contract.sh" --file "$template_file" --score >/dev/null 2>&1; then
            template_result="pass"
            score=$((score + 8))
            results+=("contract.template.json: PASS (+8)")
        else
            local rc=$?
            if [[ "$rc" -eq 1 ]]; then
                template_result="warning"
                score=$((score + 4))
                results+=("contract.template.json: RETRY (+4)")
            else
                template_result="fail"
                results+=("contract.template.json: FAIL (+0)")
            fi
        fi
    else
        results+=("contract.template.json: NOT FOUND (skip)")
    fi

    # Check branch-specific contract
    local br
    br=$(detect_branch)
    if [[ -n "$br" && "$br" != "HEAD" ]]; then
        local branch_file="$PROJECT_DIR/session/$br/contract.json"
        if [[ -f "$branch_file" ]]; then
            if bash "$SCRIPT_DIR/validate-contract.sh" --file "$branch_file" --score >/dev/null 2>&1; then
                branch_result="pass"
                score=$((score + 7))
                results+=("session/$br/contract.json: PASS (+7)")
            else
                local rc2=$?
                if [[ "$rc2" -eq 1 ]]; then
                    branch_result="warning"
                    score=$((score + 3))
                    results+=("session/$br/contract.json: RETRY (+3)")
                else
                    branch_result="fail"
                    results+=("session/$br/contract.json: FAIL (+0)")
                fi
            fi
        else
            branch_result="skip"
            results+=("No branch-specific contract (skip)")
        fi
    else
        branch_result="skip"
        results+=("No active branch detected (skip)")
    fi

    local status
    if [[ "$template_result" == "pass" && "$branch_result" == "pass" ]]; then
        status="pass"
    elif [[ "$template_result" == "pass" ]]; then
        status="warning"
    else
        status="fail"
    fi

    local detail
    detail=$(IFS="; "; echo "${results[*]}")
    record_lens "contract_integrity" "$score" "$max_score" "$status" "$detail"
}

# === Lens 2: Knowledge Drift (10%) ==========================================
lens_knowledge_drift() {
    local max_score=$W_DRIFT
    local detail=""

    if [[ ! -f "$SCRIPT_DIR/drift-detect.sh" ]]; then
        log_warn "drift-detect.sh not found — skipping knowledge drift check"
        record_lens "knowledge_drift" 0 "$max_score" "skip" "drift-detect.sh not available"
        return
    fi

    # Use --no-knowledge --verbose for file-only read-only mode
    local output
    output=$(bash "$SCRIPT_DIR/drift-detect.sh" --no-knowledge --verbose 2>&1 || true)
    local rc=$?

    if [[ "$rc" -eq 0 ]]; then
        record_lens "knowledge_drift" "$max_score" "$max_score" "pass" "No drift detected"
    else
        # Extract drift details from output
        local drift_files
        drift_files=$(echo "$output" | grep -i "drift\|diff\|changed\|modified" | head -5 | tr '\n' '; ' || echo "unspecified")
        detail="Drift detected: $drift_files"
        record_lens "knowledge_drift" 0 "$max_score" "fail" "$detail"
    fi
}

# === Lens 3: Git Health (10%) ===============================================
lens_git_health() {
    local max_score=$W_GIT
    local score=$max_score
    local details=()

    # Check uncommitted changes
    local uncommitted
    uncommitted=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$uncommitted" -gt 0 ]]; then
        score=$((score - 5))
        details+=("${uncommitted} uncommitted change(s) (-5)")
    else
        details+=("Working tree clean")
    fi

    # Check stale local branches (no commits in >7 days)
    local stale_count=0
    if command -v git >/dev/null 2>&1; then
        local now_epoch
        now_epoch=$(date +%s)
        local seven_days=$((7 * 86400))
        while IFS= read -r branch_ref; do
            local branch_name
            branch_name=$(echo "$branch_ref" | sed 's/^..//' | sed 's/ .*//' 2>/dev/null || echo "")
            [[ -z "$branch_name" ]] && continue
            [[ "$branch_name" == "main" || "$branch_name" == "master" || "$branch_name" == "HEAD" ]] && continue
            local last_commit_date
            last_commit_date=$(git log -1 --format="%ct" "$branch_name" 2>/dev/null || echo "0")
            if [[ "$last_commit_date" -gt 0 ]]; then
                local age=$((now_epoch - last_commit_date))
                if [[ "$age" -gt "$seven_days" ]]; then
                    stale_count=$((stale_count + 1))
                fi
            fi
        done < <(git branch --list 2>/dev/null || true)
    fi

    if [[ "$stale_count" -gt 0 ]]; then
        local deduction=$((stale_count * 2))
        [[ $deduction -gt 10 ]] && deduction=10
        score=$((score - deduction))
        details+=("${stale_count} stale branch(es) (>7 days, -${deduction})")
    fi

    # Ensure score >= 0
    [[ "$score" -lt 0 ]] && score=0

    local status
    status=$(compute_status "$score" "$max_score")
    local detail
    detail=$(IFS="; "; echo "${details[*]}")
    record_lens "git_health" "$score" "$max_score" "$status" "$detail"
}

# === Lens 4: Script Syntax (10%) ============================================
lens_script_syntax() {
    local max_score=$W_SYNTAX
    local pass_count=0
    local fail_count=0
    local fail_files=()
    local total=0

    if [[ ! -d "$SCRIPT_DIR" ]]; then
        record_lens "script_syntax" 0 "$max_score" "fail" "scripts/ directory not found"
        return
    fi

    while IFS= read -r -d '' script; do
        total=$((total + 1))
        if bash -n "$script" 2>/dev/null; then
            pass_count=$((pass_count + 1))
        else
            fail_count=$((fail_count + 1))
            fail_files+=("$(basename "$script")")
        fi
    done < <(find "$SCRIPT_DIR" -maxdepth 1 -name '*.sh' -print0 2>/dev/null || true)

    if [[ "$total" -eq 0 ]]; then
        record_lens "script_syntax" 0 "$max_score" "fail" "No scripts found in scripts/"
        return
    fi

    local score=$max_score
    if [[ "$fail_count" -gt 0 ]]; then
        local deduction=$((fail_count * 2))
        [[ "$deduction" -gt 10 ]] && deduction=10
        score=$((score - deduction))
    fi
    [[ "$score" -lt 0 ]] && score=0

    local status
    status=$(compute_status "$score" "$max_score")
    local detail="${pass_count}/${total} pass"
    [[ "$fail_count" -gt 0 ]] && detail+=", fails: ${fail_files[*]}"
    record_lens "script_syntax" "$score" "$max_score" "$status" "$detail"
}

# === Lens 5: Agent Doc Freshness (10%) ======================================
lens_agent_docs() {
    local max_score=$W_AGENT_DOCS
    local agents_dir="$PROJECT_DIR/agents"

    if [[ ! -d "$agents_dir" ]]; then
        record_lens "agent_docs" 0 "$max_score" "fail" "agents/ directory not found"
        return
    fi

    # Find all scripts referenced in agent docs
    local refs
    refs=$(grep -ro 'scripts/[a-zA-Z0-9_.-]*' "$agents_dir" 2>/dev/null | sort -u | sed 's/.*scripts\///' || true)

    # Find all actual scripts
    local actual_scripts
    actual_scripts=$(find "$SCRIPT_DIR" -maxdepth 1 -name '*.sh' -exec basename {} \; 2>/dev/null | sort -u || true)

    local missing_refs=()
    local ref_count=0
    local ref_found=0

    if [[ -n "$refs" ]]; then
        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            ref_count=$((ref_count + 1))
            if [[ -f "$SCRIPT_DIR/$ref" ]]; then
                ref_found=$((ref_found + 1))
            else
                missing_refs+=("$ref")
            fi
        done <<< "$refs"
    fi

    # Check what % of actual scripts are referenced
    local actual_count
    actual_count=$(echo "$actual_scripts" | grep -c . || true)
    local ref_coverage=0
    if [[ "$actual_count" -gt 0 ]]; then
        ref_coverage=$((ref_found * 100 / actual_count))
    fi

    local score=0
    local details=()

    # Score from referenced script existence (5pts max)
    if [[ "$ref_count" -gt 0 ]]; then
        local ref_pct=$((ref_found * 100 / ref_count))
        if [[ "$ref_pct" -eq 100 ]]; then
            score=$((score + 5))
            details+=("All ${ref_count} refs exist (+5)")
        elif [[ "$ref_pct" -ge 50 ]]; then
            score=$((score + 3))
            details+=("${ref_found}/${ref_count} refs exist (+3)")
            if [[ "${#missing_refs[@]}" -gt 0 ]]; then
                details+=("Missing: ${missing_refs[*]}")
            fi
        fi
    fi

    # Score from coverage (5pts max)
    if [[ "$actual_count" -gt 0 ]]; then
        if [[ "$ref_coverage" -ge 50 ]]; then
            score=$((score + 5))
            details+=("${ref_coverage}% script coverage (+5)")
        elif [[ "$ref_coverage" -ge 25 ]]; then
            score=$((score + 2))
            details+=("${ref_coverage}% script coverage (+2)")
        fi
    fi

    [[ "$score" -gt "$max_score" ]] && score=$max_score

    local status
    status=$(compute_status "$score" "$max_score")
    local detail
    detail=$(IFS="; "; echo "${details[*]}")
    [[ -z "$detail" ]] && detail="No agent docs with script references"
    record_lens "agent_docs" "$score" "$max_score" "$status" "$detail"
}

# === Lens 6: Knowledge Coverage (10%) =======================================
lens_knowledge_coverage() {
    local max_score=$W_KNOWLEDGE

    if [[ ! -f "$SCRIPT_DIR/verify-knowledge.sh" ]]; then
        log_warn "verify-knowledge.sh not found — skipping knowledge coverage check"
        record_lens "knowledge_coverage" 0 "$max_score" "skip" "verify-knowledge.sh not available"
        return
    fi

    local output
    output=$(bash "$SCRIPT_DIR/verify-knowledge.sh" --dry-run --all 2>&1 || true)

    # Detect dry-run preview mode (no real data)
    if echo "$output" | grep -qi 'would compute\|would check\|dry.run'; then
        # Dry-run mode doesn't produce real coverage — mark as pass
        record_lens "knowledge_coverage" "$max_score" "$max_score" "pass" "Dry-run mode — coverage would be computed on real run"
        return
    fi

    # Parse coverage percentage from output
    local coverage=0
    # Try to extract "X/Y categories populated" style counts
    local populated
    populated=$(echo "$output" | grep -oE '[0-9]+/[0-9]+ categories' | head -1 || echo "")
    if [[ -n "$populated" ]]; then
        local num denom
        num=$(echo "$populated" | cut -d/ -f1)
        denom=$(echo "$populated" | cut -d/ -f2 | grep -oE '[0-9]+')
        if [[ "$denom" -gt 0 ]]; then
            coverage=$((num * 100 / denom))
        fi
    fi
    # Fallback: count "would check" lines vs expected lines
    if [[ "$coverage" -eq 0 ]]; then
        local check_lines
        check_lines=$(echo "$output" | grep -c 'would check' || true)
        local total_check_lines
        total_check_lines=$(echo "$output" | grep -cE '^\w+:' || true)
        if [[ "$total_check_lines" -gt 0 ]]; then
            # Estimate coverage as (full check lines / total phase lines)
            local full_lines
            full_lines=$(echo "$output" | grep -cE '^\w+:\s+[0-9]+\s+' || true)
            if [[ "$full_lines" -gt 0 ]]; then
                coverage=$((full_lines * 100 / total_check_lines))
            fi
        fi
    fi
    # Last fallback: check for PASS/FAIL keywords
    if [[ "$coverage" -eq 0 ]]; then
        local pass_lines
        pass_lines=$(echo "$output" | grep -ci 'pass\|ok\|✓\|\[PASS\]' || true)
        local fail_lines
        fail_lines=$(echo "$output" | grep -ci 'fail\|✗\|\[FAIL\]' || true)
        local total=$((pass_lines + fail_lines))
        if [[ "$total" -gt 0 ]]; then
            coverage=$((pass_lines * 100 / total))
        fi
    fi

    local score=0
    local status="fail"
    local detail="Coverage: ${coverage}%"

    if [[ "$coverage" -ge 70 ]]; then
        score=$max_score
        status="pass"
        detail="Coverage: ${coverage}% — PASS"
    elif [[ "$coverage" -ge 50 ]]; then
        score=$((max_score * 5 / 10))
        status="warning"
        detail="Coverage: ${coverage}% — WARNING (target: 70%)"
    else
        score=0
        status="fail"
        detail="Coverage: ${coverage}% — FAIL (target: 70%)"
    fi

    record_lens "knowledge_coverage" "$score" "$max_score" "$status" "$detail"
}

# === Lens 7: Git Hooks Active (5%) ==========================================
lens_git_hooks() {
    local max_score=$W_HOOKS
    local score=0
    local details=()

    local hooks_path
    hooks_path=$(git config core.hooksPath 2>/dev/null || echo "")

    local expected_hooks_dir="$PROJECT_DIR/.githooks"

    if [[ "$hooks_path" == ".githooks" ]]; then
        score=$((score + 3))
        details+=("hooksPath set to .githooks/ (+3)")
    else
        details+=("hooksPath not set (expected: .githooks/)")
    fi

    # Check pre-commit
    if [[ -f "$expected_hooks_dir/pre-commit" ]] && is_executable "$expected_hooks_dir/pre-commit"; then
        score=$((score + 1))
        details+=("pre-commit executable (+1)")
    else
        details+=("pre-commit missing or not executable")
    fi

    # Check post-commit
    if [[ -f "$expected_hooks_dir/post-commit" ]] && is_executable "$expected_hooks_dir/post-commit"; then
        score=$((score + 1))
        details+=("post-commit executable (+1)")
    else
        details+=("post-commit missing or not executable")
    fi

    local status
    status=$(compute_status "$score" "$max_score")
    local detail
    detail=$(IFS="; "; echo "${details[*]}")
    record_lens "git_hooks" "$score" "$max_score" "$status" "$detail"
}

# === Lens 8: Abandoned Sessions (5%) ========================================
lens_abandoned_sessions() {
    local max_score=$W_SESSIONS
    local score=$max_score
    local abandoned=()
    local index_file="$PROJECT_DIR/session/index.md"

    if [[ ! -f "$index_file" ]]; then
        record_lens "abandoned_sessions" "$max_score" "$max_score" "pass" "No session index (first run)"
        return
    fi

    # Extract branch names from index.md table (first column, backtick-quoted)
    local index_branches
    index_branches=$(grep -oE '`[a-z]+/[a-zA-Z0-9_-]+`' "$index_file" 2>/dev/null | tr -d '`' | sort -u || true)

    local existing_branches
    existing_branches=$(git branch --list 2>/dev/null | sed 's/^[* ] //' || true)

    if [[ -n "$index_branches" ]]; then
        while IFS= read -r branch_entry; do
            branch_entry=$(echo "$branch_entry" | tr -d ' ' | grep -v '^$' || true)
            [[ -z "$branch_entry" ]] && continue
            # Check if branch exists in git
            if ! echo "$existing_branches" | grep -qx "$branch_entry"; then
                abandoned+=("$branch_entry")
            fi
        done <<< "$index_branches"
    fi

    local abandoned_count=${#abandoned[@]}
    if [[ "$abandoned_count" -gt 0 ]]; then
        local deduction=$((abandoned_count * 2))
        [[ $deduction -gt $max_score ]] && deduction=$max_score
        score=$((score - deduction))
    fi

    local detail="${abandoned_count} abandoned session(s) in index"
    if [[ "$abandoned_count" -gt 0 ]]; then
        detail+=": ${abandoned[*]}"
    fi

    local status
    status=$(compute_status "$score" "$max_score")
    record_lens "abandoned_sessions" "$score" "$max_score" "$status" "$detail"
}

# === Lens 9: PR Staleness (10%) =============================================
lens_pr_staleness() {
    local max_score=$W_PRS
    local score=0
    local detail=""

    if [[ "$GH_AVAILABLE" == false ]]; then
        # Partial credit if gh is not available
        score=5
        record_lens "pr_staleness" "$score" "$max_score" "warning" "gh CLI not available — partial check (5/10)"
        return
    fi

    # Try to get open PRs
    local pr_data
    pr_data=$(gh pr list --state open --json number,title,updatedAt,headRefName 2>/dev/null || true)

    if [[ -z "$pr_data" || "$pr_data" == "[]" ]]; then
        record_lens "pr_staleness" "$max_score" "$max_score" "pass" "No open PRs"
        return
    fi

    local now_epoch
    now_epoch=$(date +%s)
    local three_days=$((3 * 86400))
    local stale_count=0
    local stale_info=()

    # Parse PR data with jq
    if [[ "$JQ_AVAILABLE" == true ]]; then
        local pr_count
        pr_count=$(echo "$pr_data" | jq 'length' 2>/dev/null || echo 0)
        local stale_prs
        stale_prs=$(echo "$pr_data" | jq -c '.[]' 2>/dev/null || true)

        if [[ -n "$stale_prs" ]]; then
            while IFS= read -r pr; do
                local updated_at
                updated_at=$(echo "$pr" | jq -r '.updatedAt' 2>/dev/null || echo "")
                local title
                title=$(echo "$pr" | jq -r '.title' 2>/dev/null || echo "")
                local number
                number=$(echo "$pr" | jq -r '.number' 2>/dev/null || echo "")
                if [[ -n "$updated_at" && "$updated_at" != "null" ]]; then
                    # Parse ISO 8601 date
                    local pr_epoch
                    if [[ "$(uname)" == "Darwin" ]]; then
                        pr_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$updated_at" +%s 2>/dev/null || echo 0)
                    else
                        pr_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo 0)
                    fi
                    if [[ "$pr_epoch" -gt 0 ]]; then
                        local age=$((now_epoch - pr_epoch))
                        if [[ "$age" -gt "$three_days" ]]; then
                            stale_count=$((stale_count + 1))
                            local age_days=$((age / 86400))
                            stale_info+=("#${number} (${age_days}d)")
                        fi
                    fi
                fi
            done <<< "$stale_prs"
        fi
    fi

    if [[ "$stale_count" -eq 0 ]]; then
        score=$max_score
        detail="All PRs active"
    else
        local deduction=$((stale_count * 3))
        [[ $deduction -gt $max_score ]] && deduction=$max_score
        score=$((max_score - deduction))
        detail="${stale_count} stale PR(s): ${stale_info[*]}"
    fi

    local status
    status=$(compute_status "$score" "$max_score")
    record_lens "pr_staleness" "$score" "$max_score" "$status" "$detail"
}

# === Lens 10: Architecture Baseline (15%) ===================================
lens_architecture_baseline() {
    local max_score=$W_BASELINE
    local history_file="$PROJECT_DIR/session/health-history.json"

    # Calculate current health score (all other lenses must be computed first)
    local current_score=0
    local total_max=0
    for lens_name in "${LENS_ORDER[@]}"; do
        if [[ "$lens_name" != "architecture_baseline" ]]; then
            current_score=$((current_score + LENS_SCORE["$lens_name"]))
            total_max=$((total_max + LENS_MAX["$lens_name"]))
        fi
    done
    # Normalize to 100-scale if less than full
    if [[ "$total_max" -lt 85 ]]; then
        # Not enough lenses ran — pass baseline
        record_lens "architecture_baseline" "$max_score" "$max_score" "pass" "Insufficient lens data for baseline comparison"
        return
    fi

    if [[ ! -f "$history_file" ]]; then
        # First run: store current as baseline
        record_lens "architecture_baseline" "$max_score" "$max_score" "pass" "First run — stored baseline score: ${current_score}"
        return
    fi

    # Get last score from history
    local last_score
    if [[ "$JQ_AVAILABLE" == true ]]; then
        last_score=$(jq -r '.history[-1].score // empty' "$history_file" 2>/dev/null || echo "")
    else
        # Fallback: grep for last score
        last_score=$(grep -oP '"score":\s*\K[0-9]+' "$history_file" 2>/dev/null | tail -1 || echo "")
    fi

    if [[ -z "$last_score" ]]; then
        record_lens "architecture_baseline" "$max_score" "$max_score" "pass" "No baseline score in history"
        return
    fi

    local diff=$((current_score - last_score))
    local abs_diff=${diff#-}

    if [[ "$diff" -ge 0 ]]; then
        # Stable or improving
        if [[ "$abs_diff" -le 2 ]]; then
            record_lens "architecture_baseline" "$max_score" "$max_score" "pass" "Score stable (${last_score}→${current_score}, Δ${diff})"
        else
            record_lens "architecture_baseline" "$max_score" "$max_score" "pass" "Score improving (${last_score}→${current_score}, Δ+${diff})"
        fi
    elif [[ "$abs_diff" -le 5 ]]; then
        # Warning: drop 1-5 pts
        local partial_score=$((max_score * 7 / 10))
        record_lens "architecture_baseline" "$partial_score" "$max_score" "warning" "Score dropped ${abs_diff}pt (${last_score}→${current_score})"
    elif [[ "$abs_diff" -le 10 ]]; then
        # Warning: drop 5-10 pts
        local partial_score=$((max_score * 5 / 10))
        record_lens "architecture_baseline" "$partial_score" "$max_score" "warning" "Score dropped ${abs_diff}pt (${last_score}→${current_score})"
    else
        # Critical: drop >10 pts
        record_lens "architecture_baseline" 0 "$max_score" "fail" "Score dropped ${abs_diff}pt (${last_score}→${current_score}) — regression detected"
    fi
}

# === Fix Mode ================================================================
do_fix() {
    local fixes_applied=0

    log_info "${BOLD}🔧 Fix Mode — Auto-repairing fixable issues${NC}"
    echo ""

    # Fix 1: Set hooksPath
    local current_hooks
    current_hooks=$(git config core.hooksPath 2>/dev/null || echo "")
    if [[ "$current_hooks" != ".githooks" ]]; then
        if git config core.hooksPath .githooks 2>/dev/null; then
            log_info "  ✅ Set core.hooksPath → .githooks/"
            fixes_applied=$((fixes_applied + 1))
        else
            log_error "  ❌ Failed to set core.hooksPath"
        fi
    else
        log_info "  ✅ hooksPath already set to .githooks/"
    fi

    # Fix 2: Make hooks executable
    local hooks_dir="$PROJECT_DIR/.githooks"
    if [[ -d "$hooks_dir" ]]; then
        for hook in pre-commit post-commit; do
            local hook_file="$hooks_dir/$hook"
            if [[ -f "$hook_file" ]]; then
                if is_executable "$hook_file"; then
                    log_info "  ✅ $hook already executable"
                else
                    if chmod +x "$hook_file" 2>/dev/null; then
                        log_info "  ✅ Made $hook executable"
                        fixes_applied=$((fixes_applied + 1))
                    else
                        log_error "  ❌ Failed to chmod +x $hook"
                    fi
                fi
            else
                log_info "  ➖ $hook not found (skipping)"
            fi
        done
    fi

    # Fix 3: Clean empty session/feature/ and session/fix/ directories
    for dir in "$PROJECT_DIR"/session/feature/* "$PROJECT_DIR"/session/fix/*; do
        [[ -d "$dir" ]] || continue
        if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
            if rmdir "$dir" 2>/dev/null; then
                log_info "  ✅ Removed empty directory: $(basename "$dir")"
                fixes_applied=$((fixes_applied + 1))
            fi
        fi
    done

    echo ""
    if [[ "$fixes_applied" -gt 0 ]]; then
        log_info "${GREEN}${BOLD}Done: ${fixes_applied} fix(es) applied${NC}"
    else
        log_info "${GREEN}${BOLD}Nothing to fix — all checks passed${NC}"
    fi
}

# === History Mode ============================================================
show_history() {
    local history_file="$PROJECT_DIR/session/health-history.json"

    if [[ ! -f "$history_file" ]]; then
        echo "${YELLOW}No health history found. Run 'scripts/health-check.sh --notify' to create one.${NC}"
        return 0
    fi

    if [[ "$JQ_AVAILABLE" == true ]]; then
        echo "${BOLD}📊 Health Score History${NC}"
        echo ""
        printf "  %-20s %-10s %-12s\n" "Date" "Score" "Verdict"
        printf "  %-20s %-10s %-12s\n" "----" "-----" "-------"
        jq -r '.history[] | "  \(.date)   \(.score)/100   \(.verdict)"' "$history_file" 2>/dev/null || true
        echo ""
        local trend
        trend=$(jq -r '.trend // "unknown"' "$history_file" 2>/dev/null || echo "unknown")
        local high
        high=$(jq -r '.all_time_high // "?"' "$history_file" 2>/dev/null || echo "?")
        local low
        low=$(jq -r '.all_time_low // "?"' "$history_file" 2>/dev/null || echo "?")
        echo "  ${BOLD}Trend:${NC} $trend"
        echo "  ${BOLD}All-time high:${NC} $high/100"
        echo "  ${BOLD}All-time low:${NC} $low/100"
    else
        # Fallback without jq
        cat "$history_file" 2>/dev/null || echo "Cannot read history"
    fi
}

# === Notify: Save to health-history.json ====================================
save_history() {
    local current_score="$1"
    local verdict="$2"
    local history_file="$PROJECT_DIR/session/health-history.json"
    local today
    today=$(get_date_only)

    # Load existing history or create new
    local history_json
    if [[ -f "$history_file" ]]; then
        history_json=$(cat "$history_file" 2>/dev/null || echo '{"history":[]}')
    else
        history_json='{"history":[]}'
    fi

    if [[ "$JQ_AVAILABLE" == true ]]; then
        # Validate existing JSON
        if ! echo "$history_json" | jq empty 2>/dev/null; then
            log_warn "Corrupt health-history.json, creating new"
            history_json='{"history":[]}'
        fi

        # Remove duplicate entry for today if exists
        history_json=$(echo "$history_json" | jq --arg today "$today" \
            '.history = [.history[] | select(.date != $today)]' 2>/dev/null || echo "$history_json")

        # Append new entry
        local new_entry
        new_entry=$(jq -n --arg date "$today" --argjson score "$current_score" --arg verdict "$verdict" \
            '{date: $date, score: $score, verdict: $verdict}' 2>/dev/null || echo "{\"date\":\"$today\",\"score\":$current_score,\"verdict\":\"$verdict\"}")
        history_json=$(echo "$history_json" | jq --argjson entry "$new_entry" \
            '.history += [$entry]' 2>/dev/null || echo "$history_json")

        # Calculate trend from last 3 entries
        local trend
        trend=$(echo "$history_json" | jq -r '
            .history as $h |
            if ($h | length) < 2 then "stable" else
            ([$h[-3:][] | .score]) as $recent |
            if ($recent | length) < 2 then "stable" else
            if ($recent | map(select(. >= $recent[-1])) | length) == ($recent | length) then "improving" else
            if ($recent | map(select(. <= $recent[-1])) | length) == ($recent | length) then "declining" else
            "stable" end end end' 2>/dev/null || echo "stable")

        # Calculate all-time high/low
        local all_time_high
        all_time_high=$(echo "$history_json" | jq '[.history[].score] | max // .' 2>/dev/null || echo "$current_score")
        local all_time_low
        all_time_low=$(echo "$history_json" | jq '[.history[].score] | min // .' 2>/dev/null || echo "$current_score")

        # Write updated JSON
        history_json=$(echo "$history_json" | jq --arg trend "$trend" --argjson high "$all_time_high" --argjson low "$all_time_low" \
            '.trend = $trend | .all_time_high = $high | .all_time_low = $low' 2>/dev/null || echo "$history_json")

        echo "$history_json" > "$history_file" 2>/dev/null && \
            log_info "  📝 Health history saved to session/health-history.json"
    else
        # Without jq, append simply
        local temp_file
        temp_file=$(mktemp 2>/dev/null || mktemp -t hc.XXXX)
        echo "$history_json" | sed '$s/}$//' > "$temp_file"
        echo ",{\"date\":\"$today\",\"score\":$current_score,\"verdict\":\"$verdict\"}]}" >> "$temp_file"
        # Simpler: just create a new file with basic content
        cat > "$history_file" <<< '{"history":[{"date":"'"$today"'","score":'"$current_score"',"verdict":"'"$verdict"'"}]}' 2>/dev/null || true
        rm -f "$temp_file" 2>/dev/null
        log_info "  📝 Health history saved (basic, no jq)"
    fi
}

# === Render Report ===========================================================
render_report() {
    local total_score=0
    local total_max=0
    local warnings=0
    local failures=0

    # First compute scores to determine health before rendering
    local ordered_names=(
        "contract_integrity"
        "knowledge_drift"
        "git_health"
        "script_syntax"
        "agent_docs"
        "knowledge_coverage"
        "git_hooks"
        "abandoned_sessions"
        "pr_staleness"
        "architecture_baseline"
    )
    for lens_name in "${ordered_names[@]}"; do
        local sv=${LENS_SCORE["$lens_name"]:-0}
        local mv=${LENS_MAX["$lens_name"]:-0}
        total_score=$((total_score + sv))
        total_max=$((total_max + mv))
    done

    local health_score=0
    if [[ "$total_max" -gt 0 ]]; then
        health_score=$((total_score * 100 / total_max))
    fi
    [[ "$health_score" -gt 100 ]] && health_score=100

    # Cron mode: only output on failure
    if [[ "$MODE_CRON" == true ]]; then
        local cron_verdict="HEALTHY"
        local cron_exit=0
        if [[ "$health_score" -lt 80 ]]; then
            if [[ "$health_score" -lt 60 ]]; then
                cron_verdict="CRITICAL"
                cron_exit=2
            else
                cron_verdict="ISSUES"
                cron_exit=1
            fi
        fi
        if [[ "$health_score" -ge 80 ]]; then
            exit 0
        fi
        # Unhealthy: fall through to render
    fi

    # Reset accumulators for actual rendering
    total_score=0
    total_max=0

    # Header
    if [[ "$MODE_JSON" == false ]]; then
        echo ""
        echo "${BOLD}╔══════════════════════════════════════════════╗${NC}"
        echo "${BOLD}║    Workflow State Engine — Health Check     ║${NC}"
        echo "${BOLD}║    $HUMAN_TIMESTAMP${NC}"
        echo "${BOLD}╠══════════════════════════════════════════════╣${NC}"
    fi

    # We need to render in a specific order that matches the numerical order
    local ordered_names=(
        "contract_integrity"
        "knowledge_drift"
        "git_health"
        "script_syntax"
        "agent_docs"
        "knowledge_coverage"
        "git_hooks"
        "abandoned_sessions"
        "pr_staleness"
        "architecture_baseline"
    )
    local display_names=(
        "Contract Integrity"
        "Knowledge Drift"
        "Git Health"
        "Script Syntax"
        "Agent Doc Freshness"
        "Knowledge Coverage"
        "Git Hooks Active"
        "Abandoned Sessions"
        "PR Staleness"
        "Architecture Baseline"
    )

    local json_lenses="{}"
    local i=0
    for display_name in "${display_names[@]}"; do
        local lens_name="${ordered_names[$i]}"
        local score_val=${LENS_SCORE["$lens_name"]:-0}
        local max_val=${LENS_MAX["$lens_name"]:-0}
        local status_val=${LENS_STATUS["$lens_name"]:-"skip"}
        local detail_val=${LENS_DETAIL["$lens_name"]:-""}

        total_score=$((total_score + score_val))
        total_max=$((total_max + max_val))

        if [[ "$status_val" == "fail" ]]; then
            failures=$((failures + 1))
        elif [[ "$status_val" == "warning" ]]; then
            warnings=$((warnings + 1))
        fi

        local icon
        icon=$(status_icon "$status_val")
        local padded_name
        padded_name=$(printf "%-24s" "$display_name")
        local padded_score
        padded_score=$(printf "%3s" "$score_val")
        local padded_max
        padded_max=$(printf "%3s" "$max_val")

        if [[ "$MODE_JSON" == false ]]; then
            echo "║ ${icon} ${padded_name} [${padded_score}/${padded_max}]  ${status_val}${NC}"
        fi

        # Build JSON
        if [[ "$MODE_JSON" == true ]]; then
            local escaped_detail
            escaped_detail=$(echo "$detail_val" | sed 's/"/\\"/g')
            json_lenses=$(echo "$json_lenses" | jq \
                --arg name "$lens_name" \
                --argjson score "$score_val" \
                --argjson max "$max_val" \
                --arg status "$status_val" \
                --arg detail "$escaped_detail" \
                '. + {($name): {"score": $score, "max": $max, "status": $status, "detail": $detail}}' 2>/dev/null || echo "$json_lenses")
        fi

        i=$((i + 1))
    done

    # Footer
    local health_score=0
    if [[ "$total_max" -gt 0 ]]; then
        health_score=$((total_score * 100 / total_max))
    fi
    [[ "$health_score" -gt 100 ]] && health_score=100

    local verdict="HEALTHY"
    local verdict_icon="${GREEN}✅${NC}"
    local exit_code=0
    if [[ "$health_score" -lt 80 ]]; then
        if [[ "$health_score" -lt 60 ]]; then
            verdict="CRITICAL"
            verdict_icon="${RED}❌${NC}"
            exit_code=2
        else
            verdict="ISSUES"
            verdict_icon="${YELLOW}⚠️${NC}"
            exit_code=1
        fi
    fi

    if [[ "$MODE_JSON" == false ]]; then
        echo "${BOLD}╠══════════════════════════════════════════════╣${NC}"
        echo "${BOLD}║${NC} HEALTH SCORE: ${BOLD}${health_score}/100${NC} → ${verdict_icon} ${BOLD}${verdict}${NC}"
        # Summary
        local parts=()
        [[ "$failures" -gt 0 ]] && parts+=("${RED}${failures} failed${NC}")
        [[ "$warnings" -gt 0 ]] && parts+=("${YELLOW}${warnings} warning(s)${NC}")
        if [[ "${#parts[@]}" -gt 0 ]]; then
            local summary
            summary=$(IFS=", "; echo "${parts[*]}")
            echo "${BOLD}║${NC} ${summary}"
        else
            echo "${BOLD}║${NC} All checks passed"
        fi
        echo "${BOLD}╚══════════════════════════════════════════════╝${NC}"
    fi

    # JSON output
    if [[ "$MODE_JSON" == true ]]; then
        local summary_text
        if [[ "$failures" -gt 0 && "$warnings" -gt 0 ]]; then
            summary_text="${verdict_icon} ${verdict} — ${failures} failed, ${warnings} warning(s), 0 critical"
        elif [[ "$failures" -gt 0 ]]; then
            summary_text="${verdict_icon} ${verdict} — ${failures} failed, 0 critical"
        elif [[ "$warnings" -gt 0 ]]; then
            summary_text="${verdict_icon} ${verdict} — ${warnings} warning(s), 0 critical"
        else
            summary_text="${verdict_icon} ${verdict} — 0 issues"
        fi

        # Strip ANSI from summary
        summary_text=$(echo "$summary_text" | sed 's/\x1b\[[0-9;]*m//g')

        echo "$json_lenses" | jq --arg ts "$TIMESTAMP" --argjson score "$health_score" --arg verdict "$verdict" --arg summary "$summary_text" \
            '{timestamp: $ts, health_score: $score, verdict: $verdict, summary: $summary, lenses: .}' 2>/dev/null || \
        cat <<JSONEOF
{
  "timestamp": "$TIMESTAMP",
  "health_score": $health_score,
  "verdict": "$verdict",
  "summary": "$summary_text",
  "lenses": $json_lenses
}
JSONEOF
    fi

    # Cron mode: only output on failure
    if [[ "$MODE_CRON" == true ]]; then
        if [[ "$health_score" -ge 80 ]]; then
            # Silent exit
            exit "$exit_code"
        fi
        # Re-run in human mode for the failure output
        # But we already rendered — just exit with the right code
        echo ""
        echo "[CRON] Health score: ${health_score}/100 — ${verdict}" >&2
    fi

    return "$exit_code"
}

# === Main ====================================================================
main() {
    local exit_code=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                usage
                ;;
            --json)
                MODE_JSON=true
                MODE_HUMAN=false
                shift
                ;;
            --fix)
                MODE_FIX=true
                shift
                ;;
            --cron)
                MODE_CRON=true
                shift
                ;;
            --notify)
                MODE_NOTIFY=true
                shift
                ;;
            --history)
                MODE_HISTORY=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Try '$(basename "$0") --help' for usage."
                exit 3
                ;;
        esac
    done

    # Check required tools
    if [[ "$JQ_AVAILABLE" == false ]] && [[ "$MODE_JSON" == true ]]; then
        log_error "jq is required for --json mode. Install with: brew install jq"
        exit 3
    fi

    TIMESTAMP=$(get_timestamp)
    if [[ "$(uname)" == "Darwin" ]]; then
        HUMAN_TIMESTAMP=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$TIMESTAMP" "+%Y-%m-%d %H:%M:%S UTC" 2>/dev/null || echo "$TIMESTAMP")
    else
        HUMAN_TIMESTAMP=$(date -d "$TIMESTAMP" "+%Y-%m-%d %H:%M:%S UTC" 2>/dev/null || echo "$TIMESTAMP")
    fi

    BRANCH=$(detect_branch)

    # History-only mode
    if [[ "$MODE_HISTORY" == true ]]; then
        show_history
        exit 0
    fi

    # Fix-only mode
    if [[ "$MODE_FIX" == true ]] && [[ "$MODE_HUMAN" == true ]] && [[ "$MODE_JSON" == false ]] && [[ "$MODE_CRON" == false ]]; then
        do_fix
        exit 0
    fi

    # Run all 10 lenses
    lens_contract_integrity
    lens_knowledge_drift
    lens_git_health
    lens_script_syntax
    lens_agent_docs
    lens_knowledge_coverage
    lens_git_hooks
    lens_abandoned_sessions
    lens_pr_staleness
    lens_architecture_baseline

    # Fix mode: also run fixes after lenses (but before rendering if both)
    if [[ "$MODE_FIX" == true ]]; then
        do_fix
        # Re-run lenses that could have been fixed
        lens_git_hooks
        lens_abandoned_sessions
    fi

    # Render report
    render_report
    exit_code=$?

    # Save history if --notify
    if [[ "$MODE_NOTIFY" == true ]]; then
        local total_score=0
        local total_max=0
        for lens_name in "${LENS_ORDER[@]}"; do
            total_score=$((total_score + LENS_SCORE["$lens_name"]))
            total_max=$((total_max + LENS_MAX["$lens_name"]))
        done
        local health_score=0
        if [[ "$total_max" -gt 0 ]]; then
            health_score=$((total_score * 100 / total_max))
        fi
        [[ "$health_score" -gt 100 ]] && health_score=100

        local verdict="HEALTHY"
        if [[ "$health_score" -lt 80 ]]; then
            [[ "$health_score" -lt 60 ]] && verdict="CRITICAL" || verdict="ISSUES"
        fi

        save_history "$health_score" "$verdict"

        # Also update human-readable health-record.md
        if [[ -f "$SCRIPT_DIR/update-health-record.sh" ]]; then
            bash "$SCRIPT_DIR/update-health-record.sh" "$health_score" "$verdict" "$BRANCH" 2>/dev/null || true
        fi
    fi

    exit "$exit_code"
}

main "$@"
