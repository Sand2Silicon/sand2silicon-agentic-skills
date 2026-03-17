---
name: integrate-claudecode
description: Integrate Claude Code (CLI + VS Code extension) into any project's dev container using a standard Anthropic API key or OAuth subscription. Use when the user wants to add Claude Code to a devcontainer, set up the Claude Code VS Code extension, or configure authentication in a container environment. Trigger this whenever devcontainer + Claude Code integration is mentioned.
tools: Read, Edit, Write, Bash
---

# Integrate Claude Code into a Dev Container

This skill adds Claude Code (CLI + VS Code extension) to any existing devcontainer setup. It handles CLI installation, extension configuration, authentication persistence, and per-project isolation.

**Authentication**: Supports OAuth via Claude subscription (credentials in `~/.claude/.credentials.json`) and `ANTHROPIC_API_KEY` as fallback.

**Isolation**: Each project gets its own Claude config directory on the host (`~/.claude-<projectname>/`) so multiple devcontainers don't conflict. Auth, settings, history, and memory persist across container rebuilds.

Replace `<PROJECTNAME>` throughout with the actual project/directory name.

---

## Step 1 — Verify current devcontainer state

Read the existing files before making changes:

- `.devcontainer/devcontainer.json`
- `.devcontainer/Dockerfile`
- `.devcontainer/initialize_devcontainer.sh` (if it exists)

---

## Step 2 — Install Claude Code CLI via native installer

**Do NOT use npm or the devcontainer feature** (`ghcr.io/anthropics/devcontainer-features/claude-code`) — both use the deprecated npm package `@anthropic-ai/claude-code` which shows a yellow warning.

Use the official native installer via `onCreateCommand` in `devcontainer.json`:

```json
"onCreateCommand": "curl -fsSL https://claude.ai/install.sh | bash"
```

This installs the `claude` binary to `~/.local/bin/claude` with no Node.js dependency. It runs once when the container is first created (not on every start).

Ensure `~/.local/bin` is on PATH via `remoteEnv`:

```json
"remoteEnv": {
  "PATH": "/home/vscode/.local/bin:${containerEnv:PATH}"
}
```

The Dockerfile needs `curl` in its apt-get install list.

---

## Step 3 — Add the Claude Code VS Code extension

**The correct extension ID is `anthropic.claude-code`** (no trailing 's'). Using `anthropics.claude-code` will fail silently with "Failed Installing Extensions".

Add it to `customizations.vscode.extensions` in `devcontainer.json`:

```json
"customizations": {
  "vscode": {
    "extensions": [
      "anthropic.claude-code"
    ]
  }
}
```

Extension installs run in parallel with container setup and can race/fail intermittently. Add a `postStartCommand` as a safety net:

```json
"postStartCommand": "code --install-extension anthropic.claude-code 2>/dev/null || true"
```

---

## Step 4 — Pass the API key into the container (optional fallback)

```json
"remoteEnv": {
  "ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}",
  "PATH": "/home/vscode/.local/bin:${containerEnv:PATH}"
}
```

---

## Step 5 — Mount per-project Claude config into the container

Claude Code uses two locations:

1. **`~/.claude/`** (directory) — credentials, settings, history, sessions, memory
2. **`~/.claude.json`** (file) — onboarding state, MCP servers, per-project trust

Mount from `~/.claude-<PROJECTNAME>/` on the host:

```json
"mounts": [
  "source=${localEnv:HOME}/.claude-<PROJECTNAME>/data,target=/home/vscode/.claude,type=bind,consistency=cached",
  "source=${localEnv:HOME}/.claude-<PROJECTNAME>/claude.json,target=/home/vscode/.claude.json,type=bind,consistency=cached"
]
```

**Critical notes**:
- Use `type=bind`, never `type=volume` (named volumes start empty)
- Docker single-file bind mounts fail if the source file doesn't exist — the `initializeCommand` script handles creation

---

## Step 6 — Add initializeCommand with bootstrap script

The `initializeCommand` runs on the host **before** the container builds. It ensures the project-specific config directory and files exist.

```json
"initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize_devcontainer.sh"
```

Create `.devcontainer/initialize_devcontainer.sh` (make it executable):

```bash
#!/bin/bash
set -e

PROJECT_NAME="<PROJECTNAME>"
CLAUDE_CONFIG_DIR="${HOME}/.claude-${PROJECT_NAME}"
CLAUDE_DATA_DIR="${CLAUDE_CONFIG_DIR}/data"
CLAUDE_JSON="${CLAUDE_CONFIG_DIR}/claude.json"
CLAUDE_SETTINGS="${CLAUDE_DATA_DIR}/settings.json"

add_json_property() {
    local file_path="$1" prop_name="$2" prop_value="$3"
    grep -qs "\"$prop_name\"" "$file_path" && return
    if ! [ -s "$file_path" ] || grep -Eq '^[[:space:]]*\{[[:space:]]*\}[[:space:]]*$' "$file_path"; then
        printf '{\n  "%s": %s\n}\n' "$prop_name" "$prop_value" > "$file_path"
    else
        sed -zE 's/\}[[:space:]]*$/,\n  "'"$prop_name"'": '"$prop_value"'\n}/' "$file_path" > "$file_path.tmp"
        mv "$file_path.tmp" "$file_path"
    fi
}

mkdir -p "${CLAUDE_DATA_DIR}"
[ -f "${CLAUDE_JSON}" ] || echo '{}' > "${CLAUDE_JSON}"
add_json_property "${CLAUDE_JSON}" "hasCompletedOnboarding" "true"

if [ ! -f "${CLAUDE_SETTINGS}" ]; then
    cat > "${CLAUDE_SETTINGS}" << 'EOF'
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
EOF
fi

echo "Claude Code config for ${PROJECT_NAME} verified at ${CLAUDE_CONFIG_DIR}/"
```

---

## Step 7 — Rebuild the container

- **VS Code**: `Ctrl+Shift+P` → "Dev Containers: Rebuild Container"
- **CLI**: `devcontainer build --workspace-folder .`

**First run**: Claude Code CLI needs to authenticate once. Credentials then persist across rebuilds.

---

## Common pitfalls

| Mistake | Fix |
|---------|-----|
| Extension ID `anthropics.claude-code` (with 's') | Use `anthropic.claude-code` |
| npm install / devcontainer feature for CLI | Deprecated — use native installer via `onCreateCommand` |
| Extension not installed after rebuild | Add `postStartCommand` with `code --install-extension` |
| Named volume for config (`type=volume`) | Use bind mount (`type=bind`) |
| Shared `~/.claude` across projects | Use `~/.claude-<projectname>/data` per project |
| Missing `~/.claude.json` on host | `initializeCommand` must create it before build |
| `live_dangerously` in `~/.claude.json` | Not a valid field — use `permissions.defaultMode` in `settings.json` |
| First-time wizard on every rebuild | Mount `claude.json` with `hasCompletedOnboarding: true` |
| `claude` not found in PATH | Add `/home/vscode/.local/bin` to PATH via `remoteEnv` |
