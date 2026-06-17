#!/usr/bin/env bash
# scripts/check-plugins.sh — Verify npm and custom plugins are installed
# Called by setup.sh via: source scripts/check-plugins.sh
# Informational only — no FAILED exit.

echo "  Checking npm plugins..."

NPM_PLUGINS=(
  "@morphllm/opencode-morph-plugin"
  "@razroo/opencode-model-fallback"
  "@tarquinen/opencode-dcp"
  "opencode-notify"
  "opencode-vibeguard"
  "opencode-websearch-cited"
  "opencode-worktree"
)

for plugin in "${NPM_PLUGINS[@]}"; do
  if npm list -g "$plugin" &>/dev/null 2>&1; then
    echo "    ✅ $plugin — installed globally"
  elif [ -d "node_modules/$plugin" ] 2>/dev/null; then
    echo "    ✅ $plugin — installed locally"
  elif [ -d "n_m/$plugin" ] 2>/dev/null; then
    echo "    ✅ $plugin — installed locally (n_m/)"
  else
    echo "    📦 $plugin — not installed (OPTIONAL)"
  fi
done

echo ""
echo "  Checking custom plugins..."

if [ -f ".opencode/plugins/auto-wrap.ts" ]; then
  echo "    ✅ auto-wrap.ts — found"
else
  echo "    ℹ️  auto-wrap.ts — not found (OPTIONAL — created on first run)"
fi

if [ -f ".opencode/plugins/ponytail.mjs" ]; then
  echo "    ✅ ponytail.mjs — found"
else
  echo "    ℹ️  ponytail.mjs — not found (OPTIONAL — download from repo)"
fi

echo ""
echo "  Plugin check complete."
