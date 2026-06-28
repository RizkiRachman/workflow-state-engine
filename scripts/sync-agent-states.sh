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

# Validate generated JSON is not null or empty
if [[ -z "$agent_states_json" || "$agent_states_json" == "null" ]]; then
    echo "❌ Error: Generated agent_states is null or empty — refusing to write" >&2
    exit 1
fi
if ! echo "$agent_states_json" | jq -e . >/dev/null 2>&1; then
    echo "❌ Error: Generated agent_states is invalid JSON — refusing to write" >&2
    exit 1
fi

# Backup original rules file with timestamp
if [[ -f "$RULES_FILE" ]]; then
    backup_file="${RULES_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    cp "$RULES_FILE" "$backup_file"
    echo "✅ Backed up rules file to $backup_file"
fi

# Atomically merge agent_states into rules.json (preserves all other keys)
tmp_file="${OUTPUT_FILE}.tmp.$$"
if ! jq --argjson new_states "$agent_states_json" '
    .agent_states = $new_states
' "$RULES_FILE" > "$tmp_file" 2>/dev/null; then
    echo "❌ Error: Failed to merge agent states into rules.json" >&2
    rm -f "$tmp_file"
    exit 1
fi

# Validate merged output is valid JSON with non-null agent_states
if ! jq -e '.agent_states' "$tmp_file" >/dev/null 2>&1; then
    echo "❌ Error: Merged rules.json has null agent_states — refusing to overwrite" >&2
    rm -f "$tmp_file"
    exit 1
fi
if ! jq -e . "$tmp_file" >/dev/null 2>&1; then
    echo "❌ Error: Merged output is invalid JSON — refusing to overwrite" >&2
    rm -f "$tmp_file"
    exit 1
fi

mv "$tmp_file" "$OUTPUT_FILE"
echo "✅ Agent states updated in $OUTPUT_FILE"

# Verify the update
if [[ -f "$OUTPUT_FILE" ]]; then
    echo ""
    echo "Agent states in $OUTPUT_FILE:"
    jq -r '.agent_states | to_entries[] | "  \(.key): [\(.value | join(", "))]"' "$OUTPUT_FILE"
fi
echo "✅ Agent state sync complete"