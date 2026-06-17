#!/usr/bin/env bash
# scripts/check-mcp.sh — Verify MCP tools are installed
# Called by setup.sh via: source scripts/check-mcp.sh
# Exits with code 1 if any MANDATORY tool is missing.

FAILED_MCP=0

echo "  Checking MCP tools..."

# lean-ctx — MANDATORY
if command -v lean-ctx &>/dev/null; then
  echo "    ✅ lean-ctx — found"
else
  echo "    ❌ lean-ctx — NOT FOUND (MANDATORY)"
  echo "       Install: https://github.com/MorphLlama/lean-ctx"
  echo "       Or via Homebrew: brew install lean-ctx"
  FAILED_MCP=1
fi

# gitnexus — MANDATORY
if command -v gitnexus &>/dev/null; then
  echo "    ✅ gitnexus — found"
elif npm list -g gitnexus &>/dev/null 2>&1; then
  echo "    ✅ gitnexus — found (npm global)"
else
  echo "    ❌ gitnexus — NOT FOUND (MANDATORY)"
  echo "       Install: npm install -g gitnexus"
  FAILED_MCP=1
fi

# firecrawl — RECOMMENDED
if command -v firecrawl-mcp &>/dev/null; then
  echo "    ✅ firecrawl-mcp — found"
elif [ -n "$FIRECRAWL_API_KEY" ]; then
  echo "    ✅ FIRECRAWL_API_KEY — set in environment"
elif [ -f .env ] && grep -q FIRECRAWL_API_KEY .env 2>/dev/null; then
  echo "    ✅ FIRECRAWL_API_KEY — found in .env"
else
  echo "    ⚠️  firecrawl-mcp — not found (RECOMMENDED for web search)"
  echo "       Install: npm install -g firecrawl-mcp"
  echo "       API key: https://firecrawl.dev"
fi

# context7 — OPTIONAL
if command -v context7 &>/dev/null || npm list -g @upstash/context7-mcp &>/dev/null 2>&1; then
  echo "    ✅ context7-mcp — found"
else
  echo "    ℹ️  context7-mcp — not found (OPTIONAL — docs lookup only)"
  echo "       Install: npm install -g @upstash/context7-mcp"
fi

if [ "$FAILED_MCP" -eq 1 ]; then
  echo ""
  echo "    ⛔ Some MANDATORY MCP tools are missing."
  echo "       Install them and re-run setup.sh."
fi

# Return FAILED_MCP when sourced by setup.sh, exit when run standalone
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return "$FAILED_MCP"
else
  exit "$FAILED_MCP"
fi
