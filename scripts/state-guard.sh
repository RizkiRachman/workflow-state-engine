#!/usr/bin/env bash
set -euo pipefail

# ─── Config ────────────────────────────────────────────────────────────────
RULES_FILE="rules/rules.json"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# ─── Help ──────────────────────────────────────────────────────────────────
usage() {
  cat <<EOF
Usage: $(basename "$0") --agent NAME (--contract PATH | --state STATE) [--dry-run]

Agent state guard — verifies an agent is allowed in the current contract state.

Options:
  --agent NAME       Agent name (must match a key in rules.json agent_states)
  --contract PATH    Path to contract.json (mutually exclusive with --state)
  --state STATE      State string override (mutually exclusive with --contract)
  --dry-run          Show each step without exiting
  --help             Show this message

Examples:
  $(basename "$0") --agent system-analyst --contract contract.json
  $(basename "$0") --agent developer --state EXECUTE
  $(basename "$0") --agent tech-lead --contract contract.json
EOF
  exit 0
}

# ─── Parse flags ───────────────────────────────────────────────────────────
AGENT=""
CONTRACT=""
STATE=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --agent)
      AGENT="$2"
      shift 2
      ;;
    --contract)
      CONTRACT="$2"
      shift 2
      ;;
    --state)
      STATE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      usage
      ;;
    *)
      echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2
      usage
      ;;
  esac
done

# ─── Validate inputs ───────────────────────────────────────────────────────
if [[ -z "$AGENT" ]]; then
  echo -e "${RED}ERROR: --agent is required${NC}" >&2
  usage
fi

if [[ -n "$CONTRACT" && -n "$STATE" ]]; then
  echo -e "${RED}ERROR: --contract and --state are mutually exclusive${NC}" >&2
  exit 1
fi

if [[ -z "$CONTRACT" && -z "$STATE" ]]; then
  echo -e "${RED}ERROR: Either --contract or --state is required${NC}" >&2
  usage
fi

# ─── Check jq availability ────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo -e "${RED}ERROR: jq is required but not installed${NC}" >&2
  exit 1
fi

# ─── Check rules file ──────────────────────────────────────────────────────
if [[ ! -f "$RULES_FILE" ]]; then
  echo -e "${RED}ERROR: Rules file not found: $RULES_FILE${NC}" >&2
  exit 1
fi

if $DRY_RUN; then
  echo -e "${YELLOW}[DRY-RUN] Rules file found: $RULES_FILE${NC}"
fi

# ─── Resolve agent allowed states ──────────────────────────────────────────
ALLOWED=$(jq -r --arg agent "$AGENT" '
  .state_machine.agent_states[$agent] // empty | @json
' "$RULES_FILE")

if [[ -z "$ALLOWED" ]]; then
  echo -e "${RED}ERROR: Agent '$AGENT' not found in rules.json agent_states${NC}" >&2
  exit 1
fi

if $DRY_RUN; then
  echo -e "${YELLOW}[DRY-RUN] Agent '$AGENT' allowed states: $ALLOWED${NC}"
fi

# ─── Resolve current state ─────────────────────────────────────────────────
CURRENT_STATE=""

if [[ -n "$STATE" ]]; then
  CURRENT_STATE="$STATE"
  if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN] Using --state override: $CURRENT_STATE${NC}"
  fi
elif [[ -n "$CONTRACT" ]]; then
  if [[ ! -f "$CONTRACT" ]]; then
    echo -e "${RED}ERROR: Contract file not found: $CONTRACT${NC}" >&2
    exit 1
  fi
  CURRENT_STATE=$(jq -r '.state // empty' "$CONTRACT")
  if [[ -z "$CURRENT_STATE" ]]; then
    echo -e "${RED}ERROR: No .state field found in contract: $CONTRACT${NC}" >&2
    exit 1
  fi
  if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN] Read state from contract '$CONTRACT': $CURRENT_STATE${NC}"
  fi
fi

# ─── Evaluate ──────────────────────────────────────────────────────────────
if [[ "$ALLOWED" == '["*"]' ]]; then
  echo -e "${GREEN}PASS: Agent '$AGENT' allowed in state $CURRENT_STATE (wildcard)${NC}"
  exit 0
fi

ALLOWED_LIST=$(echo "$ALLOWED" | jq -r '.[]')
IS_ALLOWED=false

while IFS= read -r allowed_state; do
  if [[ "$allowed_state" == "$CURRENT_STATE" ]]; then
    IS_ALLOWED=true
    break
  fi
done <<< "$ALLOWED_LIST"

if $IS_ALLOWED; then
  echo -e "${GREEN}PASS: Agent '$AGENT' allowed in state $CURRENT_STATE${NC}"
  exit 0
else
  ALLOWED_CSV=$(echo "$ALLOWED_LIST" | paste -sd ", " -)
  echo -e "${RED}BLOCKED: Agent '$AGENT' not allowed in state $CURRENT_STATE. Allowed: $ALLOWED_CSV${NC}" >&2
  exit 1
fi
