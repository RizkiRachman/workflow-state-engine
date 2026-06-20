#!/usr/bin/env bash
set -euo pipefail

# validate-all.sh — validate workflow-state-engine toolkit across all 8 services
# Runs validate-toolkit.sh in each service that has .workflow-engine/
# Reports pass/fail/skip per service.

WORKSPACE="${WORKSPACE:-/Users/rizkirachman/IdeaProjects}"

SERVICES=(
  "goods-price-comparison-service"
  "goods-price-comparison-api"
  "goods-price-comparison-automation"
  "goods-price-comparison-agent-helper"
  "goods-price-comparison-dashboard"
  "goods-price-comparison-deployer"
  "goods-price-comparison-claude-service"
  "goods-price-comparison-properties"
)

PASS=0
FAIL=0
SKIP=0

echo "=== validate-all.sh — Multi-Service Toolkit Validation ==="
echo ""

for svc in "${SERVICES[@]}"; do
  dir="$WORKSPACE/$svc"
  if [ ! -d "$dir/.workflow-engine" ]; then
    echo "  SKIP: $svc — no .workflow-engine/"
    ((SKIP++))
    continue
  fi
  script="$dir/.workflow-engine/scripts/validate-toolkit.sh"
  if [ ! -f "$script" ]; then
    echo "  FAIL: $svc — validate-toolkit.sh missing"
    ((FAIL++))
    continue
  fi
  echo "=== $svc ==="
  if (cd "$dir" && bash "$script"); then
    ((PASS++))
  else
    ((FAIL++))
  fi
  echo ""
done

echo "---"
echo "Summary: $PASS pass, $FAIL fail, $SKIP skip"
echo "---"

[ "$FAIL" -eq 0 ]
