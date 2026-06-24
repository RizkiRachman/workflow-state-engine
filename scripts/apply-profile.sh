#!/bin/bash
# ============================================================================
# apply-profile.sh — Spring-like profile switcher for opencode.json
#
# Usage:
#   scripts/apply-profile.sh              # show current profile
#   scripts/apply-profile.sh <profile>    # switch to profile
#   scripts/apply-profile.sh --list       # list available profiles
#   scripts/apply-profile.sh --show       # show current profile JSON
#   scripts/apply-profile.sh --help       # this help
#
# Profiles are defined in opencode.profiles.json.
# Generates opencode.json by merging the selected profile into the template.
# ============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILES_FILE="$ROOT/opencode.profiles.json"
TEMPLATE_FILE="$ROOT/opencode.json.template"
OUTPUT_FILE="$ROOT/opencode.json"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
red()   { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
blue()  { printf "\033[34m%s\033[0m\n" "$*"; }

usage() {
  sed -n '3,12p' "$0" | sed 's/^# \?//'
  exit 0
}

fail() { red "Error: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# ensure dependencies
# ---------------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || fail "jq is required but not installed (brew install jq)"
[ -f "$PROFILES_FILE" ] || fail "Profiles file not found: $PROFILES_FILE"
[ -f "$TEMPLATE_FILE" ] || fail "Template file not found: $TEMPLATE_FILE"

# ---------------------------------------------------------------------------
# argument parsing
# ---------------------------------------------------------------------------
CURRENT_PROFILE="$(jq -r '.current // "sumopod"' "$PROFILES_FILE")"

case "${1:-}" in
  --help|-h) usage ;;
  --list|-l)
    echo "Available profiles:"
    jq -r '.profiles | to_entries[] | "  \(.key)  — \(.value.description)"' "$PROFILES_FILE"
    echo ""
    echo "Current: $(green "$CURRENT_PROFILE")"
    exit 0
    ;;
  --show|-s)
    jq --arg p "$CURRENT_PROFILE" '.profiles[$p]' "$PROFILES_FILE"
    exit 0
    ;;
  "")
    echo "Current profile: $(green "$CURRENT_PROFILE")"
    echo "Use: $(blue "$0 <profile>") to switch, $(blue "$0 --list") to see all"
    exit 0
    ;;
  *)
    PROFILE="${1}"
    ;;
esac

# ---------------------------------------------------------------------------
# validate profile
# ---------------------------------------------------------------------------
PROFILE_DATA="$(jq --arg p "$PROFILE" '.profiles[$p] // empty' "$PROFILES_FILE")"
[ -n "$PROFILE_DATA" ] || fail "Unknown profile '$PROFILE'. Run with --list to see available profiles."

echo "Applying profile: $(green "$PROFILE")"

# ---------------------------------------------------------------------------
# extract profile values
# ---------------------------------------------------------------------------
MODEL="$(echo "$PROFILE_DATA" | jq -r '.model')"
SMALL_MODEL="$(echo "$PROFILE_DATA" | jq -r '.small_model // .model')"
FALLBACK="$(echo "$PROFILE_DATA" | jq -r '.fallback // .model')"
WEBCSRCH_MODEL="$(echo "$PROFILE_DATA" | jq -r '.websearch_cited_model // "deepseek-v4-flash"')"
PROVIDER_NAME="$(echo "$PROFILE_DATA" | jq -r '.providers | keys[0]')"

echo "  Model:        $(blue "$MODEL")"
echo "  Small model:  $(blue "$SMALL_MODEL")"
echo "  Fallback:     $(blue "$FALLBACK")"
echo "  Provider:     $(blue "$PROVIDER_NAME")"

# ---------------------------------------------------------------------------
# generate opencode.json
# ---------------------------------------------------------------------------

# Step 1: Read template and replace model placeholders
TMP1=$(mktemp)
trap 'rm -f "$TMP1"' EXIT

# Replace global model/small_model
jq \
  --arg model "$MODEL" \
  --arg small "$SMALL_MODEL" \
  '.model = $model | .small_model = $small' \
  "$TEMPLATE_FILE" > "$TMP1"

# Replace all agent model and fallback_models references
# If profile has per-agent overrides, deep-merge them into each agent
AGENT_OVERRIDES_JSON="$(echo "$PROFILE_DATA" | jq '.agent_overrides // {}')"

jq \
  --arg model "$MODEL" \
  --arg fallback "$FALLBACK" \
  --argjson overrides "$AGENT_OVERRIDES_JSON" \
  '
  .agent |= with_entries(
    .value.model = ($overrides[.key].model // $model)
    | .value.fallback_models = ($overrides[.key].fallback_models // [$fallback])
    | if $overrides[.key] then
        # deep-merge remaining override fields (temperature, steps, etc.)
        .value *= ($overrides[.key] | del(.model, .fallback_models))
      else . end
  )
  ' \
  "$TMP1" > "${TMP1}.2" && mv "${TMP1}.2" "$TMP1"

# Replace websearch_cited model in sumopod provider if it exists
# (we rebuild providers from profile anyway, so just inject the profile's provider section)
PROVIDER_SECTION="$(echo "$PROFILE_DATA" | jq '.providers')"

# Step 2: Inject provider section
# If the output already has a provider key, replace it; otherwise add it
HAS_PROVIDER=$(jq 'has("provider")' "$TMP1")
if [ "$HAS_PROVIDER" = "true" ]; then
  jq --argjson providers "$PROVIDER_SECTION" '.provider = $providers' "$TMP1" > "${TMP1}.2" && mv "${TMP1}.2" "$TMP1"
else
  jq --argjson providers "$PROVIDER_SECTION" '.provider = $providers' "$TMP1" > "${TMP1}.2" && mv "${TMP1}.2" "$TMP1"
fi

# Step 3: Handle websearch_cited model in the first provider's options
# Find the provider with websearch_cited option and set the model
FIRST_PROVIDER="$(echo "$PROVIDER_SECTION" | jq -r 'keys[0]')"
HAS_WEBCSRCH=$(echo "$PROVIDER_SECTION" | jq --arg p "$FIRST_PROVIDER" '.[$p].options.websearch_cited // empty')
if [ -n "$HAS_WEBCSRCH" ]; then
  jq \
    --arg p "$FIRST_PROVIDER" \
    --arg wsm "$WEBCSRCH_MODEL" \
    '.provider[$p].options.websearch_cited.model = $wsm' \
    "$TMP1" > "${TMP1}.2" && mv "${TMP1}.2" "$TMP1"
fi

# ---------------------------------------------------------------------------
# finalize
# ---------------------------------------------------------------------------
cp "$TMP1" "$OUTPUT_FILE"

# Update current profile in profiles file
jq --arg p "$PROFILE" '.current = $p' "$PROFILES_FILE" > "${TMP1}" && mv "${TMP1}" "$PROFILES_FILE"

echo ""
green "✓ opencode.json generated with profile '$PROFILE'"
echo "  $(blue "$OUTPUT_FILE")"
echo ""
echo "Next steps:"
echo "  - Validate: $(blue "jq . $OUTPUT_FILE | head -5")"
echo "  - Switch again: $(blue "$0 <profile>")"
