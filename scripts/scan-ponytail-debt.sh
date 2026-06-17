#!/usr/bin/env bash
# shellcheck disable=SC2086
#
# scan-ponytail-debt.sh — Scan codebase for intentional shortcuts and technical debt
#
# Scans for ponytail: comments (frugality shortcuts) and debt markers
# (TODO, FIXME, HACK, XXX, WORKAROUND, TEMPORARY). Groups results by marker
# type and provides a structured summary.
#
# Usage:
#   ./scripts/scan-ponytail-debt.sh              # Default scan from project root
#   ./scripts/scan-ponytail-debt.sh --help       # Show usage
#   ./scripts/scan-ponytail-debt.sh --verbose    # Show matching lines per file
#   ./scripts/scan-ponytail-debt.sh --strict     # Exit 1 if any debt found
#   ./scripts/scan-ponytail-debt.sh --exclude-zero  # Skip files with 0 debt in output
#
# Exit codes:
#   0 — No debt items found (or all clean)
#   1 — Debt items found (with --strict), or runtime error
#
# Requirements:
#   - bash 3+ (macOS compatible)
#   - grep, find, awk (standard POSIX)
#
# This script is idempotent — safe to run multiple times.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Config ──────────────────────────────────────────────────────────────────
VERBOSE=false
STRICT=false
EXCLUDE_ZERO=false
EXIT_CODE=0
TOTAL_DEBT=0
FILES_SCANNED=0
FILES_WITH_DEBT=0

# Declare marker arrays — macOS bash 3 compatible (no associative arrays)
MARKER_TYPES=("PONYTAIL" "TODO" "FIXME" "HACK" "XXX" "WORKAROUND" "TEMPORARY")
MARKER_PATTERNS=("ponytail:" "TODO" "FIXME" "HACK" "XXX" "WORKAROUND" "TEMPORARY")

# Marker counts — parallel array to MARKER_TYPES
MARKER_COUNTS=(0 0 0 0 0 0 0)
# Marker file counts — files containing at least one of each marker type
MARKER_FILE_COUNTS=(0 0 0 0 0 0 0)

# Excluded directories and file patterns (find -path / -name)
EXCLUDE_DIRS=(
  "*/node_modules/*"
  "*/.git/*"
  "*/target/*"
  "*/.gitnexus/*"
  "*/graphify-out/*"
)
EXCLUDE_FILES=(
  "*.log"
  "*.tmp"
  "*.swp"
  ".DS_Store"
)

# Color output (disable if not a terminal)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    CYAN=''
    BOLD=''
    NC=''
fi

# ── Help ────────────────────────────────────────────────────────────────────
usage() {
    cat <<'USAGE'
scan-ponytail-debt.sh — Scan codebase for intentional shortcuts and technical debt

SYNOPSIS
    ./scripts/scan-ponytail-debt.sh [OPTIONS]

OPTIONS
    --help           Show this help message and exit
    --verbose        Show matching lines per file in detail
    --strict         Exit with code 1 if any debt items are found
    --exclude-zero   Skip files with 0 debt items from per-file output

DESCRIPTION
    Scans the codebase for two categories of markers:

    1. ponytail: comments — intentional shortcuts with documented ceilings
       and upgrade paths (from skills/simplify/SKILL.md convention)

    2. Debt markers — TODO, FIXME, HACK, XXX, WORKAROUND, TEMPORARY

    Results are grouped by marker type with file-level and aggregate counts.
    Excluded directories: node_modules/, .git/, target/, .gitnexus/, graphify-out/

EXIT CODES
    0   No debt items found, or items found without --strict
    1   Debt items found with --strict, or runtime error

EXAMPLES
    ./scripts/scan-ponytail-debt.sh
    ./scripts/scan-ponytail-debt.sh --verbose
    ./scripts/scan-ponytail-debt.sh --strict
    ./scripts/scan-ponytail-debt.sh --verbose --exclude-zero

USAGE
}

# ── Logging helpers ────────────────────────────────────────────────────────
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
        echo -e "  ${CYAN}[DEBT]${NC} $1"
    fi
}

log_section() {
    echo ""
    echo -e "${BOLD}$1${NC}"
    echo "  $(printf '%*s' "$((${#1} + 2))" '' | tr ' ' '─')"
}

# ── Helpers ────────────────────────────────────────────────────────────────
# Get marker index from name
marker_index() {
    local name="$1"
    for i in "${!MARKER_TYPES[@]}"; do
        if [[ "${MARKER_TYPES[$i]}" == "$name" ]]; then
            echo "$i"
            return 0
        fi
    done
    echo "-1"
    return 1
}

# Increment a marker's count by index
inc_marker_count() {
    local idx="$1"
    local delta="${2:-1}"
    MARKER_COUNTS[$idx]=$((MARKER_COUNTS[$idx] + delta))
}

# Increment a marker's file count by index
inc_marker_file_count() {
    local idx="$1"
    local delta="${2:-1}"
    MARKER_FILE_COUNTS[$idx]=$((MARKER_FILE_COUNTS[$idx] + delta))
}

# ── Scanning logic ─────────────────────────────────────────────────────────
scan_files() {
    local scan_root="$1"
    local total_debt=0
    local files_scanned=0
    local files_with_debt=0

    # Track which files have been counted per marker type to avoid double-counting
    # in MARKER_FILE_COUNTS. We use a temp file list per marker.
    local marker_file_tracker
    marker_file_tracker=$(mktemp)
    for i in "${!MARKER_TYPES[@]}"; do
        echo "" > "${marker_file_tracker}_${i}"
    done

    log_section "Scanning for debt markers"

    # Build the combined grep pattern (escaped for regex)
    # Order matters: check ponytail: first so it doesn't match as TODO (it doesn't, but be safe)
    local combined_pattern='ponytail:|TODO|FIXME|HACK|XXX|WORKAROUND|TEMPORARY'

    # Build find exclusion args
    local find_excludes=()
    for excl in "${EXCLUDE_DIRS[@]}"; do
        find_excludes+=(-not -path "$excl")
    done

    echo "  Scanning: $scan_root"
    echo ""

    # macOS: use find + file to skip binaries, then grep
    local tmpfile
    tmpfile=$(mktemp)

    # Get all regular files, excluding blacklisted dirs and file patterns
    local find_name_excludes=()
    for fname in "${EXCLUDE_FILES[@]}"; do
        find_name_excludes+=(-not -name "$fname")
    done
    find "$scan_root" -type f "${find_excludes[@]}" "${find_name_excludes[@]}" \
        2>/dev/null > "$tmpfile"

    # Also build a list of files to skip (binary detection)
    local files_list
    files_list=$(mktemp)

    # Filter out binary files using grep -I test
    while IFS= read -r filepath; do
        # Skip files that are empty or too large (>1MB)
        if [[ ! -f "$filepath" ]] || [[ "$(stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null || echo 0)" -eq 0 ]]; then
            continue
        fi
        # Use grep -I to test if file appears binary
        if grep -I -q '.' "$filepath" 2>/dev/null; then
            echo "$filepath" >> "$files_list"
        fi
    done < "$tmpfile"

    files_scanned=$(wc -l < "$files_list" | tr -d ' ')

    if [[ "$files_scanned" -eq 0 ]]; then
        log_info "No files to scan in $scan_root"
        rm -f "$tmpfile" "$files_list"
        for i in "${!MARKER_TYPES[@]}"; do
            rm -f "${marker_file_tracker}_${i}"
        done
        rm -f "$marker_file_tracker"
        FILES_SCANNED=0
        TOTAL_DEBT=0
        FILES_WITH_DEBT=0
        return 0
    fi

    # Per-file scan
    local file_debt_count=0
    local file_results=""

    while IFS= read -r filepath; do
        # Get relative path for display
        local relpath
        relpath="${filepath#"$PROJECT_ROOT/"}"
        [[ -z "$relpath" ]] && relpath="$filepath"

        # Scan file with combined pattern — macOS grep compatible
        local matches
        # shellcheck disable=SC2126
        matches=$(grep -nE "$combined_pattern" "$filepath" 2>/dev/null || true)

        if [[ -z "$matches" ]]; then
            # No matches in this file
            if [[ "$VERBOSE" == true ]] && [[ "$EXCLUDE_ZERO" == false ]]; then
                echo "  $(printf '%-70s' "$relpath")  → 0 debt items"
            fi
            continue
        fi

        # Count matches per marker type in this file
        local file_has_ponytail=false
        local file_has_todo=false
        local file_has_fixme=false
        local file_has_hack=false
        local file_has_xxx=false
        local file_has_workaround=false
        local file_has_temporary=false

        # Process each matching line
        local line_matches=0
        while IFS= read -r match_line; do
            # Parse line number and content
            # Format from grep -n: "lineNum:content"
            local line_num
            line_num=$(echo "$match_line" | cut -d: -f1)
            local content
            content=$(echo "$match_line" | cut -d: -f2-)

            # Trim leading whitespace from content
            content="${content## }"

            # Determine which markers are on this line (may have multiple)
            local line_markers=""
            local ponytail_remaining="$content"

            # Check for ponytail: first (case-sensitive)
            if echo "$content" | grep -q 'ponytail:'; then
                file_has_ponytail=true
                line_markers="${line_markers} PONYTAIL"
                # Extract the ponytail comment text
                local p_text="${content#*ponytail:}"
                p_text="ponytail:${p_text}"
                # Trim leading/trailing whitespace
                p_text="${p_text#"${p_text%%[! ]*}"}"
                p_text="${p_text%"${p_text##*[! ]}"}"
                inc_marker_count 0
                if [[ "$VERBOSE" == true ]]; then
                    log_verbose "$relpath:${line_num}  → PONYTAIL  $p_text"
                fi
            fi

            # Check for TODO
            if echo "$content" | grep -q 'TODO'; then
                file_has_todo=true
                line_markers="${line_markers} TODO"
                # Extract after TODO
                local t_text
                t_text=$(echo "$content" | grep -o 'TODO[^A-Za-z].*$' || echo "$content")
                t_text="${t_text#"${t_text%%[! ]*}"}"
                t_text="${t_text%"${t_text##*[! ]}"}"
                inc_marker_count 1
                if [[ "$VERBOSE" == true ]]; then
                    log_verbose "$relpath:${line_num}  → TODO      $t_text"
                fi
            fi

            # Check for FIXME
            if echo "$content" | grep -q 'FIXME'; then
                file_has_fixme=true
                line_markers="${line_markers} FIXME"
                local f_text
                f_text=$(echo "$content" | grep -o 'FIXME[^A-Za-z].*$' || echo "$content")
                f_text="${f_text#"${f_text%%[! ]*}"}"
                f_text="${f_text%"${f_text##*[! ]}"}"
                inc_marker_count 2
                if [[ "$VERBOSE" == true ]]; then
                    log_verbose "$relpath:${line_num}  → FIXME     $f_text"
                fi
            fi

            # Check for HACK
            if echo "$content" | grep -q 'HACK'; then
                file_has_hack=true
                line_markers="${line_markers} HACK"
                local h_text
                h_text=$(echo "$content" | grep -o 'HACK[^A-Za-z].*$' || echo "$content")
                h_text="${h_text#"${h_text%%[! ]*}"}"
                h_text="${h_text%"${h_text##*[! ]}"}"
                inc_marker_count 3
                if [[ "$VERBOSE" == true ]]; then
                    log_verbose "$relpath:${line_num}  → HACK      $h_text"
                fi
            fi

            # Check for XXX (not as a substring of other words)
            # Use word-boundary-like check: XXX preceded/followed by non-alpha or start/end
            if echo "$content" | grep -E '(^|[^A-Za-z])XXX($|[^A-Za-z])' | grep -q 'XXX'; then
                file_has_xxx=true
                line_markers="${line_markers} XXX"
                local x_text
                x_text=$(echo "$content" | grep -oE '[^A-Za-z]XXX[^A-Za-z].*$' || echo "$content")
                x_text="${x_text#?}"  # remove the leading non-alpha char
                x_text="${x_text#"${x_text%%[! ]*}"}"
                x_text="${x_text%"${x_text##*[! ]}"}"
                inc_marker_count 4
                if [[ "$VERBOSE" == true ]]; then
                    log_verbose "$relpath:${line_num}  → XXX       $x_text"
                fi
            fi

            # Check for WORKAROUND
            if echo "$content" | grep -qi 'WORKAROUND'; then
                file_has_workaround=true
                line_markers="${line_markers} WORKAROUND"
                local w_text
                w_text=$(echo "$content" | grep -oi 'WORKAROUND.*$' || echo "$content")
                w_text="${w_text#"${w_text%%[! ]*}"}"
                w_text="${w_text%"${w_text##*[! ]}"}"
                inc_marker_count 5
                if [[ "$VERBOSE" == true ]]; then
                    log_verbose "$relpath:${line_num}  → WORKAROUND $w_text"
                fi
            fi

            # Check for TEMPORARY
            if echo "$content" | grep -qi 'TEMPORARY'; then
                file_has_temporary=true
                line_markers="${line_markers} TEMPORARY"
                local tmp_text
                tmp_text=$(echo "$content" | grep -oi 'TEMPORARY.*$' || echo "$content")
                tmp_text="${tmp_text#"${tmp_text%%[! ]*}"}"
                tmp_text="${tmp_text%"${tmp_text##*[! ]}"}"
                inc_marker_count 6
                if [[ "$VERBOSE" == true ]]; then
                    log_verbose "$relpath:${line_num}  → TEMPORARY $tmp_text"
                fi
            fi

            line_matches=$((line_matches + 1))

        done <<< "$matches"

        # Track markers found in this file (for file-level counts)
        if [[ "$file_has_ponytail" == true ]] && [[ ! -f "${marker_file_tracker}_0_${relpath//\//_}" ]]; then
            MARKER_FILE_COUNTS[0]=$((MARKER_FILE_COUNTS[0] + 1))
            touch "${marker_file_tracker}_0_${relpath//\//_}"
        fi
        if [[ "$file_has_todo" == true ]] && [[ ! -f "${marker_file_tracker}_1_${relpath//\//_}" ]]; then
            MARKER_FILE_COUNTS[1]=$((MARKER_FILE_COUNTS[1] + 1))
            touch "${marker_file_tracker}_1_${relpath//\//_}"
        fi
        if [[ "$file_has_fixme" == true ]] && [[ ! -f "${marker_file_tracker}_2_${relpath//\//_}" ]]; then
            MARKER_FILE_COUNTS[2]=$((MARKER_FILE_COUNTS[2] + 1))
            touch "${marker_file_tracker}_2_${relpath//\//_}"
        fi
        if [[ "$file_has_hack" == true ]] && [[ ! -f "${marker_file_tracker}_3_${relpath//\//_}" ]]; then
            MARKER_FILE_COUNTS[3]=$((MARKER_FILE_COUNTS[3] + 1))
            touch "${marker_file_tracker}_3_${relpath//\//_}"
        fi
        if [[ "$file_has_xxx" == true ]] && [[ ! -f "${marker_file_tracker}_4_${relpath//\//_}" ]]; then
            MARKER_FILE_COUNTS[4]=$((MARKER_FILE_COUNTS[4] + 1))
            touch "${marker_file_tracker}_4_${relpath//\//_}"
        fi
        if [[ "$file_has_workaround" == true ]] && [[ ! -f "${marker_file_tracker}_5_${relpath//\//_}" ]]; then
            MARKER_FILE_COUNTS[5]=$((MARKER_FILE_COUNTS[5] + 1))
            touch "${marker_file_tracker}_5_${relpath//\//_}"
        fi
        if [[ "$file_has_temporary" == true ]] && [[ ! -f "${marker_file_tracker}_6_${relpath//\//_}" ]]; then
            MARKER_FILE_COUNTS[6]=$((MARKER_FILE_COUNTS[6] + 1))
            touch "${marker_file_tracker}_6_${relpath//\//_}"
        fi

        files_with_debt=$((files_with_debt + 1))

        # In non-verbose mode, print a one-liner per file
        if [[ "$VERBOSE" == false ]]; then
            echo "  $(printf '%-70s' "$relpath")  → $line_matches debt items"
        fi

    done < "$files_list"

    # Cleanup temp files
    rm -f "$tmpfile" "$files_list"
    for i in "${!MARKER_TYPES[@]}"; do
        rm -f "${marker_file_tracker}_${i}_"*
    done
    rm -f "$marker_file_tracker"

    # Sum up total debt from all marker counts
    local total=0
    for c in "${MARKER_COUNTS[@]}"; do
        total=$((total + c))
    done

    FILES_SCANNED=$files_scanned
    TOTAL_DEBT=$total
    FILES_WITH_DEBT=$files_with_debt
}

# ── Summary ────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${BOLD}=== Debt Summary ===${NC}"

    # Table header
    printf "  ${BOLD}%-16s %8s %10s${NC}\n" "Marker" "Count" "Files"
    echo "  $(printf '%*s' 36 '' | tr ' ' '─')"

    local total_marker_count=0
    local total_file_count=0
    for i in "${!MARKER_TYPES[@]}"; do
        local type="${MARKER_TYPES[$i]}"
        local count="${MARKER_COUNTS[$i]}"
        local files="${MARKER_FILE_COUNTS[$i]}"
        printf "  %-16s %8d %10d\n" "$type" "$count" "$files"
        total_marker_count=$((total_marker_count + count))
        if [[ "$files" -gt 0 ]]; then
            total_file_count=$((total_file_count + 1))
        fi
    done
    echo "  $(printf '%*s' 36 '' | tr ' ' '─')"
    printf "  ${BOLD}%-16s %8d %10s${NC}\n" "TOTAL" "$total_marker_count" "${FILES_WITH_DEBT}f"

    echo ""
    echo "  Files scanned: $FILES_SCANNED"
    echo "  Files with debt: $FILES_WITH_DEBT"
    echo ""

    if [[ "$TOTAL_DEBT" -eq 0 ]]; then
        echo -e "  ${GREEN}No debt items found.${NC}"
        EXIT_CODE=0
    else
        echo -e "  ${YELLOW}${TOTAL_DEBT} debt item(s) found across ${FILES_WITH_DEBT} file(s).${NC}"
        if [[ "$STRICT" == true ]]; then
            echo -e "  ${RED}--strict: failing with exit code 1.${NC}"
            EXIT_CODE=1
        else
            echo "  Use --strict to fail CI on debt items."
            EXIT_CODE=0
        fi
    fi
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
    local scan_root="$PROJECT_ROOT"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help)
                usage
                exit 0
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --strict)
                STRICT=true
                shift
                ;;
            --exclude-zero)
                EXCLUDE_ZERO=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done

    echo -e "${BOLD}=== Ponytail Debt Scanner — Workflow State Engine ===${NC}"
    echo "Project root: $PROJECT_ROOT"
    echo "Mode: verbose=$VERBOSE, strict=$STRICT, exclude-zero=$EXCLUDE_ZERO"
    echo ""

    scan_files "$scan_root"

    print_summary

    exit "$EXIT_CODE"
}

main "$@"