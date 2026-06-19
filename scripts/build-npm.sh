#!/usr/bin/env bash
# build-npm.sh — Build npm package tarball of the Workflow State Engine toolkit (G4)
# Packages essential toolkit files into a distributable .tgz in dist/.
# Reads or creates package.json, generates version from git tag or date,
# creates a manifest of all included files.
#   ./scripts/build-npm.sh                          # Build tarball in dist/
#   ./scripts/build-npm.sh --help                    # Show usage
#   ./scripts/build-npm.sh --dry-run                 # Show what would be done
#   ./scripts/build-npm.sh --verbose                 # Detailed output
#   ./scripts/build-npm.sh --output /path/to/dist    # Custom output directory
#   0 — Package built successfully
#   1 — Partial success (some files missing, package created with warnings)
#   2 — Error (missing deps, write failure, critical issues)
#   3 — Usage displayed
# Requirements:
#   - bash 4+
#   - tar (for packaging)
#   - jq (optional, for package.json manipulation & manifest)
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
OUTPUT_DIR="$PROJECT_ROOT/dist"
EXIT_CODE=0
MISSING_FILES=0

# --- Package manifest (files to include in the tarball) ---
# Patterns resolved at packaging time. Globs expand only when files exist.
declare -a PACKAGE_PATTERNS=(
    "scripts/*.sh"
    "contract/*.json"
    "rules/rules.json"
    "agents/*.md"
    "skills/*/SKILL.md"
    "usage/*.md"
    "agent.md"
    "README.md"
    "setup.sh"
)

# --- Logging functions ---
log_pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $1" >&2; EXIT_CODE=1; }
log_info() { echo -e "  ${YELLOW}[INFO]${NC} $1"; }
log_verbose() { if [[ "$VERBOSE" == true ]]; then echo -e "  ${CYAN}[VERB]${NC} $1"; fi; }
log_dry()   { echo -e "  ${CYAN}[DRY-RUN]${NC} $1"; }

# --- Usage ---
usage() {
    cat <<'USAGE'
build-npm.sh — Build npm package tarball of the Workflow State Engine toolkit (G4)

Packages essential toolkit files (scripts, contracts, rules, agents, skills,
usage docs) into a distributable .tgz in dist/.

Usage:
    ./scripts/build-npm.sh [OPTIONS]

Options:
    --output PATH   Output directory for the tarball (default: dist/)
    --dry-run       Show what would be done without modifying anything
    --verbose       Print detailed output for each step
    --help          Show this usage information

Exit codes:
    0 — Package built successfully
    1 — Partial success (some files missing, package created with warnings)
    2 — Error (missing deps, write failure, critical issues)

Examples:
    ./scripts/build-npm.sh
    ./scripts/build-npm.sh --verbose
    ./scripts/build-npm.sh --dry-run
    ./scripts/build-npm.sh --output /tmp/release
USAGE
    exit 3
}

# --- Dependency checks ---
check_deps() {
    local missing=false

    if ! command -v tar &>/dev/null; then
        log_fail "tar is required but not installed"
        missing=true
    fi

    if ! command -v jq &>/dev/null; then
        log_info "jq not available — package.json will be created without metadata manipulation"
    fi

    if [[ "$missing" == true ]]; then
        log_fail "Missing required dependencies. Install tar first."
        exit 2
    fi

    log_pass "All required dependencies available (tar)"
    if command -v jq &>/dev/null; then
        log_verbose "Optional dependency jq is available"
    fi
}

# --- Generate version ---
# Uses git tag if available, otherwise date-based version YYYY.MM.DD.HHMM
generate_version() {
    local version=""

    # Try git tag (latest annotated tag, strip leading 'v')
    if git -C "$PROJECT_ROOT" rev-parse --git-dir &>/dev/null; then
        version="$(git -C "$PROJECT_ROOT" describe --tags --abbrev=0 2>/dev/null || true)"
        version="${version#v}"  # strip leading 'v'
    fi

    # Fallback: date-based
    if [[ -z "$version" ]]; then
        version="$(date -u '+%Y.%m.%d.%H%M')"
        log_verbose "No git tag found — using date-based version: $version"
    else
        log_verbose "Using git tag version: $version"
    fi

    echo "$version"
}

# --- Ensure or create package.json ---
ensure_package_json() {
    local pkg_json="$PROJECT_ROOT/package.json"
    local version="$1"

    if [[ -f "$pkg_json" ]]; then
        log_verbose "package.json exists at: $pkg_json"
        if command -v jq &>/dev/null; then
            local existing_version
            existing_version="$(jq -r '.version // ""' "$pkg_json" 2>/dev/null || true)"
            if [[ -n "$existing_version" ]]; then
                log_verbose "Existing version in package.json: $existing_version"
            fi
        fi
        echo "$pkg_json"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would create package.json with version $version"
        echo "$PROJECT_ROOT/package.json"
        return 0
    fi

    log_info "Creating package.json at: $pkg_json"
    cat > "$pkg_json" <<PKGJSON
{
  "name": "workflow-state-engine",
  "version": "${version}",
  "description": "Contract-driven state machine orchestration engine for AI agent workflows",
  "license": "MIT",
  "author": "Workflow State Engine",
  "keywords": [
    "opencode",
    "orchestration",
    "state-machine",
    "ai-agents",
    "workflow"
  ],
  "files": [
    "scripts/*.sh",
    "contract/*.json",
    "rules/rules.json",
    "agents/*.md",
    "skills/*/SKILL.md",
    "usage/*.md",
    "agent.md",
    "README.md",
    "setup.sh"
  ]
}
PKGJSON
    log_pass "package.json created with version $version"
    echo "$pkg_json"
}

# --- Resolve file list from patterns ---
# Glob patterns are expanded at runtime. Missing patterns are warned but
# do not block packaging (partial success = exit 1).
resolve_file_list() {
    local pkg_root="$1"
    local -a files=()
    local pattern expanded

    cd "$pkg_root"

    for pattern in "${PACKAGE_PATTERNS[@]}"; do
        # shellcheck disable=SC2086
        expanded="$(find . -path "./${pattern}" -type f 2>/dev/null || true)"

        if [[ -z "$expanded" ]]; then
            log_info "No files matched pattern: $pattern"
            MISSING_FILES=$((MISSING_FILES + 1))
        else
            while IFS= read -r f; do
                # Remove leading ./ for clean paths
                f="${f#./}"
                files+=("$f")
                log_verbose "  + $f"
            done <<< "$expanded"
        fi
    done

    echo "${files[@]}"
}

# --- Write manifest file ---
write_manifest() {
    local manifest_file="$1"
    local version="$2"
    local -a files=("${@:3}")
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would write manifest to: $manifest_file"
        return 0
    fi

    mkdir -p "$(dirname "$manifest_file")"

    cat > "$manifest_file" <<MANIFEST
# Workflow State Engine — Package Manifest
# Generated: $timestamp
# Version: $version
# Total files: ${#files[@]}
MANIFEST
    echo "" >> "$manifest_file"
    for f in "${files[@]}"; do
        echo "$f" >> "$manifest_file"
    done

    log_pass "Manifest written: $manifest_file (${#files[@]} files)"
}

# --- Create tarball ---
create_tarball() {
    local version="$1"
    local pkg_root="$2"
    local output_dir="$3"
    local -a files=("${@:4}")

    local tarball_name="workflow-state-engine-${version}.tgz"
    local tarball_path="$output_dir/$tarball_name"

    if [[ "$DRY_RUN" == true ]]; then
        log_dry "Would create tarball: $tarball_path"
        log_dry "  Working directory: $pkg_root"
        log_dry "  Files (${#files[@]}):"
        for f in "${files[@]}"; do
            log_dry "    $f"
        done
        return 0
    fi

    # Ensure output dir exists
    mkdir -p "$output_dir"

    # Create tarball from project root with clean paths
    # tar --transform prefixes with package dir for npm-friendly layout
    cd "$pkg_root"
    local package_dir="package"

    if command -v gtar &>/dev/null; then
        # macOS with GNU tar via homebrew
        gtar -czf "$tarball_path" \
            --transform "s|^|${package_dir}/|" \
            "${files[@]}" 2>&1
    else
        # BSD tar (macOS) or GNU tar (Linux)
        tar -czf "$tarball_path" \
            --transform "s|^|${package_dir}/|" \
            "${files[@]}" 2>/dev/null \
        || tar -czf "$tarball_path" \
            -s "/^/${package_dir}\//" \
            "${files[@]}" 2>/dev/null \
        || {
            # Fallback: tar without transform, warn about flat layout
            log_info "tar does not support path transforms — tarball will have flat paths"
            tar -czf "$tarball_path" "${files[@]}"
        }
    fi

    log_pass "Tarball created: $tarball_path"
    log_verbose "  Size: $(du -h "$tarball_path" | cut -f1)"
    log_verbose "  Files: ${#files[@]}"

    # Create a symlink 'latest' pointing to this tarball
    local latest_link="$output_dir/workflow-state-engine-latest.tgz"
    ln -sf "$tarball_name" "$latest_link" 2>/dev/null || true
    log_verbose "Symlink: $latest_link → $tarball_name"
}

# --- Print summary ---
print_summary() {
    local version="$1"
    local output_dir="$2"
    local file_count="$3"

    echo ""
    echo "=== Build Summary — Workflow State Engine ==="
    echo "  Version:    $version"
    echo "  Output:     $output_dir/"
    echo "  Files:      $file_count"
    echo "  Tarball:    workflow-state-engine-${version}.tgz"
    echo "  Symlink:    workflow-state-engine-latest.tgz"
    echo ""

    if [[ "$MISSING_FILES" -gt 0 ]]; then
        echo -e "  ${YELLOW}Warning: $MISSING_FILES file pattern(s) had no matches${NC}"
    fi
    if [[ "$EXIT_CODE" -eq 0 ]]; then
        echo -e "  ${GREEN}Build: PASS${NC}"
    else
        echo -e "  ${YELLOW}Build: PARTIAL (exit code 1)${NC}"
    fi
}

# --- Argument parsing ---
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                usage
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
    echo "=== Build NPM Package — Workflow State Engine ==="
    echo ""

    # Step 1: Check dependencies
    echo "Step 1: Check dependencies"
    check_deps
    echo ""

    # Step 2: Generate version
    echo "Step 2: Generate version"
    local version
    version="$(generate_version)"
    log_pass "Version: $version"
    echo ""

    # Step 3: Ensure package.json
    echo "Step 3: Ensure package.json"
    local pkg_json
    pkg_json="$(ensure_package_json "$version")"
    if [[ "$DRY_RUN" == false ]]; then
        log_pass "Package.json: $pkg_json"
    fi
    echo ""

    # Step 4: Resolve file list
    echo "Step 4: Resolve files"
    local -a file_list
    IFS=' ' read -r -a file_list <<< "$(resolve_file_list "$PROJECT_ROOT")"
    local file_count=${#file_list[@]}
    log_pass "Resolved $file_count file(s)"
    if [[ "$VERBOSE" == true ]]; then
        for f in "${file_list[@]}"; do
            echo "    $f"
        done
    fi
    echo ""

    # Step 5: Write manifest
    echo "Step 5: Write manifest"
    local manifest_file="$OUTPUT_DIR/.manifest"
    if [[ "$DRY_RUN" == false ]]; then
        write_manifest "$manifest_file" "$version" "${file_list[@]}"
    else
        write_manifest "$manifest_file" "$version" "${file_list[@]}"
    fi
    echo ""

    # Step 6: Create tarball
    echo "Step 6: Create tarball"
    create_tarball "$version" "$PROJECT_ROOT" "$OUTPUT_DIR" "${file_list[@]}"
    echo ""

    # Step 7: Summary
    print_summary "$version" "$OUTPUT_DIR" "$file_count"

    # Exit code determination
    if [[ "$EXIT_CODE" -ne 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
