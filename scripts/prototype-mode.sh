#!/usr/bin/env bash
set -euo pipefail
# prototype-mode.sh -- Prototype-First Mode (G26)
# Implements a prototype-first development mode where agents use a lightweight,
# low-ceremony workflow instead of the full state machine. In prototype mode:
#   - SDD gate is skipped (no spec required before EXECUTE)
#   - Scoring pipeline is bypassed
#   - Single-pass execute (no retry cycles for prototype code)
#   - Auto-merge (no formal review gate for prototype branches)
# Ponytail intensity is read from rules.json -> ponytail.intensity for prototype behavior.
# Mode state is stored in session/{branch}/.mode file.
# Usage:
#   ./scripts/prototype-mode.sh --enable            # Enable prototype mode
#   ./scripts/prototype-mode.sh --disable           # Disable prototype mode
#   ./scripts/prototype-mode.sh --status            # Check if active
#   ./scripts/prototype-mode.sh --enable --verbose   # Enable with detail
#   ./scripts/prototype-mode.sh --disable --dry-run  # Preview disable
#   ./scripts/prototype-mode.sh --help               # Show usage
# Exit: 0=success, 1=error, 2=usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
MODE_ACTION=""; VERBOSE=false; DRY_RUN=false

usage() {
  cat <<'USAGE_EOF'
prototype-mode.sh - Prototype-First Mode (G26)

Toggle prototype-first development mode for the current branch.
Prototype mode: skip SDD gate, bypass scoring, single-pass execute, auto-merge.

Usage:
  --enable            Enable prototype mode
  --disable           Disable, restore full orchestration
  --status            Check if active
  --verbose           Detailed output
  --dry-run           Show what would be done
  --help              This message

State file: session/{branch}/.mode
  Enabled: {"mode":"prototype","ponytail_intensity":"...","enabled_at":"..."}
  Disabled: file removed

Exit codes: 0=success, 1=error, 2=usage
USAGE_EOF
}

log_pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
log_info() { echo -e "  ${YELLOW}[INFO]${NC} $1"; }
log_verbose() { [[ "$VERBOSE" == true ]] && echo -e "  ${CYAN}[VERB]${NC} $1"; }
log_dry() { echo -e "  ${CYAN}[DRY-RUN]${NC} $1"; }
log_section() { echo -e "${BOLD}  $1${NC}"; echo "  $(printf '%*s' "$((${#1}+2))" '' | tr ' ' '-')"; }

get_br() {
  if ! git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    log_fail "Not in a git repository"; exit 1; fi
  local br; br="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -z "$br" || "$br" == "HEAD" ]]; then
    log_fail "Cannot detect branch (detached HEAD?)"; exit 1; fi
  echo "$br"
}

load_ponytail_config() {
  local f="$PROJECT_DIR/rules/rules.json"
  [[ ! -f "$f" ]] && { log_verbose "rules.json not found"; echo "high"; return; }
  if ! command -v jq &>/dev/null; then echo "high"; return; fi
  jq -r '.ponytail.default_intensity // "high"' "$f" 2>/dev/null || echo "high"
}

build_mode_json() {
  local ts; ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if command -v jq &>/dev/null; then
    jq -n --arg mode "prototype" --arg intensity "$1" --arg ts "$ts" \
      '{mode: $mode, ponytail_intensity: $intensity, enabled_at: $ts}'
  else
    printf '{"mode":"prototype","ponytail_intensity":"%s","enabled_at":"%s"}\n' "$1" "$ts"
  fi
}

cmd_enable() {
  local br; br="$(get_br)"; local d="$PROJECT_DIR/session/$br"
  local mf="$d/.mode"; local lf="$PROJECT_DIR/.prototype-mode"
  local pi; pi="$(load_ponytail_config)"
  log_section "Enable Prototype Mode - Branch: ${br}"
  log_info "Ponytail intensity: ${pi}"
  if [[ "$DRY_RUN" == true ]]; then
    log_dry "Would create: $mf and $lf"; log_pass "Dry-run complete"; return; fi
  mkdir -p "$d"; echo "$(build_mode_json "$pi")" > "$mf"
  echo "$(build_mode_json "$pi")" > "$lf"
  log_pass "Prototype mode ENABLED for branch '${br}'"
  log_info "Effects: SDD skipped, scoring bypassed, single-pass, auto-merge"
}

cmd_disable() {
  local br; br="$(get_br)"; local d="$PROJECT_DIR/session/$br"
  local mf="$d/.mode"; local lf="$PROJECT_DIR/.prototype-mode"
  log_section "Disable Prototype Mode - Branch: ${br}"
  if [[ ! -f "$mf" && ! -f "$lf" ]]; then
    log_info "Not active - nothing to disable"; exit 0; fi
  if [[ "$DRY_RUN" == true ]]; then
    [[ -f "$mf" ]] && log_dry "Would remove: $mf"
    [[ -f "$lf" ]] && log_dry "Would remove: $lf"; log_pass "Dry-run complete"; return; fi
  local n=0
  [[ -f "$mf" ]] && { rm "$mf"; n=$((n+1)); }
  [[ -f "$lf" ]] && { rm "$lf"; n=$((n+1)); }
  [[ "$n" -gt 0 ]] && log_pass "Prototype mode DISABLED" || log_info "Nothing to remove"
}

cmd_status() {
  local br; br="$(get_br)"; local mf="$PROJECT_DIR/session/$br/.mode"
  local lf="$PROJECT_DIR/.prototype-mode"
  log_section "Prototype Mode Status - Branch: ${br}"
  if [[ -f "$mf" ]]; then
    echo -e "  ${GREEN}ACTIVE${NC} (session/${br}/.mode)"
    if command -v jq &>/dev/null; then
      echo "  Ponytail intensity: $(jq -r '.ponytail_intensity // "unknown"' "$mf")"
      echo "  Enabled at: $(jq -r '.enabled_at // "unknown"' "$mf")"; fi
  elif [[ -f "$lf" ]]; then
    echo -e "  ${YELLOW}ACTIVE (legacy)${NC} (.prototype-mode marker, no session/.mode)"
    log_info "Run --enable to upgrade to current format"
  else
    echo -e "  ${CYAN}INACTIVE${NC} (full orchestration mode)"
    log_info "Use --enable to switch to prototype mode"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --enable) MODE_ACTION="enable"; shift ;;
    --disable) MODE_ACTION="disable"; shift ;;
    --status) MODE_ACTION="status"; shift ;;
    --verbose) VERBOSE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown: $1. Use --help." >&2; exit 2 ;;
  esac
done

if [[ -z "$MODE_ACTION" ]]; then
  echo -e "${RED}Error:${NC} Specify --enable, --disable, or --status. Use --help." >&2; exit 1; fi
command -v jq &>/dev/null || log_info "jq not available - basic mode only"
case "$MODE_ACTION" in enable) cmd_enable ;; disable) cmd_disable ;; status) cmd_status ;; esac
