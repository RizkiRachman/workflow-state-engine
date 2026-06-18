#!/usr/bin/env bash
# sync-agent-states.sh — Auto-generate agent_states from agents/*.md files
# Usage: bash scripts/sync-agent-states.sh [--rules rules.json] [--output output_file]
# Example: bash scripts/sync-agent-states.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RULES_FILE="${1:-$PROJECT_DIR/rules/rules.json}"
OUTPUT_FILE="${2:-$RULES_FILE}"

AGENTS_DIR="$PROJECT_DIR/agents"

# Check if agents directory exists
if [[ ! -d "$AGENTS_DIR" ]]; then
    echo "❌ Error: agents/ directory not found at $AGENTS_DIR" >&2
    exit 1
fi

# Check if rules file exists
if [[ ! -f "$RULES_FILE" ]]; then
    echo "❌ Error: rules file not found at $RULES_FILE" >&2
    exit 1
fi

# Find all agent files (excluding _governance.md)
agent_files=()
for file in "$AGENTS_DIR"/*.md; do
    if [[ -f "$file" ]]; then
        basename=$(basename "$file" .md)
        if [[ "$basename" != "_governance" ]]; then
            agent_files+=("$basename")
        fi
    fi
done

if [[ ${#agent_files[@]} -eq 0 ]]; then
    echo "❌ Error: No agent files found in $AGENTS_DIR" >&2
    exit 1
fi

echo "Found ${#agent_files[@]} agent files: ${agent_files[*]}"

# Generate agent_states JSON
agent_states_json=$(jq -n \
    --argjson agents "$(printf '%s\n' "${agent_files[@]}" | jq -R . | jq -s .)" \
    '{
        "tech-lead": ["*"],
        "system-analyst": ["INIT", "PLAN", "PLAN_SCORED"],
        "developer": ["EXECUTE", "EXECUTE_SCORED"],
        "quality-analyst": ["REVIEW", "REVIEW_SCORED"],
        "software-architect": ["INIT", "PLAN", "PLAN_SCORED"],
        "developer-explorer": ["*"],
        "developer-fixer": ["*"],
        "developer-librarian": ["*"],
        "developer-council": ["*"],
        "developer-observer": ["*"],
        "quality-analyst-learner": ["REVIEW_SCORED", "COMPLETE"],
        "available_agents": $agents
    }')

# Backup original rules file
if [[ -f "$RULES_FILE" ]]; then
    cp "$RULES_FILE" "${RULES_FILE}.backup"
    echo "✅ Backed up original rules file to ${RULES_FILE}.backup"
fi

# Write new agent_states to rules file
echo "$agent_states_json" | jq '.agent_states' > "$OUTPUT_FILE" 2>/dev/null && \
    echo "✅ Agent states updated in $OUTPUT_FILE" || \
    echo "❌ Failed to update agent states" >&2

# Verify the update
if [[ -f "$OUTPUT_FILE" ]]; then
    echo ""
    echo "Agent states in $OUTPUT_FILE:"
    jq '.agent_states | to_entries[] | "\(.key): \(.value | join(", "))"' "$OUTPUT_FILE"
fi