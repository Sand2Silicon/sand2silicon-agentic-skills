#!/bin/bash
# Bootstrap script for Claude Code devcontainer integration.
# Run this on the Docker host to set up project-specific Claude config,
# or let it run automatically via devcontainer.json initializeCommand.
#
# Usage:
#   ./scripts/setup-claude-code.sh              # uses default project name
#   ./scripts/setup-claude-code.sh myProject     # custom project name

set -e

PROJECT_NAME="${1:-cryptoPredictionModel}"
CLAUDE_CONFIG_DIR="${HOME}/.claude-${PROJECT_NAME}"
CLAUDE_DATA_DIR="${CLAUDE_CONFIG_DIR}/data"
CLAUDE_JSON="${CLAUDE_CONFIG_DIR}/claude.json"
CLAUDE_SETTINGS="${CLAUDE_DATA_DIR}/settings.json"

echo "Setting up Claude Code config for project: ${PROJECT_NAME}"
echo "Config directory: ${CLAUDE_CONFIG_DIR}"

# --- Helper: add a top-level JSON property to a file (idempotent) ---
add_json_property() {
    local file_path="$1"
    local prop_name="$2"
    local prop_value="$3"

    if grep -qs "\"$prop_name\"" "$file_path"; then
        echo "  [skip] \"$prop_name\" already set in $(basename "$file_path")"
        return
    fi

    if ! [ -s "$file_path" ] || grep -Eq '^[[:space:]]*\{[[:space:]]*\}[[:space:]]*$' "$file_path"; then
        printf '{\n  "%s": %s\n}\n' "$prop_name" "$prop_value" > "$file_path"
    else
        sed -zE 's/\}[[:space:]]*$/,\n  "'"$prop_name"'": '"$prop_value"'\n}/' "$file_path" > "$file_path.tmp"
        mv "$file_path.tmp" "$file_path"
    fi
    echo "  [set]  \"$prop_name\" in $(basename "$file_path")"
}

# --- Create project-specific config directories ---
mkdir -p "${CLAUDE_DATA_DIR}"
echo "Created: ${CLAUDE_DATA_DIR}/"

# --- Ensure claude.json exists (required for Docker single-file bind mount) ---
if [ ! -f "${CLAUDE_JSON}" ]; then
    echo '{}' > "${CLAUDE_JSON}"
    echo "Created: ${CLAUDE_JSON}"
else
    echo "Exists:  ${CLAUDE_JSON}"
fi

# Mark onboarding complete
add_json_property "${CLAUDE_JSON}" "hasCompletedOnboarding" "true"

# --- Create settings.json with permission bypass (container-only) ---
if [ ! -f "${CLAUDE_SETTINGS}" ]; then
    cat > "${CLAUDE_SETTINGS}" << 'SETTINGS_EOF'
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
SETTINGS_EOF
    echo "Created: ${CLAUDE_SETTINGS} (bypassPermissions for container)"
else
    echo "Exists:  ${CLAUDE_SETTINGS}"
fi

echo ""
echo "Done. Claude Code will use:"
echo "  ~/.claude  → ${CLAUDE_DATA_DIR}/"
echo "  ~/.claude.json → ${CLAUDE_JSON}"
echo ""
echo "First run in container will require authentication (stored in ${CLAUDE_DATA_DIR}/.credentials.json)."
