---
name: create-devcontainer-project
description: Scaffold a new project with a fully configured VS Code devcontainer for AI-driven development. Creates the project directory, Dockerfile, devcontainer.json, two lifecycle scripts (initialize_devcontainer.sh on the host, setup_devcontainer.sh via postCreateCommand), language-specific tooling, and .gitignore. Supports Bedrock or Anthropic API auth, OpenSpec, Beads, and language-specific tooling as configurable options. Use this whenever the user wants to start a new project, create a devcontainer, scaffold a project, or set up a development environment from scratch. Even if they just say "new project" or "start a project", this skill applies.
tools: Read, Edit, Write, Bash
---

# Create a New Devcontainer Project

This skill scaffolds a complete project with a VS Code devcontainer configured for AI-driven development. It runs on the **Docker host** (not inside a container) and generates THREE core files plus a Dockerfile:

- `.devcontainer/devcontainer.json`
- `.devcontainer/initialize_devcontainer.sh`
- `.devcontainer/setup_devcontainer.sh`
- `.devcontainer/Dockerfile`

The generated project uses a **two-script lifecycle** pattern. Scripts are generated with project-specific values baked in (not parameterized with flags). Use the plugin's `templates/` directory (`templates/add_json_property.sh`, `templates/Dockerfile.base`) as starting-point references.

---

## Step 1 -- Gather Project Details

Ask the user for these details. If they have already provided some, only ask for the missing ones.

1. **Project name** -- Used for the directory, workspace mount path, and Claude config isolation (e.g., `my-ml-project`)
2. **Bedrock or Anthropic?** -- AWS Bedrock (needs .aws mount, `CLAUDE_CODE_USE_BEDROCK=1`, VS Code settings) or Anthropic API key (simpler, just `ANTHROPIC_API_KEY`)
3. **Include OpenSpec?** -- If yes, adds Node.js to Dockerfile and openspec install to setup_devcontainer.sh
4. **Include Beads?** -- If yes, adds dolt + bd install to setup_devcontainer.sh
5. **Primary language** -- Determines Dockerfile packages and VS Code extensions. If Python, adds uv to Dockerfile. If not Python, no uv.

**Defaults** (use if the user does not specify):
- Authentication: **Bedrock**
- Include OpenSpec: **Yes**
- Include Beads: **Yes**
- Primary language: **Python**

---

## Step 2 -- Create Project Directory

```bash
PROJECT="<project-name>"
mkdir -p "${PROJECT}/.devcontainer"
cd "${PROJECT}"
git init
```

---

## Step 3 -- Generate Dockerfile

The Dockerfile has a `base` stage (system packages only) and a `devcontainer` stage. Language-specific and tool-specific blocks are ONLY added when requested.

### Base stage (always included):

```dockerfile
ARG APP_UID=1000
ARG APP_GID=1000

FROM ubuntu:22.04 AS base
ARG APP_UID
ARG APP_GID

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates sudo tar findutils jq less \
    && rm -rf /var/lib/apt/lists/*

# Non-root user setup (handles existing UID gracefully)
RUN groupadd -f -g $APP_GID appuser || true \
    && if id -u $APP_UID >/dev/null 2>&1; then \
        existing_user=$(id -un $APP_UID) && \
        if [ "$existing_user" != "appuser" ]; then \
            usermod -l appuser $existing_user && \
            groupmod -n appuser $(id -gn $APP_UID) 2>/dev/null || true; \
        fi; \
    else \
        useradd -m -u $APP_UID -g $APP_GID -s /bin/bash appuser; \
    fi \
    && echo "appuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/appuser \
    && chmod 0440 /etc/sudoers.d/appuser

WORKDIR /workspaces
CMD ["/bin/bash"]
```

### Devcontainer stage (always included):

```dockerfile
FROM base AS devcontainer
ARG APP_UID
ARG APP_GID

ENV PATH="/home/appuser/.local/bin:${PATH}"
```

### If Python requested -- add to devcontainer stage (before USER):

```dockerfile
RUN export UV_INSTALL_DIR=/usr/local/bin && curl -LsSf https://astral.sh/uv/install.sh | sh
```

### If OpenSpec requested -- add to devcontainer stage (before USER):

```dockerfile
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
```

### End of devcontainer stage (always last):

```dockerfile
USER appuser
```

### Language-specific system packages

Add to the base stage `apt-get install` or as separate layers depending on language:

**Python** -- add to the base stage `apt-get install` list:
```dockerfile
    python3 \
    python3-venv \
    python3-pip \
```

**C++** -- add a separate layer in the base stage:
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake gdb ninja-build pkg-config \
    && rm -rf /var/lib/apt/lists/*
```

**Go** -- add in the base stage:
```dockerfile
ARG GO_VERSION=1.22.0
RUN wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    && tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz" \
    && rm "go${GO_VERSION}.linux-amd64.tar.gz"
ENV PATH="/usr/local/go/bin:${PATH}"
```

**Rust** -- add in the devcontainer stage AFTER `USER appuser`:
```dockerfile
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/appuser/.cargo/bin:${PATH}"
```

**Node.js / TypeScript** -- uses the same NodeSource block as OpenSpec (add if not already present from OpenSpec).

---

## Step 4 -- Generate devcontainer.json

### Bedrock auth version:

```json
{
  "name": "PROJECT_NAME",
  "build": {"context": "..", "dockerfile": "Dockerfile", "target": "devcontainer"},
  "containerUser": "appuser",
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspaces/PROJECT_NAME,type=bind,consistency=cached",
  "workspaceFolder": "/workspaces/PROJECT_NAME",
  "initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize_devcontainer.sh",
  "postCreateCommand": "/bin/bash /workspaces/PROJECT_NAME/.devcontainer/setup_devcontainer.sh",
  "remoteEnv": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "us-west-2",
    "GITHUB_PERSONAL_ACCESS_TOKEN": "${localEnv:GITHUB_PERSONAL_ACCESS_TOKEN}"
  },
  "mounts": [
    "source=${localEnv:HOME}/.aws,target=/home/appuser/.aws,type=bind,readonly",
    "source=${localEnv:HOME}/.claude-PROJECT_NAME/data,target=/home/appuser/.claude,type=bind",
    "source=${localEnv:HOME}/.claude-PROJECT_NAME/claude.json,target=/home/appuser/.claude.json,type=bind"
  ],
  "customizations": {
    "vscode": {
      "extensions": ["anthropic.claude-code"],
      "settings": {
        "claude-code.apiProvider": "bedrock",
        "claude-code.awsRegion": "us-west-2"
      }
    }
  }
}
```

### Anthropic API key version -- differences from Bedrock:

- `remoteEnv`: Use `"ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}"` instead of `CLAUDE_CODE_USE_BEDROCK` and `AWS_REGION`
- `mounts`: No `.aws` mount (only the two Claude config mounts)
- `customizations.vscode.settings`: Empty object `{}` (no `apiProvider` or `awsRegion`)

### Language-specific VS Code extensions

Add to the `customizations.vscode.extensions` array as appropriate:

**Python**:
```json
"ms-python.python",
"ms-python.debugpy",
"ms-python.vscode-pylance"
```

**C++**:
```json
"ms-vscode.cpptools",
"ms-vscode.cmake-tools"
```

**Node.js / TypeScript**:
```json
"dbaeumer.vscode-eslint"
```

**Rust**:
```json
"rust-lang.rust-analyzer"
```

**Go**:
```json
"golang.go"
```

Replace `PROJECT_NAME` with the actual project name in all occurrences.

---

## Step 5 -- Generate initialize_devcontainer.sh

This script runs on the **HOST** before the container builds via `initializeCommand`. It creates bind-mount source paths and pre-seeds claude.json so Docker bind mounts work on first build.

Generate the script with `PROJECT_NAME` substituted throughout (the script is NOT parameterized -- the project name is baked in):

```bash
#!/bin/bash
# Initialize devcontainer environment before container build
# Creates persistence directories for Claude Code config

set -e

# Function to add a JSON property to a file
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

# Create Claude Code persistence directory
mkdir -p "${HOME}/.claude-PROJECT_NAME/data"

# Ensure claude.json exists (Docker bind mount requires source file to pre-exist)
CLAUDE_JSON="${HOME}/.claude-PROJECT_NAME/claude.json"
if [ ! -f "$CLAUDE_JSON" ]; then
    echo "{}" > "$CLAUDE_JSON"
fi

add_json_property "$CLAUDE_JSON" "initialPermissionMode" "bypassPermissions"
```

The `add_json_property` helper is sourced from the plugin's `templates/add_json_property.sh` as a starting point. It is inlined into the generated script so the project has no runtime dependency on the plugin.

---

## Step 6 -- Generate setup_devcontainer.sh

This script runs **INSIDE the container** via `postCreateCommand`. It installs ONLY the tools the user requested. The script is NOT parameterized with flags -- instead, generate a script with exactly the blocks needed based on user choices.

### Always included (start of script + Claude Code):

```bash
#!/bin/bash
# setup_devcontainer.sh: Post-create command for devcontainer
# See: devcontainer.json 'postCreateCommand'
echo "Running [setup_devcontainer.sh]..."
startDir="$(pwd)"

# Install Claude Code CLI
curl -fsSL https://claude.ai/install.sh | bash || echo 'WARNING: Claude Code install failed - continuing'
```

### If OpenSpec requested -- add this block:

```bash
# Configure npm to install global packages in user-writable directory
# This avoids EACCES errors when running as non-root (appuser)
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"

# Install OpenSpec
npm install -g @fission-ai/openspec@1.2.0
```

### If Beads requested -- add this block:

```bash
# Install dolt (database backend for beads) — pinned, bump manually when upgrading
mkdir -p "$HOME/.local/bin"
DOLT_VERSION=1.83.6
curl -fsSL "https://github.com/dolthub/dolt/releases/download/v${DOLT_VERSION}/dolt-linux-amd64.tar.gz" -o /tmp/dolt.tar.gz \
    && tar -xzf /tmp/dolt.tar.gz -C /tmp \
    && cp /tmp/dolt-linux-amd64/bin/dolt "$HOME/.local/bin/" \
    && rm -rf /tmp/dolt.tar.gz /tmp/dolt-linux-amd64

# Install beads (bd) — pinned, bump manually when upgrading
BD_VERSION=0.62.0
curl -fsSL "https://github.com/steveyegge/beads/releases/download/v${BD_VERSION}/beads_${BD_VERSION}_linux_amd64.tar.gz" -o /tmp/beads.tar.gz \
    && tar -xzf /tmp/beads.tar.gz -C "$HOME/.local/bin" bd \
    && rm /tmp/beads.tar.gz
```

### Always included (end of script):

```bash
# Return to starting directory
cd "${startDir}"
echo "Finished [setup_devcontainer.sh], returned to directory: $(pwd)"
```

---

## Step 7 -- Generate Supporting Files

### .gitignore

Combine language-specific patterns with AI development additions. Read the plugin's `templates/gitignore-additions.txt` for the AI-specific block.

Start with language-specific patterns:

**Python**:
```
.venv/
__pycache__/
*.pyc
*.egg-info/
dist/
build/
```

**C++**:
```
build/
*.o
*.so
*.a
.cache/
compile_commands.json
```

**Node.js / TypeScript**:
```
node_modules/
dist/
```

**Rust**:
```
target/
```

**Go**:
```
bin/
```

Then append the AI development additions block:
```
# === AI-Driven Development ===

# Claude Code
.claude/settings.local.json
.claude/.credentials.json

# Beads (local database)
# .beads/

# OpenSpec (generated artifacts)
# openspec-output/

# Python (uv)
.venv/
__pycache__/
*.pyc
.python-version

# Node
node_modules/

# IDE
.vscode/.ropeproject
*.code-workspace

# OS
.DS_Store
Thumbs.db

# Secrets
.env
.env.*

# Docker
.dockerignore.local
```

If Beads is included, uncomment the `.beads/` line.

### .dockerignore

```
.git/
.venv/
__pycache__/
*.pyc
node_modules/
dist/
build/
target/
.env
.env.*
.beads/
```

### CLAUDE.md

Create a minimal project-level instructions file:

```markdown
# <project-name>

## Development Environment

This project uses a VS Code devcontainer for development. Open in VS Code and select "Reopen in Container".

## Tools Available

- Claude Code CLI (`claude`)
```

If Python, add: `- uv (Python package manager)`
If Beads is included, add: `- Beads (`bd`) -- graph-based issue tracker`
If OpenSpec is included, add: `- OpenSpec (`openspec`) -- specification management`

### Language-specific files

**Python**:
- `pyproject.toml`:
  ```toml
  [project]
  name = "<project-name>"
  version = "0.1.0"
  requires-python = ">=3.10"
  dependencies = []
  ```

**C++**:
- `CMakeLists.txt`:
  ```cmake
  cmake_minimum_required(VERSION 3.20)
  project(<project-name> LANGUAGES CXX)
  set(CMAKE_CXX_STANDARD 17)
  set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
  ```
- `src/main.cpp`:
  ```cpp
  #include <iostream>
  int main() {
      std::cout << "Hello from <project-name>" << std::endl;
      return 0;
  }
  ```

**Node.js / TypeScript**:
- Run `npm init -y` in the project directory
- If TypeScript, create `tsconfig.json`:
  ```json
  {
    "compilerOptions": {
      "target": "ES2022",
      "module": "node16",
      "moduleResolution": "node16",
      "outDir": "./dist",
      "rootDir": "./src",
      "strict": true,
      "esModuleInterop": true
    },
    "include": ["src/**/*"]
  }
  ```

**Rust**:
- Create `Cargo.toml` and `src/main.rs` manually (cargo is not available on the host)

**Go**:
- `go.mod`:
  ```
  module <project-name>

  go 1.22
  ```
- `main.go`:
  ```go
  package main

  import "fmt"

  func main() {
      fmt.Println("Hello from <project-name>")
  }
  ```

---

## Step 8 -- Git Init and Commit

```bash
cd <project-name>
git add -A
git commit -m "Initial project scaffold with devcontainer and Claude Code integration"
```

---

## Step 9 -- Next Steps

Tell the user:

```
Project "<project-name>" is ready.

To start development:

1. Open the project folder in VS Code:
   code <project-name>

2. When prompted, select "Reopen in Container"
   (or Ctrl+Shift+P -> "Dev Containers: Reopen in Container")

3. Wait for the container to build and set up. The lifecycle scripts will:
   - Create Claude config directories on your host (initialize_devcontainer.sh)
   - Install tools inside the container (setup_devcontainer.sh)

4. Claude Code will be available in the VS Code sidebar and terminal.
```

If Beads was included:
```
Beads is installed. After the container starts, run in the terminal:
  bd init
  bd setup claude --project
```

If OpenSpec was included:
```
OpenSpec is installed. Initialize a spec with:
  openspec init
```

---

## Common Pitfalls

| Mistake | Fix |
|---------|-----|
| Extension ID `anthropics.claude-code` (with 's') | Correct ID is `anthropic.claude-code` (no 's') |
| Installing Claude Code via npm | Use `curl -fsSL https://claude.ai/install.sh \| bash` in setup_devcontainer.sh |
| Node.js added when not needed | Node.js is ONLY added to the Dockerfile when OpenSpec is requested |
| uv added when not Python | uv is ONLY added to the Dockerfile when Python is the primary language |
| Dolt installed via `install.sh` | Use direct tarball download to `~/.local/bin` in setup_devcontainer.sh, NOT via `install.sh` |
| Beads `install.sh` in Docker | Known ANSI escape code bug in `detect_platform()`. Use direct binary download: `curl ... beads_0.62.0_linux_amd64.tar.gz` |
| BD_VERSION or beads URL wrong | BD_VERSION is `0.62.0`, GitHub URL is `steveyegge/beads` (not `fission-codes/beads`) |
| `initialPermissionMode` in settings.json | Set `initialPermissionMode` in `claude.json` via `add_json_property`, NOT in `settings.json` |
| Docker bind mount fails on first build | `initialize_devcontainer.sh` MUST create all host-side source paths before container builds. Docker bind mounts FAIL if source file/directory does not exist. |
| Using `remoteUser` instead of `containerUser` | Use `"containerUser": "appuser"`, not `"remoteUser": "vscode"` |
| Bedrock auth missing VS Code settings | Bedrock needs BOTH the `.aws` bind mount AND `claude-code.apiProvider`/`claude-code.awsRegion` in VS Code settings |
| Anthropic auth with Bedrock settings | Anthropic API key auth only needs `ANTHROPIC_API_KEY` in `remoteEnv` -- no `.aws` mount, no VS Code provider settings |
| Named volume for config (`type=volume`) | Use `type=bind`. Named volumes start empty and don't sync with host. |
| Shared `~/.claude` across projects | Use `~/.claude-<project>/data` per project for isolation |
| `claude` not found in PATH | Set `ENV PATH="/home/appuser/.local/bin:${PATH}"` in the Dockerfile, NOT in `remoteEnv` |
| Workspace path uses `/workspace/` (singular) | Use `/workspaces/<project-name>` (plural: `/workspaces/`) |
| OpenSpec npm install fails as non-root | Use the npm global prefix trick: `mkdir -p ~/.npm-global && npm config set prefix ~/.npm-global` then add `~/.npm-global/bin` to PATH |
| Distro nodejs too old for OpenSpec | Use NodeSource `setup_22.x`, not `apt-get install nodejs` which gives v12 on Ubuntu 22.04 |
| Setup script parameterized with flags | Do NOT use `--flags`. Generate setup_devcontainer.sh with exactly the blocks needed -- no flag parsing |
| Three scripts with post-start.sh | There is NO post-start.sh. Use only two scripts: initialize_devcontainer.sh (host) and setup_devcontainer.sh (postCreateCommand) |
