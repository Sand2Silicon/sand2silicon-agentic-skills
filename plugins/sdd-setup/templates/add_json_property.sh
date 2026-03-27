# add_json_property — idempotent helper for writing JSON properties to files.
# Include this function in initialize_devcontainer.sh scripts.
#
# Usage:
#   add_json_property <file_path> <property_name> <value>
#
# Values are auto-quoted unless they look like JSON literals (true/false/null/number).
# If the property already exists, does nothing (idempotent).
# Requires GNU sed (for -z flag). Works on Linux hosts; on macOS may need gsed.

add_json_property() {
    local file_path="$1"
    local prop_name="$2"
    local prop_value="$3"

    # Wrap value in quotes if it is not already a JSON literal (boolean, number, null, or pre-quoted string)
    if [[ ! "$prop_value" =~ ^(true|false|null|-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?|\".*\")$ ]]; then
        prop_value="\"$prop_value\""
    fi

    # Check if property already exists
    if grep -qs "\"$prop_name\"" "$file_path"; then
        return
    fi

    # If file is empty or just contains '{}', overwrite it
    if ! [ -s "$file_path" ] || grep -Eq '^[[:space:]]*\{[[:space:]]*\}[[:space:]]*$' "$file_path"; then
        printf '{\n  "%s": %s\n}\n' "$prop_name" "$prop_value" > "$file_path"
    else
        # Insert property before the closing brace of the existing JSON object
        sed -zE 's/\}[[:space:]]*$/,\n  "'"$prop_name"'": '"$prop_value"'\n}/' "$file_path" > "$file_path.tmp"
        mv "$file_path.tmp" "$file_path"
    fi
}
