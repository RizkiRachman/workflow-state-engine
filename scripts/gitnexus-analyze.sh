#!/usr/bin/env bash
# scripts/gitnexus-analyze.sh — Re-index the GitNexus code intelligence database
# Called by post-flight protocol (agent.md §5) and session startup (agent.md §0.5)
# Usage: bash scripts/gitnexus-analyze.sh
# Depends on: gitnexus (npm global or npx)
set -euo pipefail

echo "  Re-indexing GitNexus..."
cd "$(git rev-parse --show-toplevel)"

if command -v gitnexus &>/dev/null; then
    GITNEXUS="gitnexus"
elif npx -y gitnexus --help &>/dev/null 2>&1; then
    GITNEXUS="npx -y gitnexus"
else
    echo "    ⚠️  gitnexus not found — install: npm install -g gitnexus"
    exit 1
fi

$GITNEXUS analyze "$(pwd)" 2>&1 | tail -5
echo "    ✅ GitNexus index refreshed"
