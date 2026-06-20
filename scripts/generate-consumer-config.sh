#!/usr/bin/env bash
# shellcheck disable=SC2086
# generate-consumer-config.sh — Generate populated opencode.json from template
# Reads opencode.json.template, replaces all YOUR_* placeholders with user
# values, injects a type-specific instructions block, and outputs valid JSON.
#
# Usage:
#   ./scripts/generate-consumer-config.sh --type core
#   ./scripts/generate-consumer-config.sh --type ui --name "My Dashboard" --output ./dist/opencode.json
#   ./scripts/generate-consumer-config.sh --type support --model gpt-4o --firecrawl-key sk-xxx
#   ./scripts/generate-consumer-config.sh --help
#
# Exit codes:
#   0 — Success
#   1 — Usage / validation error
#   2 — Template not found
#   3 — JSON validation failed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ─── Defaults ──────────────────────────────────────────────────────────
MODEL="sumopod/deepseek-v4-flash"
FALLBACK="sumopod/deepseek-v4-flash"
TYPE=""
FIRECRAWL_KEY="YOUR_FIRECRAWL_API_KEY"
LEAN_CTX_PATH="/opt/homebrew/bin/lean-ctx"
LEAN_CTX_DIR='$HOME/.lean-ctx'
OUTPUT_FILE="./opencode.json"
SERVICE_NAME=""
HELP=false

# ─── Color output ──────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
fi

# ─── Helper functions ──────────────────────────────────────────────────
log_pass() { echo -e "  ${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
log_info() { echo -e "  ${YELLOW}[INFO]${NC} $1"; }
log_section() { echo -e "\n${BOLD}$1${NC}"; echo "  $(printf '%*s' "$((${#1}+2))" '' | tr ' ' '─')"; }

usage() {
    cat <<'USAGE'
Usage: bash scripts/generate-consumer-config.sh [OPTIONS]

Generates a populated opencode.json from the workflow-engine template.

Options:
  --model <MODEL>         AI model ID (default: sumopod/deepseek-v4-flash)
  --fallback <MODEL>      Fallback model (default: sumopod/deepseek-v4-flash)
  --type <TYPE>           Service type: core|ui|support|infra (required)
  --firecrawl-key <KEY>   Firecrawl API key (default: YOUR_FIRECRAWL_API_KEY)
  --lean-ctx-path <PATH>  Path to lean-ctx binary (default: /opt/homebrew/bin/lean-ctx)
  --output <FILE>         Output file (default: ./opencode.json)
  --name <NAME>           Service display name for the instructions block
  --help                  Show this help

Types:
  core      Spring Boot 3 / Java 21 / PostgreSQL / Hexagonal (services, APIs)
  ui        React/TypeScript, REST APIs, read-only views (dashboards)
  support   Python/Node scripts, scheduled tasks, config (automation helpers)
  infra     Docker, shell, Terraform, CI/CD (deployment pipelines)
USAGE
}

# ─── Generate instructions block based on type ─────────────────────────
# (Handled inline below via DESCRIPTION variable)

# ─── Parse arguments ───────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)
            MODEL="$2"; shift 2 ;;
        --fallback)
            FALLBACK="$2"; shift 2 ;;
        --type)
            TYPE="$2"; shift 2
            case "$TYPE" in
                core|ui|support|infra) ;;
                *)
                    echo -e "${RED}Error:${NC} --type must be core, ui, support, or infra (got: ${TYPE})" >&2
                    echo "Try '$(basename "$0") --help' for more info." >&2
                    exit 1
                    ;;
            esac
            ;;
        --firecrawl-key)
            FIRECRAWL_KEY="$2"; shift 2 ;;
        --lean-ctx-path)
            LEAN_CTX_PATH="$2"; shift 2 ;;
        --output)
            OUTPUT_FILE="$2"; shift 2 ;;
        --name)
            SERVICE_NAME="$2"; shift 2 ;;
        --help)
            HELP=true; shift ;;
        *)
            echo -e "${RED}Unknown option:${NC} $1" >&2
            echo "Try '$(basename "$0") --help' for more info." >&2
            exit 1
            ;;
    esac
done

if [[ "$HELP" == true ]]; then
    usage
    exit 0
fi

# ─── Validate arguments ────────────────────────────────────────────────
if [[ -z "$TYPE" ]]; then
    log_fail "--type is required. Choose: core, ui, support, or infra"
    echo "Try '$(basename "$0") --help' for more info." >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    log_fail "jq is required but not installed. Install with: brew install jq"
    exit 1
fi

# ─── Resolve template location ─────────────────────────────────────────
TEMPLATE=""
for candidate in "$PROJECT_DIR/.workflow-engine/opencode.json.template" "$PROJECT_DIR/opencode.json.template"; do
    if [[ -f "$candidate" ]]; then
        TEMPLATE="$candidate"
        break
    fi
done

if [[ -z "$TEMPLATE" ]]; then
    log_fail "Template not found. Checked:"
    log_info "  .workflow-engine/opencode.json.template"
    log_info "  opencode.json.template"
    echo "Run this script from the project root or the engine repo root." >&2
    exit 2
fi

log_section "generate-consumer-config.sh — Config Generator"
echo -e "  Type:         ${CYAN}${TYPE}${NC}"
echo -e "  Model:        ${CYAN}${MODEL}${NC}"
echo -e "  Fallback:     ${CYAN}${FALLBACK}${NC}"
echo -e "  Output:       ${CYAN}${OUTPUT_FILE}${NC}"
echo -e "  Template:     ${CYAN}${TEMPLATE}${NC}"
[[ -n "$SERVICE_NAME" ]] && echo -e "  Name:         ${CYAN}${SERVICE_NAME}${NC}"

# ─── Build description text ────────────────────────────────────────────
case "$TYPE" in
    core)
        DESCRIPTION="This is the ${SERVICE_NAME:-service}. Domain: price, product, store, receipt, price-calc. Tech: Spring Boot 3, Java 21, PostgreSQL, Flyway. Architecture: hexagonal (application/ + infrastructure/). Build: Maven."
        ;;
    ui)
        DESCRIPTION="This is the ${SERVICE_NAME:-dashboard}. Domain: grant management, user settings, visualization. Tech: React/TypeScript, charts. APIs: REST. No persistence — read-only views."
        ;;
    support)
        DESCRIPTION="This is the ${SERVICE_NAME:-automation}. Domain: scheduled tasks, LLM prompts, config. Tech: Python/Node scripts. No persistence. Lightweight."
        ;;
    infra)
        DESCRIPTION="This is the ${SERVICE_NAME:-deployer}. Domain: CI/CD, deployment pipelines, infrastructure. Tech: Docker, shell scripts, Terraform. High-trust operations."
        ;;
esac

# ─── Backup existing output ────────────────────────────────────────────
if [[ -f "$OUTPUT_FILE" ]]; then
    BACKUP_FILE="${OUTPUT_FILE}.backup"
    log_info "Backing up existing ${OUTPUT_FILE} → ${BACKUP_FILE}"
    cp "$OUTPUT_FILE" "$BACKUP_FILE" || {
        log_fail "Failed to create backup"
        exit 1
    }
fi

# ─── Generate config ───────────────────────────────────────────────────
# Step 1: Read template into temp file
TMP_FILE=$(mktemp)
TMP_OUT=$(mktemp)
cp "$TEMPLATE" "$TMP_FILE"

# Step 2: Replace all placeholders with sed
# Use | delimiter to avoid conflicts with / in model IDs (sumopod/deepseek-v4-flash)
#   YOUR_MODEL_ID (13 occurrences: top model + small_model + 11 agents)
sed -i '' "s|YOUR_MODEL_ID|${MODEL}|g" "$TMP_FILE"
#   YOUR_FALLBACK_MODEL (11 occurrences: 11 agents)
sed -i '' "s|YOUR_FALLBACK_MODEL|${FALLBACK}|g" "$TMP_FILE"
#   YOUR_FIRECRAWL_API_KEY (1 occurrence)
sed -i '' "s|YOUR_FIRECRAWL_API_KEY|${FIRECRAWL_KEY}|g" "$TMP_FILE"
#   LEAN_CTX_DATA_DIR (1 occurrence)
sed -i '' "s|LEAN_CTX_DATA_DIR|${LEAN_CTX_DIR}|g" "$TMP_FILE"
#   /path/to/lean-ctx (1 occurrence)
sed -i '' "s|/path/to/lean-ctx|${LEAN_CTX_PATH}|g" "$TMP_FILE"

# Step 3: Inject instructions block (index [2])
jq --arg desc "$DESCRIPTION" \
   '.instructions += [$desc]' \
   "$TMP_FILE" > "$TMP_OUT" && mv "$TMP_OUT" "$TMP_FILE"

# Step 4: Validate JSON
if python3 -m json.tool "$TMP_FILE" > /dev/null 2>&1; then
    log_pass "JSON validation passed"
else
    log_fail "Generated JSON is invalid"
    python3 -m json.tool "$TMP_FILE" 2>&1 | head -5
    rm -f "$TMP_FILE" "$TMP_OUT"
    exit 3
fi

# Step 5: Verify no remaining placeholders (unless intentional)
TEMPLATE_COUNT=$(grep -c 'YOUR_' "$TEMPLATE" 2>/dev/null || true)
REMAINING=$(grep -c 'YOUR_' "$TMP_FILE" 2>/dev/null || true)
if [[ "$REMAINING" -gt 0 ]]; then
    log_info "Warning: ${REMAINING} YOUR_ placeholder(s) remain in output (from ${TEMPLATE_COUNT} in template)"
    grep -n 'YOUR_' "$TMP_FILE" | head -10
fi

# Step 6: Write output
cp "$TMP_FILE" "$OUTPUT_FILE"
log_pass "Generated: ${OUTPUT_FILE}"

# ─── Cleanup ───────────────────────────────────────────────────────────
rm -f "$TMP_FILE" "$TMP_OUT"

log_section "Summary"
echo -e "  Output:     ${CYAN}${OUTPUT_FILE}${NC}"
echo -e "  Template:   ${CYAN}${TEMPLATE}${NC}"
echo -e "  Model:      ${CYAN}${MODEL}${NC}"
echo -e "  Fallback:   ${CYAN}${FALLBACK}${NC}"
echo -e "  Type:       ${CYAN}${TYPE}${NC}"
if [[ "$REMAINING" -gt 0 ]]; then
    echo -e "  Placeholders: ${RED}${REMAINING} remaining (${TEMPLATE_COUNT} in template)${NC}"
else
    echo -e "  Placeholders: ${GREEN}all ${TEMPLATE_COUNT} replaced${NC}"
fi
[[ -f "$BACKUP_FILE" ]] && echo -e "  Backup:     ${CYAN}${BACKUP_FILE}${NC}"
exit 0
