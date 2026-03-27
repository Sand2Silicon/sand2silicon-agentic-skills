---
name: add-claudecode-to-project
description: Integrate Claude Code (CLI + VS Code extension) into an existing project's dev container. Adds CLI installation via postCreateCommand curl installer, VS Code extension with Bedrock settings, per-project config isolation via bind mounts, authentication (API key, Bedrock, Vertex, or OAuth), permission mode configuration via claude.json initialPermissionMode, and a two-script lifecycle (initialize.sh + setup.sh). Use when the user wants to add Claude Code to a devcontainer, set up the Claude Code VS Code extension, configure authentication for Claude in the container, or set up per-project Claude config isolation.
tools: Read, Edit, Write, Bash
---

# Add Claude Code to an Existing Dev Container

This skill adds Claude Code (CLI and VS Code extension) to a project that already has a devcontainer. It modifies the existing Dockerfile, devcontainer.json, and lifecycle scripts. It does NOT create a new project from scratch -- use the `create-devcontainer-project` skill for that.

**Two-script lifecycle**: This skill uses only two lifecycle scripts:
- `initialize.sh` -- runs on the Docker HOST via `initializeCommand`
- `setup.sh` -- runs inside the container via `postCreateCommand`

There is no `post-start.sh`. The VS Code extension is declared in `customizations.vscode.extensions` and does not need a runtime safety net.

**Troubleshooting**: If builds fail or tools misbehave, delegate to the `builder` agent (`plugins/sdd-setup/agents/builder/`) for diagnosis.

---

## Step 1 -- Read existing devcontainer state

Read the existing files before making any changes:

- `.devcontainer/devcontainer.json`
- `.devcontainer/Dockerfile`
- Any existing lifecycle scripts (e.g., `.devcontainer/initialize.sh`, `.devcontainer/setup.sh`, or similarly named files)

Identify:

- Which base image the Dockerfile uses (Ubuntu, CUDA, Debian, etc.)
- Whether `curl` is already in the `apt-get install` list
- Which user the Dockerfile creates (look for `RUN useradd` or `USER` directives -- the default username is `appuser`)
- Whether the Dockerfile sets `ENV PATH="/home/appuser/.local/bin:${PATH}"` (needed for Claude CLI)
- Whether `mounts`, `remoteEnv`, `initializeCommand`, `postCreateCommand`, or `containerUser` already exist in devcontainer.json
- Whether any existing lifecycle commands exist that must be preserved (do not overwrite them -- merge)

---

## Step 2 -- Ask the user about authentication and permissions

Before modifying files, ask the user two questions:

### Authentication method

| Method | Required environment | Notes |
|--------|---------------------|-------|
| **Anthropic API key** (default) | `ANTHROPIC_API_KEY` | Simplest. Pass via `remoteEnv` from host env. |
| **AWS Bedrock** | `CLAUDE_CODE_USE_BEDROCK=1` + AWS credentials | Mount `~/.aws` readonly and set `AWS_REGION`. |
| **Google Vertex AI** | `CLAUDE_CODE_USE_VERTEX=1` + `CLOUD_ML_REGION` + `ANTHROPIC_VERTEX_PROJECT_ID` | Set project and region env vars. |
| **OAuth subscription** | None (interactive) | Run `claude login` inside container after first build. |

### Permission mode

| Mode | Behavior |
|------|----------|
| `default` | Prompts for each tool use |
| `plan` | Read-only analysis mode |
| `acceptEdits` | Auto-accepts file edits, prompts for commands |
| `dontAsk` | Auto-denies unless pre-approved in allow list |
| `bypassPermissions` | Skips all prompts (container-only recommended) |

If the user does not specify, default to `bypassPermissions`. This is safe for isolated container environments and avoids interactive permission prompts that block automated workflows.

---

## Step 3 -- Create or update the initialize script

The `initializeCommand` runs on the **host** before the container builds. It must create the per-project config directories and files that Docker will bind-mount. Docker single-file bind mounts fail if the source file does not exist on the host.

If the project already has an initialize script, **add** the Claude Code section to it. If not, create `.devcontainer/initialize.sh`.

The initialize script must use the `add_json_property` helper to safely set properties in JSON files. This helper is idempotent -- it will not overwrite existing properties.

```bash
#!/bin/bash
set -e

# ── Helper: safely add a property to a JSON file ──────────────────────
# Usage: add_json_property <file_path> <prop_name> <prop_value>
# - Skips if property already exists
# - Auto-quotes string values; leaves true/false/null/numbers unquoted
# - Creates the file if it is empty or contains only {}
add_json_property() {
    local file_path="$1"
    local prop_name="$2"
    local prop_value="$3"

    # Auto-quote non-literal values
    if [[ ! "$prop_value" =~ ^(true|false|null|-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?|\".*\")$ ]]; then
        prop_value="\"$prop_value\""
    fi

    # Skip if property already exists
    if grep -qs "\"$prop_name\"" "$file_path"; then
        return
    fi

    # Handle empty or {} file
    if ! [ -s "$file_path" ] || grep -Eq '^[[:space:]]*\{[[:space:]]*\}[[:space:]]*$' "$file_path"; then
        printf '{\n  "%s": %s\n}\n' "$prop_name" "$prop_value" > "$file_path"
    else
        sed -zE 's/\}[[:space:]]*$/,\n  "'"$prop_name"'": '"$prop_value"'\n}/' "$file_path" > "$file_path.tmp"
        mv "$file_path.tmp" "$file_path"
    fi
}

PROJECT_NAME="<project-name>"
CLAUDE_HOME="${HOME}/.claude-${PROJECT_NAME}"

# 1. Create per-project Claude config directory
#    This maps to ~/.claude inside the container
mkdir -p "$CLAUDE_HOME/data"

# 2. Pre-seed claude.json (maps to ~/.claude.json inside container)
#    Docker single-file bind mount REQUIRES the source file to exist.
CLAUDE_JSON="$CLAUDE_HOME/claude.json"
if [ ! -f "$CLAUDE_JSON" ]; then
    echo "{}" > "$CLAUDE_JSON"
fi

# 3. Set permission mode in claude.json via initialPermissionMode
#    This controls how Claude Code handles tool-use permission prompts.
add_json_property "$CLAUDE_JSON" "initialPermissionMode" "<permission-mode>"

echo "Claude Code config for ${PROJECT_NAME} ready at ${CLAUDE_HOME}/"
```

Replace `<project-name>` with the actual project name and `<permission-mode>` with the user's chosen mode (default: `bypassPermissions`).

Make the script executable:

```bash
chmod +x .devcontainer/initialize.sh
```

**Key difference from previous versions**: Permission mode is set via `initialPermissionMode` in `claude.json`, NOT via `permissions.defaultMode` in `settings.json`. There is no need to create or seed `settings.json`.

---

## Step 4 -- Update devcontainer.json

This is the core integration step. Update devcontainer.json to add mounts, environment variables, lifecycle commands, the extension, and VS Code settings.

### 4a. Set containerUser

Use `containerUser` (not `remoteUser`) to specify the non-root user:

```json
"containerUser": "appuser"
```

### 4b. Add bind mounts for per-project config isolation and credentials

Add these to the `mounts` array (create the array if it does not exist):

```json
"mounts": [
  "source=${localEnv:HOME}/.claude-<project-name>/data,target=/home/appuser/.claude,type=bind",
  "source=${localEnv:HOME}/.claude-<project-name>/claude.json,target=/home/appuser/.claude.json,type=bind"
]
```

For **Bedrock authentication**, also mount the AWS credentials directory readonly:

```json
"source=${localEnv:HOME}/.aws,target=/home/appuser/.aws,type=bind,readonly"
```

**Critical rules**:
- Use `type=bind`, **NEVER** `type=volume` (named volumes start empty and do not sync with the host)
- `${localEnv:HOME}` resolves to the host user's home directory
- The initialize script (Step 3) must create these paths before the container builds
- If the project already has mounts, append to the existing array -- do not replace it

### 4c. Add remoteEnv for authentication

Add the authentication variables based on the user's chosen method. **Do NOT set PATH in remoteEnv** -- PATH is set in the Dockerfile via `ENV` (see Step 5).

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

For Bedrock, the `~/.aws` bind mount (added in Step 4b) provides credentials. Set `AWS_REGION` to the user's preferred region.

**Google Vertex AI:**
```json
"remoteEnv": {
  "CLAUDE_CODE_USE_VERTEX": "1",
  "CLOUD_ML_REGION": "us-east5",
  "ANTHROPIC_VERTEX_PROJECT_ID": "<user-project-id>",
  "GITHUB_PERSONAL_ACCESS_TOKEN": "${localEnv:GITHUB_PERSONAL_ACCESS_TOKEN}"
}
```

**OAuth subscription:**
```json
"remoteEnv": {
  "GITHUB_PERSONAL_ACCESS_TOKEN": "${localEnv:GITHUB_PERSONAL_ACCESS_TOKEN}"
}
```

No auth env vars needed -- the user runs `claude login` inside the container after first build.

Always include `GITHUB_PERSONAL_ACCESS_TOKEN` via `remoteEnv` so Claude Code can access private repositories and create pull requests.

If `remoteEnv` already exists in devcontainer.json, merge into it. Do not replace existing entries.

### 4d. Add workspace mount

Set the workspace mount to use `/workspaces/<project-name>`:

```json
"workspaceMount": "source=${localWorkspaceFolder},target=/workspaces/<project-name>,type=bind,consistency=cached",
"workspaceFolder": "/workspaces/<project-name>"
```

### 4e. Add lifecycle commands

**initializeCommand** -- runs on the host before the container builds:

```json
"initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize.sh"
```

If an `initializeCommand` already exists, chain commands:

```json
"initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/existing-init.sh && bash ${localWorkspaceFolder}/.devcontainer/initialize.sh"
```

**postCreateCommand** -- runs inside the container once after creation. Installs the Claude CLI and runs any other setup:

```json
"postCreateCommand": "curl -fsSL https://claude.ai/install.sh | bash || echo 'WARNING: Claude Code install failed - continuing'"
```

If the project has a `setup.sh` script with additional setup steps, call it instead and include the Claude CLI install within it:

```json
"postCreateCommand": "/bin/bash /workspaces/<project-name>/.devcontainer/setup.sh"
```

Where `setup.sh` contains the curl install line along with other setup.

**Do NOT use `npm install -g @anthropic-ai/claude-code`** -- the npm distribution is deprecated. Use the curl installer.

**Do NOT use `onCreateCommand`** -- use `postCreateCommand` for the CLI install.

**Do NOT add a `postStartCommand`** -- the VS Code extension is handled by the `customizations.vscode.extensions` declaration and does not need a runtime safety net.

If an existing `postCreateCommand` already exists, chain:

```json
"postCreateCommand": "existing-command && curl -fsSL https://claude.ai/install.sh | bash || echo 'WARNING: Claude Code install failed - continuing'"
```

### 4f. Add the VS Code extension

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

### 4g. Add VS Code settings for Bedrock

For Bedrock authentication, add the API provider and region settings:

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

For other authentication methods, these settings can be omitted or adjusted accordingly.

If `settings` already exists, merge into it.

### 4h. Complete devcontainer.json example

Here is what the Claude Code additions look like assembled together (Bedrock auth, `bypassPermissions` mode):

```json
{
  "name": "<project-name>",
  "build": {
    "context": "..",
    "dockerfile": "../Dockerfile"
  },
  "containerUser": "appuser",
  "remoteEnv": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "us-west-2",
    "GITHUB_PERSONAL_ACCESS_TOKEN": "${localEnv:GITHUB_PERSONAL_ACCESS_TOKEN}"
  },
  "initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize.sh",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspaces/<project-name>,type=bind,consistency=cached",
  "workspaceFolder": "/workspaces/<project-name>",
  "postCreateCommand": "curl -fsSL https://claude.ai/install.sh | bash || echo 'WARNING: Claude Code install failed - continuing'",
  "mounts": [
    "source=${localEnv:HOME}/.aws,target=/home/appuser/.aws,type=bind,readonly",
    "source=${localEnv:HOME}/.claude-<project-name>/data,target=/home/appuser/.claude,type=bind",
    "source=${localEnv:HOME}/.claude-<project-name>/claude.json,target=/home/appuser/.claude.json,type=bind"
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

---

## Step 5 -- Ensure Dockerfile has curl and PATH

The Claude CLI installer requires `curl`. Check that `curl` is in the Dockerfile's `apt-get install` list. If not, add it:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
```

If an `apt-get install` block already exists, append `curl` and `ca-certificates` to it rather than creating a separate layer.

**Set PATH in the Dockerfile** so the Claude CLI (`~/.local/bin/claude`) is on PATH. Add this after any `USER` directive:

```dockerfile
USER appuser
ENV PATH="/home/appuser/.local/bin:${PATH}"
```

Do NOT set PATH via `remoteEnv` in devcontainer.json -- it belongs in the Dockerfile `ENV` directive.

---

## Step 6 -- Delete the old setup-claude-code.sh script

If the project has a `scripts/setup-claude-code.sh` file left over from a previous version of this skill, delete it. Its functionality has been superseded by the two-script lifecycle (`initialize.sh` + `setup.sh`) and the devcontainer lifecycle commands.

```bash
rm -f scripts/setup-claude-code.sh
```

Also remove any references to it in devcontainer.json or other scripts.

---

## Step 7 -- Rebuild the container

After saving all file changes, tell the user to rebuild the container:

- **VS Code**: `Ctrl+Shift+P` then "Dev Containers: Rebuild Container"
- **CLI**: `devcontainer build --workspace-folder .`

**First run with OAuth**: If using OAuth subscription auth, the user must run `claude login` inside the container once after the first rebuild. Credentials persist in `~/.claude-<project-name>/data/.credentials.json` across rebuilds.

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
aws sts get-caller-identity    # Should succeed (if AWS CLI is available)
```

For API key auth:

```bash
echo $ANTHROPIC_API_KEY       # Should print the key value (non-empty)
```

For Vertex auth:

```bash
echo $CLAUDE_CODE_USE_VERTEX            # Should print 1
echo $ANTHROPIC_VERTEX_PROJECT_ID       # Should print the project ID
```

---

## Common pitfalls

| Mistake | Fix |
|---------|-----|
| Extension ID `anthropics.claude-code` (with trailing 's') | Use `anthropic.claude-code` -- the wrong ID fails silently |
| `npm install -g @anthropic-ai/claude-code` for CLI | Deprecated. Use `curl -fsSL https://claude.ai/install.sh \| bash` via `postCreateCommand` |
| CLI install via `onCreateCommand` | Use `postCreateCommand`, not `onCreateCommand` |
| Named volume for config (`type=volume`) | Use `type=bind` -- named volumes start empty and do not sync with the host |
| Shared `~/.claude` across projects | Use `~/.claude-<project-name>/data` per project for isolation |
| Missing `~/.claude.json` on host before build | The `initializeCommand` script must create it -- Docker single-file bind mount fails on missing source |
| Permission mode set in `settings.json` | Wrong file. Set `initialPermissionMode` in `claude.json` via `add_json_property` helper |
| `remoteUser` instead of `containerUser` | Use `containerUser` in devcontainer.json |
| Default user `vscode` | Use `appuser` as the default non-root username |
| PATH set in `remoteEnv` | Set PATH in the Dockerfile via `ENV PATH="/home/appuser/.local/bin:${PATH}"` |
| Adding a `postStartCommand` for extension install | Not needed -- declare the extension in `customizations.vscode.extensions` instead |
| First-time wizard on every rebuild | Mount `claude.json` pre-seeded by initialize script with `initialPermissionMode` |
| `claude` not found in PATH | Ensure `ENV PATH="/home/appuser/.local/bin:${PATH}"` is in the Dockerfile |
| Overwriting existing `postCreateCommand` | Chain commands with `&&` -- do not replace existing lifecycle commands |
| `initializeCommand` script not executable | Run `chmod +x .devcontainer/initialize.sh` |
| Bedrock auth fails inside container | Mount `~/.aws` readonly as a bind mount: `source=${localEnv:HOME}/.aws,target=/home/appuser/.aws,type=bind,readonly` |
| Missing `GITHUB_PERSONAL_ACCESS_TOKEN` | Forward via `remoteEnv`: `"GITHUB_PERSONAL_ACCESS_TOKEN": "${localEnv:GITHUB_PERSONAL_ACCESS_TOKEN}"` |
| Curl installer with `-y` flag | Do not pass `-y`. Use plain: `curl -fsSL https://claude.ai/install.sh \| bash` |
| Bedrock not working in VS Code extension | Add `"claude-code.apiProvider": "bedrock"` and `"claude-code.awsRegion"` to VS Code settings in devcontainer.json |

---

## File inventory

After this skill completes, the following files should be created or modified:

| File | Action | Purpose |
|------|--------|---------|
| `.devcontainer/devcontainer.json` | Modified | Added containerUser, mounts, remoteEnv, lifecycle commands, workspace mount, extension, settings |
| `.devcontainer/initialize.sh` | Created or modified | Host-side script to create per-project Claude config directories and set `initialPermissionMode` in claude.json |
| `.devcontainer/Dockerfile` | Possibly modified | Ensure `curl` is present and `ENV PATH` includes `~/.local/bin` |
| `scripts/setup-claude-code.sh` | Deleted (if present) | Superseded by two-script lifecycle and lifecycle commands |
