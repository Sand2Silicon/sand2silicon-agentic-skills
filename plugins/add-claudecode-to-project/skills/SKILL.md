---
name: add-claudecode-to-project
description: Integrate Claude Code (CLI + VS Code extension) into this project's dev container using a standard Anthropic API key or OAuth subscription. Use when the user wants to add Claude Code to the devcontainer, set up the Claude Code VS Code extension, or configure authentication in the container environment.
tools: Read, Edit, Write, Bash
---

# Integrate Claude Code into the Dev Container

This skill configures Claude Code for this project's dev container. The container is based on `nvidia/cuda:12.1.0-runtime-ubuntu22.04`, runs as the `vscode` user, and mounts the workspace at `/workspace`.

**Authentication**: Uses OAuth via Claude subscription (credentials stored in `~/.claude/.credentials.json`). `ANTHROPIC_API_KEY` is also forwarded as a fallback for API key auth.

**Isolation**: Each project gets its own Claude config directory on the host (`~/.claude-<projectname>/`) so multiple devcontainers don't conflict. Auth, settings, history, and memory persist across container rebuilds.

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

The Dockerfile needs `curl` in its apt-get install list (already present in this project).

---

## Step 3 — Add the Claude Code VS Code extension

**The correct extension ID is `anthropic.claude-code`** (no trailing 's'). Using `anthropics.claude-code` will fail silently with "Failed Installing Extensions".

Add it to `customizations.vscode.extensions` in `devcontainer.json`:

```json
"customizations": {
  "vscode": {
    "extensions": [
      "ms-python.python",
      "ms-toolsai.jupyter",
      "ms-vscode-remote.remote-containers",
      "anthropic.claude-code"
    ]
  }
}
```

Extension installs from `customizations.vscode.extensions` run in parallel with container setup and can race/fail intermittently. Add a `postStartCommand` as a safety net that re-attempts the install on every container start:

```json
"postStartCommand": "code --install-extension anthropic.claude-code 2>/dev/null || true"
```

This is idempotent — if the extension is already installed it's a no-op.

---

## Step 4 — Pass the API key into the container (optional fallback)

For API key auth as a fallback, add `ANTHROPIC_API_KEY` via `remoteEnv`:

```json
"remoteEnv": {
  "ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}",
  "PATH": "/home/vscode/.local/bin:${containerEnv:PATH}"
}
```

Not required for OAuth/subscription auth — that propagates via the bind-mounted credentials file.

---

## Step 5 — Mount per-project Claude config into the container

Use **project-specific bind mounts** so multiple devcontainers don't conflict. Claude Code uses two locations:

1. **`~/.claude/`** (directory) — credentials, settings, history, sessions, memory
2. **`~/.claude.json`** (file) — onboarding state, MCP servers, per-project trust

Mount them from `~/.claude-<projectname>/` on the host:

```json
"mounts": [
  "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached",
  "source=${localEnv:HOME}/.claude-cryptoPredictionModel/data,target=/home/vscode/.claude,type=bind,consistency=cached",
  "source=${localEnv:HOME}/.claude-cryptoPredictionModel/claude.json,target=/home/vscode/.claude.json,type=bind,consistency=cached"
]
```

**Critical notes**:
- Use `type=bind`, never `type=volume` (named volumes start empty, won't propagate host state)
- Docker single-file bind mounts fail if the source file doesn't exist — the `initializeCommand` script handles creation
- `${localEnv:HOME}` resolves to the host user's home directory

---

## Step 6 — Add initializeCommand with bootstrap script

The `initializeCommand` runs on the host **before** the container builds. It ensures the project-specific config directory and files exist.

```json
"initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize_devcontainer.sh"
```

Create `.devcontainer/initialize_devcontainer.sh`:

```bash
#!/bin/bash
set -e

PROJECT_NAME="cryptoPredictionModel"
CLAUDE_CONFIG_DIR="${HOME}/.claude-${PROJECT_NAME}"
CLAUDE_DATA_DIR="${CLAUDE_CONFIG_DIR}/data"
CLAUDE_JSON="${CLAUDE_CONFIG_DIR}/claude.json"
CLAUDE_SETTINGS="${CLAUDE_DATA_DIR}/settings.json"

# Create project-specific config directories
mkdir -p "${CLAUDE_DATA_DIR}"

# Ensure claude.json exists (Docker single-file bind mount requires it)
if [ ! -f "${CLAUDE_JSON}" ]; then
    echo '{}' > "${CLAUDE_JSON}"
fi

# Mark onboarding complete so CLI skips first-time wizard
# (uses add_json_property helper — see full script)
add_json_property "${CLAUDE_JSON}" "hasCompletedOnboarding" "true"

# Create settings.json with permission bypass for container environment
if [ ! -f "${CLAUDE_SETTINGS}" ]; then
    cat > "${CLAUDE_SETTINGS}" << 'EOF'
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
EOF
fi
```

A standalone bootstrap script is also available at `scripts/setup-claude-code.sh` for manual setup or onboarding new team members.

---

## Step 7 — Rebuild the container

After saving all files, rebuild the container:

- **VS Code**: `Ctrl+Shift+P` → "Dev Containers: Rebuild Container"
- **CLI**: `devcontainer build --workspace-folder .`

**First run**: Claude Code CLI will need to authenticate once. After that, credentials persist in `~/.claude-cryptoPredictionModel/data/.credentials.json` across rebuilds.

---

## Verification

Inside the container terminal:

```bash
claude --version        # should print Claude Code version
which claude            # should be ~/.local/bin/claude (native installer)
ls ~/.claude/           # should show persistent config from host
cat ~/.claude.json      # should show hasCompletedOnboarding: true
```

The Claude Code extension should appear in the VS Code sidebar.

---

## Permission bypass (bypassPermissions)

The `initializeCommand` script sets `"permissions": {"defaultMode": "bypassPermissions"}` in `~/.claude/settings.json` (inside the container). This skips all permission prompts — appropriate for isolated container environments.

**`live_dangerously` is NOT a valid field** in `~/.claude.json`. The correct mechanism is `permissions.defaultMode` in a `settings.json` file. Valid modes:

| Mode | Behavior |
|------|----------|
| `default` | Prompts for permission on first use of each tool |
| `acceptEdits` | Auto-accepts file edit permissions for the session |
| `plan` | Read-only analysis mode |
| `dontAsk` | Auto-denies unless pre-approved via `permissions.allow` |
| `bypassPermissions` | Skips all permission prompts (container-only) |

---

## Common pitfalls

| Mistake | Fix |
|---------|-----|
| Extension ID `anthropics.claude-code` (with 's') | Use `anthropic.claude-code` |
| npm install / devcontainer feature for CLI | Deprecated — use native installer `curl -fsSL https://claude.ai/install.sh \| bash` via `onCreateCommand` |
| Extension not installed after rebuild | Add `postStartCommand` with `code --install-extension` as safety net |
| Named volume for config (`type=volume`) | Use bind mount (`type=bind`) |
| Shared `~/.claude` across projects | Use `~/.claude-<projectname>/data` per project |
| Missing `~/.claude.json` on host | `initializeCommand` must create it before build |
| `live_dangerously` in `~/.claude.json` | Not a valid field — use `permissions.defaultMode` in `settings.json` |
| First-time wizard on every rebuild | Mount `claude.json` with `hasCompletedOnboarding: true` |
| `claude` not found in PATH | Add `/home/vscode/.local/bin` to PATH via `remoteEnv` |
| Deprecated `terminal.integrated.shell.linux` | Use `terminal.integrated.defaultProfile.linux` |

---

## File inventory

| File | Purpose |
|------|---------|
| `.devcontainer/devcontainer.json` | Extension, native CLI install, mounts, remoteEnv, initializeCommand |
| `.devcontainer/Dockerfile` | No Claude-specific changes needed |
| `.devcontainer/initialize_devcontainer.sh` | Creates project-specific host dirs, claude.json, settings.json |
| `scripts/setup-claude-code.sh` | Standalone bootstrap script (same logic, verbose output, accepts project name arg) |
