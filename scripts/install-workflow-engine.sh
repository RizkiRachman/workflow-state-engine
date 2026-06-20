#!/usr/bin/env bash
# shellcheck disable=SC2086
# scripts/install-workflow-engine.sh — Consumer-facing installation script
#
# Installs the workflow-state-engine as a git submodule into a consumer project.
# Sets up .opencode/ symlinks, session scaffolding, git hooks, and validates.
#
# Usage:
#   bash scripts/install-workflow-engine.sh [OPTIONS]
#
# Options:
#   --url <URL>           Submodule URL (default: https://github.com/RizkiRachman/workflow-state-engine.git)
#   --model <MODEL>       AI model ID (default: sumopod/deepseek-v4-flash)
#   --type <TYPE>         Service type: core|ui|support|infra (default: core)
#   --firecrawl-key <KEY> Firecrawl API key
#   --lean-ctx <PATH>     Path to lean-ctx binary (default: autodetect)
#   --update              Update existing submodule to latest
#   --force               Skip safety checks (uncommitted changes, branch checks)
#   --hooks               Install git hooks (default: true)
#   --help                Show this help
#
# Exit codes:
#   0 — Installation successful
#   1 — Partial success (warnings)
#   2 — Error (requirements not met)

set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────────────
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_DIR="$(pwd)"

# Defaults
SUBMODULE_URL="https://github.com/RizkiRachman/workflow-state-engine.git"
SUBMODULE_PATH=".workflow-engine"
AI_MODEL="sumopod/deepseek-v4-flash"
SERVICE_TYPE="core"
FIRECRAWL_KEY=""
LEAN_CTX_PATH=""
UPDATE_MODE=false
FORCE_MODE=false
INSTALL_HOOKS=true

# State tracking
EXIT_CODE=0
WARNINGS=0
ERRORS=0
PASS_STEPS=0
FAIL_STEPS=0
WARN_STEPS=0

# Colors (disable if not a terminal)
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

# ── Logging Helpers ────────────────────────────────────────────────────────────
log_pass()  { echo -e "  ${GREEN}[PASS]${NC} $1"; ((PASS_STEPS++)); }
log_fail()  { echo -e "  ${RED}[FAIL]${NC} $1"; ((FAIL_STEPS++)); EXIT_CODE=2; }
log_warn()  { echo -e "  ${YELLOW}[WARN]${NC} $1"; ((WARN_STEPS++)); WARNINGS=$((WARNINGS + 1)); }
log_info()  { echo -e "  ${CYAN}[INFO]${NC} $1"; }
log_step()  { echo ""; echo -e "${CYAN}==> Step $1:${NC} $2"; }
log_err()   { echo -e "  ${RED}[FAIL]${NC} $1" >&2; ((FAIL_STEPS++)); EXIT_CODE=2; }

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
  cat <<USAGE
${CYAN}${SCRIPT_NAME}${NC} — Install Workflow State Engine into a consumer project

${CYAN}USAGE${NC}
  bash ${SCRIPT_NAME} [OPTIONS]

${CYAN}OPTIONS${NC}
  --url <URL>           Submodule URL (default: ${SUBMODULE_URL})
  --model <MODEL>       AI model ID (default: ${AI_MODEL})
  --type <TYPE>         Service type: core|ui|support|infra (default: ${SERVICE_TYPE})
  --firecrawl-key <KEY> Firecrawl API key
  --lean-ctx <PATH>     Path to lean-ctx binary (default: autodetect)
  --update              Update existing submodule to latest
  --force               Skip safety checks (uncommitted changes, branch checks)
  --hooks               Install git hooks (default: true)
  --help                Show this help

${CYAN}EXIT CODES${NC}
  0   Installation successful
  1   Partial success (some warnings)
  2   Error (requirements not met)

${CYAN}EXAMPLE${NC}
  cd /path/to/my-service
  bash ${SCRIPT_DIR}/${SCRIPT_NAME} --model sumopod/deepseek-v4-flash --type core

USAGE
  exit 0
}

# ── Parse Arguments ────────────────────────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --url)
        SUBMODULE_URL="$2"; shift 2 ;;
      --model)
        AI_MODEL="$2"; shift 2 ;;
      --type)
        SERVICE_TYPE="$2"; shift 2 ;;
      --firecrawl-key)
        FIRECRAWL_KEY="$2"; shift 2 ;;
      --lean-ctx)
        LEAN_CTX_PATH="$2"; shift 2 ;;
      --update)
        UPDATE_MODE=true; shift ;;
      --force)
        FORCE_MODE=true; shift ;;
      --hooks)
        INSTALL_HOOKS=true; shift ;;
      --help|-h)
        usage ;;
      *)
        log_err "Unknown option: $1"
        echo "  Try '${SCRIPT_NAME} --help' for usage."
        exit 2 ;;
    esac
  done
}

# ── Step 1: Check Prerequisites ────────────────────────────────────────────────
check_prerequisites() {
  log_step "1" "Checking prerequisites"

  # 1a. Must be a git repo
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    log_fail "Not in a git repository — run this script from the consumer project root"
    return 1
  fi
  log_pass "Git repository detected: $(git rev-parse --show-toplevel 2>/dev/null)"

  # 1b. Check for uncommitted changes (unless --force)
  if [[ "$FORCE_MODE" != true ]]; then
    if ! git diff --quiet HEAD 2>/dev/null; then
      log_fail "Uncommitted changes detected. Commit or stash first, or use --force"
      return 1
    fi
    log_pass "Working tree clean (no uncommitted changes)"
  else
    log_info "Skipping uncommitted changes check (--force)"
  fi

  # 1c. Verify essential tools
  local missing=()
  command -v git    &>/dev/null || missing+=("git")
  command -v jq     &>/dev/null || log_warn "jq not found — JSON operations will use python3 fallback"
  command -v python3 &>/dev/null || log_warn "python3 not found — JSON validation unavailable"

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_fail "Missing required tools: ${missing[*]}"
    return 1
  fi
  log_pass "All required tools available"
}

# ── Step 2: Branch Management ──────────────────────────────────────────────────
manage_branch() {
  log_step "2" "Checking branch"
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"

  if [[ "$FORCE_MODE" == true ]]; then
    log_info "Skipping branch check (--force). Current branch: ${current_branch}"
    return 0
  fi

  if [[ "$current_branch" == "main" || "$current_branch" == "master" ]]; then
    local new_branch="feature/enable-workflow-engine"
    log_info "On '${current_branch}' — creating feature branch '${new_branch}'"
    if git checkout -b "$new_branch" 2>/dev/null; then
      log_pass "Created and switched to branch: ${new_branch}"
    else
      # Branch may already exist, try switching
      if git checkout "$new_branch" 2>/dev/null; then
        log_pass "Switched to existing branch: ${new_branch}"
      else
        log_fail "Failed to create or switch to branch '${new_branch}'"
        return 1
      fi
    fi
  else
    log_pass "Already on feature branch: ${current_branch}"
  fi
}

# ── Step 3: Submodule Setup ────────────────────────────────────────────────────
setup_submodule() {
  log_step "3" "Setting up git submodule"
  local submodule_dir="${PROJECT_DIR}/${SUBMODULE_PATH}"

  if [[ -d "$submodule_dir" ]]; then
    # Check if it's a valid submodule
    local sub_status
    sub_status="$(git submodule status "${SUBMODULE_PATH}" 2>/dev/null || true)"

    if [[ -n "$sub_status" ]]; then
      log_info "Submodule already exists at ${SUBMODULE_PATH}/"

      # Verify URL matches
      local actual_url
      actual_url="$(git config --local --get "submodule.${SUBMODULE_PATH}.url" 2>/dev/null || true)"
      if [[ -n "$actual_url" && "$actual_url" != "$SUBMODULE_URL" ]]; then
        log_warn "Existing submodule URL (${actual_url}) differs from requested (${SUBMODULE_URL})"
        log_info "  Using existing URL. Remove submodule to change."
      fi

      if [[ "$UPDATE_MODE" == true ]]; then
        log_info "Updating submodule to latest..."
        if git submodule update --remote "${SUBMODULE_PATH}" 2>/dev/null; then
          log_pass "Submodule updated to latest"
        else
          log_warn "Submodule update failed — continuing with current version"
        fi
      fi
    else
      log_info "Directory ${SUBMODULE_PATH}/ exists but is not a submodule"
      log_fail "Remove or rename '${SUBMODULE_PATH}/' manually, then re-run"
      return 1
    fi
  else
    log_info "Adding submodule from ${SUBMODULE_URL}"
    if git submodule add "$SUBMODULE_URL" "$SUBMODULE_PATH" 2>/dev/null; then
      log_pass "Submodule added: ${SUBMODULE_PATH}/"
    else
      log_fail "Failed to add submodule"
      return 1
    fi
  fi
}

# ── Step 4: Gitignore Fix ──────────────────────────────────────────────────────
fix_gitignore() {
  log_step "4" "Checking .gitignore for ${SUBMODULE_PATH}"
  local gitignore="${PROJECT_DIR}/.gitignore"

  if [[ ! -f "$gitignore" ]]; then
    log_pass "No .gitignore file — nothing to check"
    return 0
  fi

  # Check if .workflow-engine is listed in .gitignore
  if grep -q "^\.workflow-engine" "$gitignore" 2>/dev/null; then
    log_warn "${SUBMODULE_PATH} found in .gitignore — removing entry"

    # Try GNU sed first, then macOS sed
    if sed -i.bak "/^\.workflow-engine/d" "$gitignore" 2>/dev/null; then
      rm -f "${gitignore}.bak" 2>/dev/null || true
      log_pass "Removed '${SUBMODULE_PATH}' from .gitignore"
    elif sed -i '' "/^\.workflow-engine/d" "$gitignore" 2>/dev/null; then
      log_pass "Removed '${SUBMODULE_PATH}' from .gitignore"
    else
      log_fail "Failed to edit .gitignore — remove '${SUBMODULE_PATH}' entry manually"
      return 1
    fi
  else
    log_pass ".gitignore does not contain ${SUBMODULE_PATH}"
  fi
}

# ── Step 5: Create .opencode/ Symlinks ─────────────────────────────────────────
create_opencode_symlinks() {
  log_step "5" "Creating .opencode/ symlinks"
  local violations=0
  local opencode_dir="${PROJECT_DIR}/.opencode"

  # Ensure .opencode/ exists
  mkdir -p "$opencode_dir"

  # Define symlinks: relative_target -> consumer's .opencode/<name>
  declare -A SYMLINKS=(
    ["agents"]="../.workflow-engine/agents"
    ["config"]="../.workflow-engine/config"
    ["rules"]="../.workflow-engine/rules"
    ["skills"]="../.workflow-engine/skills"
    ["usage"]="../.workflow-engine/usage"
    ["orchestration"]="../.workflow-engine/contract"
    ["plugins"]="../.workflow-engine/plugins"
  )

  for name in "${!SYMLINKS[@]}"; do
    local link_path="${opencode_dir}/${name}"
    local link_target="${SYMLINKS[$name]}"

    # Remove existing symlink, file, or directory
    if [[ -L "$link_path" ]] || [[ -e "$link_path" ]]; then
      rm -rf "$link_path"
      log_info "Removed existing: .opencode/${name}"
    fi

    # Create symlink (use -sfn for macOS compatibility: -n = don't follow)
    if ln -sfn "$link_target" "$link_path" 2>/dev/null; then
      log_pass "Symlink created: .opencode/${name} -> ${link_target}"
    else
      log_fail "Failed to create symlink: .opencode/${name}"
      violations=$((violations + 1))
    fi
  done

  if [[ "$violations" -eq 0 ]]; then
    log_pass "All 7 .opencode/ symlinks created successfully"
  fi
  return "$violations"
}

# ── Step 6: Create Session Scaffolding ─────────────────────────────────────────
create_session_scaffolding() {
  log_step "6" "Creating session/ scaffolding"
  local session_dir="${PROJECT_DIR}/session"
  local main_dir="${session_dir}/main"

  # Create session/ directory structure
  mkdir -p "${main_dir}"
  mkdir -p "${session_dir}/feature"

  # Copy contract.json from template
  local contract_template
  local contract_target="${main_dir}/contract.json"

  if [[ -f "${ENGINE_DIR}/contract/contract.template.json" ]]; then
    contract_template="${ENGINE_DIR}/contract/contract.template.json"
  elif [[ -f "${ENGINE_DIR}/contract/meta-contract.template.json" ]]; then
    contract_template="${ENGINE_DIR}/contract/meta-contract.template.json"
  else
    contract_template=""
  fi

  if [[ -n "$contract_template" ]]; then
    if [[ ! -f "$contract_target" ]]; then
      cp "$contract_template" "$contract_target"
      log_pass "Created: session/main/contract.json"
    else
      log_info "session/main/contract.json already exists — skipping"
    fi
  else
    # Create minimal contract JSON
    cat > "$contract_target" <<'CONTRACTJSON'
{
  "contract_version": "0.8.0",
  "session": {},
  "scope": {},
  "outputs": {},
  "state": "INIT",
  "decisions": {},
  "governance": {}
}
CONTRACTJSON
    log_pass "Created minimal: session/main/contract.json"
  fi

  # Copy contract.schema.json
  if [[ -f "${ENGINE_DIR}/contract/contract.schema.json" ]]; then
    local schema_target="${main_dir}/contract.schema.json"
    if [[ ! -f "$schema_target" ]]; then
      cp "${ENGINE_DIR}/contract/contract.schema.json" "$schema_target"
      log_pass "Created: session/main/contract.schema.json"
    else
      log_info "session/main/contract.schema.json already exists — skipping"
    fi
  else
    log_warn "contract.schema.json not found in submodule — skipping schema copy"
  fi

  # Create state.md
  local state_target="${main_dir}/state.md"
  if [[ ! -f "$state_target" ]]; then
    if [[ -f "${ENGINE_DIR}/contract/state.template.md" ]]; then
      cp "${ENGINE_DIR}/contract/state.template.md" "$state_target"
      log_pass "Created: session/main/state.md (from template)"
    else
      # Create minimal state.md
      cat > "$state_target" <<'STATEMD'
# Session State — Workflow State Engine
<!-- Session state for main branch. Managed by orchestration toolkit. -->

## Current Focus
<!-- Describe the current focus of work -->

## Known Blockers
<!-- List any blockers or issues -->

## Completed Work
<!-- Chronological log of completed work items -->
STATEMD
      log_pass "Created minimal: session/main/state.md"
    fi
  else
    log_info "session/main/state.md already exists — skipping"
  fi

  log_pass "Session scaffolding created at session/"
}

# ── Step 7: Generate Consumer Config ───────────────────────────────────────────
generate_consumer_config() {
  log_step "7" "Generating consumer config"

  local submodule_scripts="${PROJECT_DIR}/${SUBMODULE_PATH}/scripts"
  local local_gen_script="${ENGINE_DIR}/scripts/generate-consumer-config.sh"
  local submodule_gen_script="${submodule_scripts}/generate-consumer-config.sh"
  local gen_script=""

  if [[ -f "$local_gen_script" ]]; then
    gen_script="$local_gen_script"
    log_info "Found generate-consumer-config.sh in local engine: ${ENGINE_DIR}/scripts/"
  elif [[ -f "$submodule_gen_script" ]]; then
    gen_script="$submodule_gen_script"
    log_info "Found generate-consumer-config.sh in submodule: ${submodule_gen_script}"
  else
    log_info "generate-consumer-config.sh not found — skipping config generation"
    log_info "  (Checked: ${local_gen_script} and ${submodule_gen_script})"
    log_info "  (Use scripts/generate-config.sh for basic config generation)"
    return 0
  fi

  log_info "Running: generate-consumer-config.sh --model ${AI_MODEL} --type ${SERVICE_TYPE}"

  local gen_args=()
  gen_args+=("--model" "$AI_MODEL")
  gen_args+=("--type" "$SERVICE_TYPE")

  if [[ -n "$FIRECRAWL_KEY" ]]; then
    gen_args+=("--firecrawl-key" "$FIRECRAWL_KEY")
  fi

  if bash "$gen_script" "${gen_args[@]}"; then
    log_pass "Consumer config generated successfully"
  else
    log_warn "generate-consumer-config.sh exited with non-zero status"
  fi
}

# ── Step 8: Install Git Hooks ──────────────────────────────────────────────────
install_git_hooks() {
  log_step "8" "Installing git hooks"
  local hooks_script="${PROJECT_DIR}/${SUBMODULE_PATH}/scripts/install-hooks.sh"

  # Fall back to ENGINE_DIR if submodule path doesn't exist (local engine dev)
  if [[ ! -f "$hooks_script" && -f "${ENGINE_DIR}/scripts/install-hooks.sh" ]]; then
    hooks_script="${ENGINE_DIR}/scripts/install-hooks.sh"
  fi

  if [[ "$INSTALL_HOOKS" != true ]]; then
    log_info "Skipping hook installation (--hooks flag disabled)"
    return 0
  fi

  if [[ ! -f "$hooks_script" ]]; then
    log_warn "install-hooks.sh not found at ${hooks_script} — skipping"
    return 0
  fi

  log_info "Running: ${SUBMODULE_PATH}/scripts/install-hooks.sh"
  if bash "$hooks_script"; then
    log_pass "Git hooks installed successfully"
  else
    log_warn "Hook installation reported issues — check output above"
  fi
}

# ── Step 9: Validate Installation ──────────────────────────────────────────────
validate_installation() {
  log_step "9" "Validating installation"
  local validate_script="${PROJECT_DIR}/${SUBMODULE_PATH}/scripts/validate-toolkit.sh"

  # Fall back to ENGINE_DIR if submodule path doesn't exist (local engine dev)
  if [[ ! -f "$validate_script" && -f "${ENGINE_DIR}/scripts/validate-toolkit.sh" ]]; then
    validate_script="${ENGINE_DIR}/scripts/validate-toolkit.sh"
  fi

  if [[ ! -f "$validate_script" ]]; then
    log_warn "validate-toolkit.sh not found — skipping validation"
    return 0
  fi

  log_info "Running: ${SUBMODULE_PATH}/scripts/validate-toolkit.sh"
  if bash "$validate_script"; then
    log_pass "Installation validated successfully"
  else
    log_warn "Validation reported issues — review output above"
  fi
}

# ── Print Summary ──────────────────────────────────────────────────────────────
print_summary() {
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"

  echo ""
  echo "=========================================="
  echo -e "  ${CYAN}Installation Summary${NC}"
  echo "=========================================="
  echo ""
  echo -e "  Steps:    ${GREEN}${PASS_STEPS} passed${NC}, ${YELLOW}${WARN_STEPS} warnings${NC}, ${RED}${FAIL_STEPS} failed${NC}"
  echo -e "  Branch:   ${current_branch}"
  echo -e "  Engine:   ${SUBMODULE_PATH}/ (${SUBMODULE_URL})"
  echo ""
  echo "  Green check: ${GREEN}[PASS]${NC}  Yellow: ${YELLOW}[WARN]${NC}  Red: ${RED}[FAIL]${NC}"
  echo ""

  if [[ "$PASS_STEPS" -eq 0 && "$FAIL_STEPS" -gt 0 ]]; then
    echo -e "${RED}Installation failed.${NC} Review errors above and re-run."
    return 2
  fi

  if [[ "$FAIL_STEPS" -gt 0 ]]; then
    echo -e "${YELLOW}Installation completed with errors.${NC}"
    echo "  - ${FAIL_STEPS} step(s) failed — review above"
    echo "  - Some features may not be available"
  elif [[ "$WARN_STEPS" -gt 0 ]]; then
    echo -e "${YELLOW}Installation completed with warnings.${NC}"
  else
    echo -e "${GREEN}Installation completed successfully.${NC}"
  fi

  echo ""
  echo "${CYAN}Files to commit:${NC}"
  echo "  git add .opencode/ session/ .gitmodules ${SUBMODULE_PATH}"
  echo "  git add .gitignore                         # if modified"
  echo "  git commit -m \"Add workflow-state-engine toolkit\""
  echo ""
  echo "${CYAN}Next steps:${NC}"
  echo "  1. Review session/main/contract.json and adjust as needed"
  echo "  2. Review .opencode/ symlinks: ls -la .opencode/"
  echo "  3. Run validation:               bash ${SUBMODULE_PATH}/scripts/validate-toolkit.sh"
  echo "  4. Start an orchestration session"
  echo ""

  if [[ "$FAIL_STEPS" -gt 0 ]]; then
    return 2
  elif [[ "$WARN_STEPS" -gt 0 ]]; then
    return 1
  fi
  return 0
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"

  echo ""
  echo -e "${CYAN}=== Install Workflow State Engine ===${NC}"
  echo -e "  Consumer root: ${PROJECT_DIR}"
  echo -e "  Submodule:     ${SUBMODULE_PATH}/"
  echo -e "  Model:         ${AI_MODEL}"
  echo -e "  Type:          ${SERVICE_TYPE}"
  echo ""

  check_prerequisites || true
  manage_branch       || true
  setup_submodule     || true
  fix_gitignore       || true
  create_opencode_symlinks || true
  create_session_scaffolding || true
  generate_consumer_config  || true
  install_git_hooks         || true
  validate_installation     || true

  print_summary
  exit "$?"
}

main "$@"
