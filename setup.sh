#!/usr/bin/env bash
# toolkit/setup.sh — Regenerate all .opencode/ symlinks + root reference symlinks
# Run once on fresh clone: bash toolkit/setup.sh
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
  echo "  Create at toolkit/config/opencode-skillful.json if needed."
fi

if [ "$FAILED" -eq 1 ]; then
  echo "Pre-flight checks FAILED. Fix errors above and re-run."
  exit 1
fi
echo "Pre-flight checks passed."
# ── End pre-flight checks ──────────────────────────────────────

cd "$(git rev-parse --show-toplevel)"
echo "Creating .opencode/ -> toolkit/ symlinks..."

# Core symlinks (6)
ln -sfn ../toolkit/agents      .opencode/agents
ln -sfn ../toolkit/skills      .opencode/skills
ln -sfn ../toolkit/rules       .opencode/rules
ln -sfn ../toolkit/template    .opencode/orchestration
ln -sfn ../toolkit/doc/planning .opencode/planning
ln -sfn ../toolkit/doc/reports  .opencode/reports

# Usage & config symlinks (2)
ln -sfn ../toolkit/usage        .opencode/usage
ln -sfn ../toolkit/config       .opencode/config

# Root reference symlinks (3 — point to existing toolkit files)
ln -sfn toolkit/template/state.md STATE.md
ln -sfn toolkit/doc/project.md    PROJECT.md
ln -sfn toolkit/agent.md          AGENTS.md

# Custom tools symlink (1)
mkdir -p .opencode/tools
ln -sf ../../toolkit/tools/request-transform.ts .opencode/tools/request-transform.ts

# Custom plugins directory + symlink (registered in opencode.json plugin config)
mkdir -p toolkit/plugins
ln -sfn ../toolkit/plugins .opencode/plugins

# Plugin config symlinks (1)
ln -sfn toolkit/config/opencode-skillful.json .opencode-skillful.json

# ── Post-install validation ────────────────────────────────────
echo "Validating symlinks..."
VALIDATION_FAILED=0

# Expected symlinks: target -> source
declare -A SYMLINKS=(
  [".opencode/agents"]="../toolkit/agents"
  [".opencode/skills"]="../toolkit/skills"
  [".opencode/rules"]="../toolkit/rules"
  [".opencode/orchestration"]="../toolkit/template"
  [".opencode/planning"]="../toolkit/doc/planning"
  [".opencode/reports"]="../toolkit/doc/reports"
  [".opencode/usage"]="../toolkit/usage"
  [".opencode/config"]="../toolkit/config"
  ["STATE.md"]="toolkit/template/state.md"
  ["PROJECT.md"]="toolkit/doc/project.md"
  ["AGENTS.md"]="toolkit/agent.md"
  [".opencode/plugins"]="../toolkit/plugins"
  [".opencode-skillful.json"]="toolkit/config/opencode-skillful.json"
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
  echo "  .opencode/agents        -> ../toolkit/agents"
  echo "  .opencode/skills        -> ../toolkit/skills"
  echo "  .opencode/rules         -> ../toolkit/rules"
  echo "  .opencode/orchestration -> ../toolkit/template"
  echo "  STATE.md                -> toolkit/template/state.md"
  echo "  PROJECT.md              -> toolkit/doc/project.md"
  echo "  AGENTS.md               -> toolkit/agent.md"
  exit 1
fi

echo "All symlinks valid."
echo ""
echo "Setup complete. The toolkit is ready."
