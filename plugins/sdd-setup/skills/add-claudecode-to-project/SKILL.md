---
name: add-claudecode-to-project
description: Integrate Claude Code (CLI + VS Code extension) into an existing project's dev container. Creates or updates three core files -- initialize_devcontainer.sh (host-side config seeding), setup_devcontainer.sh (in-container CLI install), and devcontainer.json (mounts, env vars, extension, lifecycle commands). Supports Bedrock or Anthropic API key authentication. Use when the user wants to add Claude Code to a devcontainer, set up the Claude Code VS Code extension, configure Bedrock or API key authentication for Claude in the container, or set up per-project Claude config isolation.
tools: Read, Edit, Write, Bash
---

# Add Claude Code to an Existing Dev Container

This skill adds Claude Code (CLI and VS Code extension) to a project that already has a devcontainer. It GENERATES project-specific files with values baked in -- not parameterized shared scripts. If files already exist (e.g., the project was created by `create-devcontainer-project`), the skill UPDATES them by adding Claude Code sections. If they don't exist, it CREATES them.

The three core files this skill creates or updates:

| File | Runs where | Purpose |
|------|-----------|---------|
| `.devcontainer/initialize_devcontainer.sh` | Docker HOST via `initializeCommand` | Create per-project Claude config dirs, pre-seed claude.json with `initialPermissionMode` |
| `.devcontainer/setup_devcontainer.sh` | Inside container via `postCreateCommand` | Install Claude Code CLI via curl installer |
| `.devcontainer/devcontainer.json` | Container config | Mounts, env vars, extension, lifecycle commands |

**Troubleshooting**: If builds fail or tools misbehave, delegate to the `builder` agent (`plugins/sdd-setup/agents/builder/`) for diagnosis.

---

## Step 1 -- Ask the user: Bedrock or Anthropic?

Before modifying any files, ask the user which authentication method they want. Do not assume one or the other.

| Method | What it needs |
|--------|--------------|
| **AWS Bedrock** | `.aws` mount (readonly), `CLAUDE_CODE_USE_BEDROCK=1`, `AWS_REGION` in remoteEnv, VS Code settings `claude-code.apiProvider: "bedrock"` and `claude-code.awsRegion` |
| **Anthropic API key** | `ANTHROPIC_API_KEY` in remoteEnv. No special mounts or VS Code settings needed. |

Both methods always include `GITHUB_PERSONAL_ACCESS_TOKEN` in remoteEnv so Claude Code can access private repositories and create pull requests.

---

## Step 2 -- Read existing devcontainer state

Read these files before making any changes:

- `.devcontainer/devcontainer.json`
- `.devcontainer/Dockerfile` (or `../Dockerfile` if the build context points up)
- Any existing `.devcontainer/*.sh` scripts (e.g., `initialize_devcontainer.sh`, `setup_devcontainer.sh`, or similarly named files)

Identify:

- Which base image the Dockerfile uses (Ubuntu, CUDA, Debian, etc.)
- Which user the Dockerfile creates (look for `RUN useradd` or `USER` directives -- the default username is `appuser`)
- Whether `curl` is already in the `apt-get install` list (required for Claude CLI installer)
- Whether the Dockerfile sets `ENV PATH="/home/appuser/.local/bin:${PATH}"` (needed for Claude CLI)
- Whether `mounts`, `remoteEnv`, `initializeCommand`, `postCreateCommand`, or `containerUser` already exist in devcontainer.json
- Whether any existing lifecycle commands exist that must be preserved (do not overwrite them -- merge)
- What already exists vs what needs to be created vs updated

---

## Step 3 -- Create or update initialize_devcontainer.sh

The `initializeCommand` runs on the **host** before the container builds. It must create the per-project config directories and files that Docker will bind-mount. Docker single-file bind mounts fail if the source file does not exist on the host.

If `.devcontainer/initialize_devcontainer.sh` already exists, **add** the Claude Code section to it. If it does not exist, create the full script.

The initialize script must include the `add_json_property` helper function (from `plugins/sdd-setup/templates/add_json_property.sh` in this plugin). Include the EXACT function body in the generated script.

### Claude Code section to add

Replace `PROJECT_NAME` with the actual project name throughout:

```bash
# ── Helper: safely add a property to a JSON file ──────────────────────
# Usage: add_json_property <file_path> <prop_name> <prop_value>
# - Skips if property already exists
# - Auto-quotes string values; leaves true/false/null/numbers unquoted
# - Creates the file if it is empty or contains only {}
add_json_property() {
    local file_path="$1"
    local prop_name="$2"
    local prop_value="$3"
    if [[ ! "$prop_value" =~ ^(true|false|null|-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?|\".*\")$ ]]; then
        prop_value="\"$prop_value\""
    fi
    if grep -qs "\"$prop_name\"" "$file_path"; then
        return
    fi
    if ! [ -s "$file_path" ] || grep -Eq '^[[:space:]]*\{[[:space:]]*\}[[:space:]]*$' "$file_path"; then
        printf '{\n  "%s": %s\n}\n' "$prop_name" "$prop_value" > "$file_path"
    else
        sed -zE 's/\}[[:space:]]*$/,\n  "'"$prop_name"'": '"$prop_value"'\n}/' "$file_path" > "$file_path.tmp"
        mv "$file_path.tmp" "$file_path"
    fi
}

# ── Claude Code per-project config ────────────────────────────────────
# Create per-project Claude config directory (maps to ~/.claude inside container)
mkdir -p "${HOME}/.claude-PROJECT_NAME/data"

# Pre-seed claude.json (maps to ~/.claude.json inside container)
# Docker single-file bind mount REQUIRES the source file to exist.
CLAUDE_JSON="${HOME}/.claude-PROJECT_NAME/claude.json"
if [ ! -f "$CLAUDE_JSON" ]; then
    echo "{}" > "$CLAUDE_JSON"
fi

# Set permission mode -- bypassPermissions is safe for isolated container environments
add_json_property "$CLAUDE_JSON" "initialPermissionMode" "bypassPermissions"
```

### If creating the file from scratch

Wrap the above in a full script:

```bash
#!/bin/bash
set -e

# <paste add_json_property function here>

# <paste Claude Code section here>

echo "Claude Code config for PROJECT_NAME ready at ${HOME}/.claude-PROJECT_NAME/"
```

Make the script executable:

```bash
chmod +x .devcontainer/initialize_devcontainer.sh
```

**Key rule**: Permission mode is set via `initialPermissionMode` in `claude.json`, NOT via `permissions.defaultMode` in `settings.json`. There is no need to create or seed `settings.json`.

---

## Step 4 -- Create or update setup_devcontainer.sh

The `postCreateCommand` runs **inside** the container after creation. It installs the Claude Code CLI.

### Claude Code install line

```bash
# Install Claude Code CLI
curl -fsSL https://claude.ai/install.sh | bash || echo 'WARNING: Claude Code install failed - continuing'
```

### If the file does not exist

Create `.devcontainer/setup_devcontainer.sh` with the full script:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "=== Devcontainer setup ==="

# Ensure ~/.local/bin exists and is on PATH
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# ── Claude Code CLI ───────────────────────────────────────────────────
echo "[claude] Installing Claude Code CLI..."
if command -v claude &>/dev/null; then
    echo "  Already installed: $(claude --version 2>/dev/null || echo 'unknown version')"
else
    curl -fsSL https://claude.ai/install.sh | bash || echo 'WARNING: Claude Code install failed - continuing'
    echo "  Installed: $(claude --version 2>/dev/null || echo 'check manually')"
fi

# Ensure PATH persistence in .bashrc
if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

# ── Git safe directory ────────────────────────────────────────────────
echo "[git] Configuring git safe directories..."
WORKSPACE="$(pwd)"
git config --global --add safe.directory "$WORKSPACE" 2>/dev/null || true

# ── Fix executable permissions ────────────────────────────────────────
echo "[permissions] Fixing executable bits on scripts..."
find .devcontainer -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true

echo ""
echo "=== Setup complete ==="
```

Make the script executable:

```bash
chmod +x .devcontainer/setup_devcontainer.sh
```

### If the file already exists

Add the Claude Code install block to the existing script. Place it after any existing `mkdir -p "$HOME/.local/bin"` and PATH setup lines. If those lines don't exist, add them before the Claude install block.

**Do NOT use `npm install -g @anthropic-ai/claude-code`** -- the npm distribution is deprecated. Use the curl installer.

---

## Step 5 -- Update devcontainer.json

This is the core integration step. Update `.devcontainer/devcontainer.json` to add mounts, environment variables, lifecycle commands, the extension, and VS Code settings. If fields already exist, merge into them -- do not replace existing entries.

### 5a. Add bind mounts for per-project config isolation

Add these to the `mounts` array (create the array if it does not exist). Replace `PROJECT_NAME` with the actual project name:

```json
"mounts": [
  "source=${localEnv:HOME}/.claude-PROJECT_NAME/data,target=/home/appuser/.claude,type=bind",
  "source=${localEnv:HOME}/.claude-PROJECT_NAME/claude.json,target=/home/appuser/.claude.json,type=bind"
]
```

**For Bedrock authentication**, also add the AWS credentials mount:

```json
"source=${localEnv:HOME}/.aws,target=/home/appuser/.aws,type=bind,readonly"
```

If the project already has mounts, append to the existing array -- do not replace it.

**Critical rules**:
- Use `type=bind`, **NEVER** `type=volume` (named volumes start empty and do not sync with the host)
- `${localEnv:HOME}` resolves to the host user's home directory
- The initialize script (Step 3) must create these paths before the container builds
- Replace `appuser` with the actual container username if different

### 5b. Add/update remoteEnv for authentication

Add the authentication variables based on the user's chosen method. **Do NOT set PATH in remoteEnv** -- PATH is set in the Dockerfile via `ENV` (see Step 6).

**Anthropic API key:**

```json
"remoteEnv": {
  "ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}",
  "GITHUB_PERSONAL_ACCESS_TOKEN": "${localEnv:GITHUB_PERSONAL_ACCESS_TOKEN}"
}
```

**AWS Bedrock:**

```json
"remoteEnv": {
  "CLAUDE_CODE_USE_BEDROCK": "1",
  "AWS_REGION": "us-west-2",
  "GITHUB_PERSONAL_ACCESS_TOKEN": "${localEnv:GITHUB_PERSONAL_ACCESS_TOKEN}"
}
```

Always include `GITHUB_PERSONAL_ACCESS_TOKEN`. If `remoteEnv` already exists, merge into it -- do not replace existing entries.

### 5c. Add initializeCommand

If `initializeCommand` does not exist, add it:

```json
"initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize_devcontainer.sh"
```

If an `initializeCommand` already exists, chain commands:

```json
"initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/existing-init.sh && bash ${localWorkspaceFolder}/.devcontainer/initialize_devcontainer.sh"
```

### 5d. Add postCreateCommand

If `postCreateCommand` does not exist, add it. Replace `PROJECT_NAME` with the actual project name:

```json
"postCreateCommand": "/bin/bash /workspaces/PROJECT_NAME/.devcontainer/setup_devcontainer.sh"
```

If an existing `postCreateCommand` already exists, chain:

```json
"postCreateCommand": "existing-command && /bin/bash /workspaces/PROJECT_NAME/.devcontainer/setup_devcontainer.sh"
```

**Do NOT use `onCreateCommand`** -- use `postCreateCommand`.

**Do NOT add a `postStartCommand`** -- the VS Code extension is handled by the `customizations.vscode.extensions` declaration and does not need a runtime safety net.

### 5e. Add the VS Code extension

Add `anthropic.claude-code` to `customizations.vscode.extensions`:

```json
"customizations": {
  "vscode": {
    "extensions": [
      "anthropic.claude-code"
    ]
  }
}
```

**The correct extension ID is `anthropic.claude-code`** (no trailing 's'). Using `anthropics.claude-code` will fail silently.

If the `extensions` array already exists, append to it. Do not replace existing extensions.

### 5f. Add VS Code settings for Bedrock

For Bedrock authentication only, add the API provider and region settings:

```json
"customizations": {
  "vscode": {
    "settings": {
      "claude-code.apiProvider": "bedrock",
      "claude-code.awsRegion": "us-west-2"
    }
  }
}
```

For Anthropic API key authentication, these settings are not needed.

If `settings` already exists, merge into it.

### 5g. Complete devcontainer.json examples

**Bedrock example** (showing only the Claude Code additions):

```json
{
  "remoteEnv": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "us-west-2",
    "GITHUB_PERSONAL_ACCESS_TOKEN": "${localEnv:GITHUB_PERSONAL_ACCESS_TOKEN}"
  },
  "initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize_devcontainer.sh",
  "postCreateCommand": "/bin/bash /workspaces/PROJECT_NAME/.devcontainer/setup_devcontainer.sh",
  "mounts": [
    "source=${localEnv:HOME}/.claude-PROJECT_NAME/data,target=/home/appuser/.claude,type=bind",
    "source=${localEnv:HOME}/.claude-PROJECT_NAME/claude.json,target=/home/appuser/.claude.json,type=bind",
    "source=${localEnv:HOME}/.aws,target=/home/appuser/.aws,type=bind,readonly"
  ],
  "customizations": {
    "vscode": {
      "extensions": [
        "anthropic.claude-code"
      ],
      "settings": {
        "claude-code.apiProvider": "bedrock",
        "claude-code.awsRegion": "us-west-2"
      }
    }
  }
}
```

**Anthropic API key example** (showing only the Claude Code additions):

```json
{
  "remoteEnv": {
    "ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}",
    "GITHUB_PERSONAL_ACCESS_TOKEN": "${localEnv:GITHUB_PERSONAL_ACCESS_TOKEN}"
  },
  "initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize_devcontainer.sh",
  "postCreateCommand": "/bin/bash /workspaces/PROJECT_NAME/.devcontainer/setup_devcontainer.sh",
  "mounts": [
    "source=${localEnv:HOME}/.claude-PROJECT_NAME/data,target=/home/appuser/.claude,type=bind",
    "source=${localEnv:HOME}/.claude-PROJECT_NAME/claude.json,target=/home/appuser/.claude.json,type=bind"
  ],
  "customizations": {
    "vscode": {
      "extensions": [
        "anthropic.claude-code"
      ]
    }
  }
}
```

---

## Step 6 -- Ensure Dockerfile has PATH for ~/.local/bin

The Claude CLI installs to `~/.local/bin/claude`. Check the Dockerfile for this line:

```dockerfile
ENV PATH="/home/appuser/.local/bin:${PATH}"
```

Replace `appuser` with the actual username if different. This line should appear **before** the `USER` directive in the devcontainer stage.

If this `ENV` line is missing, add it. Without it, the `claude` binary will not be on PATH in non-interactive contexts like VS Code tasks or lifecycle commands.

Do NOT set PATH via `remoteEnv` in devcontainer.json -- it belongs in the Dockerfile `ENV` directive.

Also ensure `curl` is in the Dockerfile's `apt-get install` list (required by the Claude CLI installer). If missing, add `curl` and `ca-certificates` to the existing `apt-get install` block.

---

## Step 7 -- Rebuild the container

After saving all file changes, tell the user to rebuild:

- **VS Code**: `Ctrl+Shift+P` then "Dev Containers: Rebuild Container"
- **CLI**: `devcontainer build --workspace-folder .`

**First run with API key**: No additional login step needed -- the key is passed via `remoteEnv`.

**First run with Bedrock**: No login step needed -- AWS credentials are provided via the `~/.aws` bind mount.

---

## Step 8 -- Verify installation

Inside the rebuilt container terminal, run:

```bash
# CLI installed and on PATH
claude --version              # Should print Claude Code version
which claude                  # Should be /home/appuser/.local/bin/claude (NOT a node_modules path)

# Per-project config mounted correctly
ls ~/.claude/                 # Should show persistent config from host
cat ~/.claude.json            # Should show initialPermissionMode set

# VS Code extension
# The Claude Code icon should appear in the VS Code sidebar
```

For Bedrock auth, also verify:

```bash
echo $CLAUDE_CODE_USE_BEDROCK  # Should print 1
echo $AWS_REGION               # Should print us-west-2 (or chosen region)
ls ~/.aws/                     # Should show credentials and config files
```

For API key auth:

```bash
echo $ANTHROPIC_API_KEY       # Should print the key value (non-empty)
```

---

## Common pitfalls

| Mistake | Fix |
|---------|-----|
| Extension ID `anthropics.claude-code` (with trailing 's') | Use `anthropic.claude-code` -- the wrong ID fails silently |
| `npm install -g @anthropic-ai/claude-code` for CLI | Deprecated. Use `curl -fsSL https://claude.ai/install.sh \| bash` via `postCreateCommand` |
| CLI install via `onCreateCommand` | Use `postCreateCommand`, not `onCreateCommand` |
| `initialPermissionMode` set in `settings.json` | Wrong file. Set `initialPermissionMode` in `claude.json` via the `add_json_property` helper |
| Named volume for config (`type=volume`) | Use `type=bind` -- named volumes start empty and do not sync with the host |
| Shared `~/.claude` across projects | Use `~/.claude-PROJECT_NAME/data` per project for isolation |
| Missing `~/.claude.json` on host before build | The `initializeCommand` script must create it -- Docker single-file bind mount fails on missing source |
| Missing `~/.claude-PROJECT_NAME/data` on host before build | The `initializeCommand` script must `mkdir -p` it -- Docker bind mount fails on missing source directory |
| `remoteUser` instead of `containerUser` | Use `containerUser` in devcontainer.json |
| PATH set in `remoteEnv` | Set PATH in the Dockerfile via `ENV PATH="/home/appuser/.local/bin:${PATH}"` -- not in remoteEnv |
| Adding a `postStartCommand` for extension install | Not needed -- declare the extension in `customizations.vscode.extensions` instead |
| First-time wizard on every rebuild | Mount `claude.json` pre-seeded by initialize script with `initialPermissionMode` set |
| `claude` not found in PATH | Ensure `ENV PATH="/home/appuser/.local/bin:${PATH}"` is in the Dockerfile before the USER directive |
| Overwriting existing `postCreateCommand` | Chain commands with `&&` -- do not replace existing lifecycle commands |
| Overwriting existing `mounts` array | Append new entries to existing array -- do not replace it |
| `initializeCommand` script not executable | Run `chmod +x .devcontainer/initialize_devcontainer.sh` |
| Bedrock auth fails inside container | Requires BOTH the `~/.aws` bind mount AND `CLAUDE_CODE_USE_BEDROCK=1` in remoteEnv |
| Bedrock extension not working | Add `"claude-code.apiProvider": "bedrock"` and `"claude-code.awsRegion"` to VS Code settings in devcontainer.json -- env vars alone are not enough for the extension |
| Missing `GITHUB_PERSONAL_ACCESS_TOKEN` | Forward via `remoteEnv`: `"GITHUB_PERSONAL_ACCESS_TOKEN": "${localEnv:GITHUB_PERSONAL_ACCESS_TOKEN}"` |
| Curl installer with `-y` flag | Do not pass `-y`. Use plain: `curl -fsSL https://claude.ai/install.sh \| bash` |
| Missing `curl` in Dockerfile | The Claude CLI installer requires `curl` and `ca-certificates` in the `apt-get install` list |

---

## File inventory

After this skill completes, the following files should be created or modified:

| File | Action | Purpose |
|------|--------|---------|
| `.devcontainer/initialize_devcontainer.sh` | Created or modified | Host-side script to create per-project Claude config directories and set `initialPermissionMode` in claude.json |
| `.devcontainer/setup_devcontainer.sh` | Created or modified | In-container script that installs Claude Code CLI via curl installer |
| `.devcontainer/devcontainer.json` | Modified | Added mounts, remoteEnv, lifecycle commands, extension, and (for Bedrock) VS Code settings |
| `.devcontainer/Dockerfile` | Possibly modified | Ensure `curl` is present and `ENV PATH` includes `~/.local/bin` |
