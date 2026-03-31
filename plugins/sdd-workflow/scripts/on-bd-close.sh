#!/bin/bash
# PostToolUse hook — fires after every Bash call; exits immediately unless it was a bd close.
# Receives tool event JSON on stdin.
INPUT=$(cat)
echo "$INPUT" | grep -q '"bd close' || exit 0
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/sync-openspec-tasks.py"
