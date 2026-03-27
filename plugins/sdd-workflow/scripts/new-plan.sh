#!/usr/bin/env bash
# new-plan.sh — Copy the spec planning template for a new change
#
# Usage: new-plan.sh <change-name> [output-dir]
#
# Copies the project-specific planning template (from .claude/sdd-workflow/)
# or the base template (from this plugin) to <output-dir>/<change-name>-plan.md.

set -euo pipefail

CHANGE_NAME="${1:?Usage: new-plan.sh <change-name> [output-dir]}"
OUTPUT_DIR="${2:-.}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_TEMPLATE="$SCRIPT_DIR/../templates/spec-planning-template.md"
PROJECT_TEMPLATE=".claude/sdd-workflow/spec-planning-template.md"

if [[ -f "$PROJECT_TEMPLATE" ]]; then
    SOURCE="$PROJECT_TEMPLATE"
    echo "Using project template: $PROJECT_TEMPLATE"
else
    SOURCE="$BASE_TEMPLATE"
    echo "Using base template (run /sdd-workflow-init to create a project-specific one)"
fi

OUTPUT="$OUTPUT_DIR/${CHANGE_NAME}-plan.md"

if [[ -f "$OUTPUT" ]]; then
    echo "Error: $OUTPUT already exists. Remove it or choose a different name."
    exit 1
fi

cp "$SOURCE" "$OUTPUT"

# Replace placeholders with the change name
sed -i "s/<change-name-in-kebab-case>/$CHANGE_NAME/g" "$OUTPUT" 2>/dev/null || true
sed -i "s/<change-name>/$CHANGE_NAME/g" "$OUTPUT" 2>/dev/null || true

echo ""
echo "Created: $OUTPUT"
echo ""
echo "Next steps:"
echo "  1. Edit $OUTPUT — fill in what you know"
echo "  2. Run: /plan-spec $CHANGE_NAME"
echo "     (or paste the content into /opsx:propose $CHANGE_NAME)"
