#!/usr/bin/env bash
# setup.sh — Create .opencode/ symlinks for flat project structure
# Run once on fresh clone: bash setup.sh
set -euo pipefail

# ── Pre-flight checks ──────────────────────────────────────────
echo "Running pre-flight checks..."
FAILED=0

# Bash >= 4 (for associative arrays used by some scripts)
if (( BASH_VERSINFO[0] < 4 )); then
  echo "ERROR: bash >= 4 required (found $BASH_VERSION). Install bash 4+ and re-run."
  FAILED=1
fi

# Git must be available and we must be in a git repo
if ! command -v git &>/dev/null; then
  echo "ERROR: git not found. Install git and re-run."
  FAILED=1
elif ! git rev-parse --show-toplevel &>/dev/null; then
  echo "ERROR: Not inside a git repository. Run this script from the project root."
  FAILED=1
fi

# Node.js (required for OpenCode plugins and tooling)
if ! command -v node &>/dev/null; then
  echo "WARNING: node not found. OpenCode plugins may not work."
  echo "  Install from https://nodejs.org/ or via package manager."
fi

# lean-ctx (recommended for file management)
if ! command -v lean-ctx &>/dev/null; then
  echo "WARNING: lean-ctx not found. Some toolkit features will be unavailable."
  echo "  Install from: https://github.com/MorphLlama/lean-ctx"
fi

# opencode-skillful plugin config (optional, not a hard dependency)
if [ ! -f "$(dirname "$0")/config/opencode-skillful.json" ]; then
  echo "INFO: opencode-skillful.json not found — skill plugin not configured."
  echo "  Create at config/opencode-skillful.json if needed."
fi

if [ "$FAILED" -eq 1 ]; then
  echo "Pre-flight checks FAILED. Fix errors above and re-run."
  exit 1
fi
echo "Pre-flight checks passed."
# ── End pre-flight checks ──────────────────────────────────────

echo ""
echo "── Tool Verification ──────────────────────────────────────"
source "$(dirname "$0")/scripts/check-mcp.sh" || FAILED=1
echo ""
source "$(dirname "$0")/scripts/check-plugins.sh"
echo "────────────────────────────────────────────────────────────"

if [ "$FAILED" -eq 1 ]; then
  echo ""
  echo "=============================="
  echo "  MISSING MANDATORY TOOLS"
  echo "=============================="
  echo "  Install the missing tools listed above and re-run setup.sh."
  exit 1
fi

echo ""

cd "$(git rev-parse --show-toplevel)"
echo "Creating .opencode/ symlinks..."
mkdir -p .opencode

ln -sfn ../agents   .opencode/agents
ln -sfn ../skills   .opencode/skills
ln -sfn ../plugins  .opencode/plugins
ln -sfn ../rules    .opencode/rules
ln -sfn ../template .opencode/orchestration
ln -sfn ../doc/planning .opencode/planning
ln -sfn ../doc/reports  .opencode/reports
ln -sfn ../usage    .opencode/usage
ln -sfn ../config   .opencode/config
ln -sfn ../agent.md .opencode/AGENTS.md

# ── Post-install validation ────────────────────────────────────
echo "Validating symlinks..."
VALIDATION_FAILED=0

# Expected symlinks: target -> source
declare -A SYMLINKS=(
  [".opencode/agents"]="../agents"
  [".opencode/skills"]="../skills"
  [".opencode/plugins"]="../plugins"
  [".opencode/rules"]="../rules"
  [".opencode/orchestration"]="../template"
  [".opencode/planning"]="../doc/planning"
  [".opencode/reports"]="../doc/reports"
  [".opencode/usage"]="../usage"
  [".opencode/config"]="../config"
  [".opencode/AGENTS.md"]="../agent.md"
)

for target in "${!SYMLINKS[@]}"; do
  if [ ! -L "$target" ]; then
    echo "FAIL: $target is not a symlink"
    VALIDATION_FAILED=1
  elif [ "$(readlink "$target")" != "${SYMLINKS[$target]}" ]; then
    echo "FAIL: $target points to $(readlink "$target") (expected ${SYMLINKS[$target]})"
    VALIDATION_FAILED=1
  else
    echo "  OK: $target -> $(readlink "$target")"
  fi
done

# Also check .opencode/tools/request-transform.ts
if [ ! -L ".opencode/tools/request-transform.ts" ]; then
  echo "FAIL: .opencode/tools/request-transform.ts is not a symlink"
  VALIDATION_FAILED=1
fi

if [ "$VALIDATION_FAILED" -eq 1 ]; then
  echo ""
  echo "WARNING: Some symlinks are incorrect or missing. Re-run setup.sh or fix manually."
  echo "Expected layout:"
  echo "  .opencode/agents        -> ../agents"
  echo "  .opencode/skills        -> ../skills"
  echo "  .opencode/rules         -> ../rules"
  echo "  .opencode/orchestration -> ../template"
  echo "  .opencode/planning      -> ../doc/planning"
  echo "  .opencode/reports       -> ../doc/reports"
  echo "  STATE.md                -> contract/state.md"
  echo "  PROJECT.md              -> doc/project.md"
  echo "  AGENTS.md               -> ../agent.md"
  exit 1
fi

echo "All symlinks valid."
echo ""
echo "Setup complete. The toolkit is ready."
