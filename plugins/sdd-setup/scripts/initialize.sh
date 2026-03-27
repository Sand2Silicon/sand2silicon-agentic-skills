#!/usr/bin/env bash
# initialize.sh — Runs on the DOCKER HOST before the container builds.
# Called via devcontainer.json "initializeCommand".
#
# Purpose:
#   1. Create per-project Claude Code config directories on the host
#   2. Pre-seed claude.json (onboarding, permissions) so bind mounts work
#   3. Ensure bind-mount source paths exist (Docker fails on missing sources)
#
# Usage:
#   ./initialize.sh <project-name> [options]
#
# Options:
#   --permissions-mode <mode>   Claude Code initial permission mode (default: bypassPermissions)
#                               Values: default, plan, acceptEdits, dontAsk, bypassPermissions
#   --no-onboarding             Skip marking onboarding as complete
#   --claude-home <path>        Override Claude config base dir (default: ~/.claude-<project>)
#
set -e

# --- Argument parsing ---
PROJECT_NAME="${1:?Usage: initialize.sh <project-name> [options]}"
shift

PERMISSIONS_MODE="bypassPermissions"
SKIP_ONBOARDING=false
CLAUDE_HOME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --permissions-mode) PERMISSIONS_MODE="$2"; shift 2 ;;
    --no-onboarding)    SKIP_ONBOARDING=true; shift ;;
    --claude-home)      CLAUDE_HOME="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude-${PROJECT_NAME}}"

# --- Helper: add a JSON property to a file (idempotent) ---
# Adds a key-value pair to a JSON file without overwriting existing properties.
# Values are auto-quoted unless they look like JSON literals (true/false/null/number).
add_json_property() {
    local file_path="$1"
    local prop_name="$2"
    local prop_value="$3"

    # Wrap value in quotes if it is not already a JSON literal
    if [[ ! "$prop_value" =~ ^(true|false|null|-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?|\".*\")$ ]]; then
        prop_value="\"$prop_value\""
    fi

    # Skip if property already exists
    if grep -qs "\"$prop_name\"" "$file_path"; then
        return
    fi

    # If file is empty or just contains '{}', overwrite it
    if ! [ -s "$file_path" ] || grep -Eq '^[[:space:]]*\{[[:space:]]*\}[[:space:]]*$' "$file_path"; then
        printf '{\n  "%s": %s\n}\n' "$prop_name" "$prop_value" > "$file_path"
    else
        # Insert property before the closing brace (requires GNU sed)
        sed -zE 's/\}[[:space:]]*$/,\n  "'"$prop_name"'": '"$prop_value"'\n}/' "$file_path" > "$file_path.tmp"
        mv "$file_path.tmp" "$file_path"
    fi
}

# --- Main ---
echo "=== Claude Code devcontainer initialization ==="
echo "Project:     $PROJECT_NAME"
echo "Claude home: $CLAUDE_HOME"
echo "Permissions: $PERMISSIONS_MODE"
echo ""

# 1. Create Claude config directory (maps to ~/.claude inside container)
echo "[1/3] Creating Claude config directories..."
mkdir -p "$CLAUDE_HOME/data"
echo "  Created: $CLAUDE_HOME/data/"

# 2. Create claude.json (maps to ~/.claude.json inside container)
#    This file must pre-exist with valid JSON for Docker's single-file bind mount to work.
echo "[2/3] Pre-seeding claude.json..."
CLAUDE_JSON="$CLAUDE_HOME/claude.json"
if [ ! -f "$CLAUDE_JSON" ]; then
    echo "{}" > "$CLAUDE_JSON"
    echo "  Created: $CLAUDE_JSON"
else
    echo "  Exists:  $CLAUDE_JSON"
fi

# Set initial permission mode in claude.json
add_json_property "$CLAUDE_JSON" "initialPermissionMode" "$PERMISSIONS_MODE"
echo "  Set initialPermissionMode=$PERMISSIONS_MODE"

# Mark onboarding complete (skips the interactive wizard)
if [[ "$SKIP_ONBOARDING" == "false" ]]; then
    add_json_property "$CLAUDE_JSON" "hasCompletedOnboarding" "true"
    echo "  Set hasCompletedOnboarding=true"
fi

# 3. Ensure the data directory has a placeholder so bind mount works
echo "[3/3] Ensuring bind-mount targets exist..."
touch "$CLAUDE_HOME/data/.keep" 2>/dev/null || true
echo "  Done."

echo ""
echo "=== Initialization complete ==="
echo "These paths will be bind-mounted into the container."
echo "Rebuild or reopen the container to apply."
