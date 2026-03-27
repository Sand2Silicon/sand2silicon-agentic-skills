---
name: create-devcontainer-project
description: Scaffold a new project with a fully configured VS Code devcontainer for AI-driven development. Creates the project directory, Dockerfile, devcontainer.json, two lifecycle scripts (initialize.sh on the host, setup.sh via postCreateCommand), language-specific tooling, and .gitignore. Supports Claude Code, uv, Beads, and OpenSpec as optional components. Use this whenever the user wants to start a new project, create a devcontainer, scaffold a project, or set up a development environment from scratch. Even if they just say "new project" or "start a project", this skill applies.
tools: Read, Edit, Write, Bash
---

# Create a New Devcontainer Project

This skill scaffolds a complete project with a VS Code devcontainer configured for AI-driven development. It runs on the **Docker host** (not inside a container) and creates a project directory with everything needed to open in VS Code and start coding immediately.

The generated project uses a **two-script lifecycle** pattern with shared scripts from this plugin as starting points. Scripts are COPIED into the project (not symlinked) with project-specific values baked in.

## Architecture Overview

```
<project-name>/
├── .devcontainer/
│   ├── Dockerfile           # Multi-stage: system packages, uv, Node.js only
│   ├── devcontainer.json    # Mounts, env vars, lifecycle commands, extensions
│   ├── initialize.sh        # HOST-side: creates bind-mount source paths, pre-seeds claude.json
│   └── setup.sh             # CONTAINER (postCreateCommand): installs Claude CLI, dolt, bd, openspec
├── .gitignore
├── .dockerignore
├── CLAUDE.md                # Minimal project instructions for Claude Code
└── <language-specific files>
```

**Two-script lifecycle**:

| Script | Runs where | Triggered by | Purpose |
|--------|-----------|--------------|---------|
| `initialize.sh` | Docker HOST | `initializeCommand` | Create bind-mount source paths, pre-seed claude.json with `initialPermissionMode` |
| `setup.sh` | Inside container | `postCreateCommand` | Install ALL user-space tools: Claude CLI, dolt, bd, openspec, uv |

**Key principle**: The Dockerfile ONLY contains system packages, uv (system-wide via `UV_INSTALL_DIR=/usr/local/bin`), and Node.js (via NodeSource). ALL other tools (Claude Code, dolt, beads/bd, openspec) are installed by `setup.sh` running as `postCreateCommand` -- NOT in the Dockerfile, NOT in `onCreateCommand`.

---

## Step 1 -- Gather Project Details

Ask the user for these details. If they have already provided some, only ask for the missing ones.

1. **Project name** -- Used for the directory, devcontainer name, and Claude config isolation (e.g., `my-ml-project`)
2. **Primary language(s)** -- Python, C++, Node.js/TypeScript, Rust, Go, etc. Determines Dockerfile packages and VS Code extensions
3. **GPU support?** -- Yes/No. Determines base Docker image (CUDA vs plain Ubuntu)
4. **Authentication method** -- How Claude Code authenticates:
   - **API key** (default) -- passes `ANTHROPIC_API_KEY` from host env
   - **AWS Bedrock** -- sets `CLAUDE_CODE_USE_BEDROCK=1` plus AWS env vars, mounts `~/.aws`
   - **Google Vertex** -- sets `CLAUDE_CODE_USE_VERTEX=1` plus GCP env vars
5. **Permission mode** -- Claude Code's initial permission level (set in claude.json via `initialPermissionMode`):
   - `bypassPermissions` (default for devcontainers) -- skips all prompts (fully autonomous)
   - `acceptEdits` -- auto-accepts file edits
   - `default` -- prompts for permission on first use of each tool
   - `plan` -- read-only analysis mode
   - `dontAsk` -- auto-denies unless pre-approved
6. **Include Beads?** -- Yes/No. Adds dolt + bd CLI install to setup.sh
7. **Include OpenSpec?** -- Yes/No. Adds OpenSpec npm install to setup.sh (requires Node.js in Dockerfile)

Use these defaults if the user does not specify:
- Authentication: API key
- Permission mode: bypassPermissions
- Beads: No
- OpenSpec: No

---

## Step 2 -- Create Project Directory Structure

```bash
PROJECT="<project-name>"
mkdir -p "${PROJECT}/.devcontainer"
cd "${PROJECT}"
git init
```

---

## Step 3 -- Generate Dockerfile

Build the Dockerfile based on the user's choices. Use the plugin's template at `plugins/sdd-setup/templates/Dockerfile.base` as a reference, but generate a clean file tailored to the project.

The Dockerfile uses a **multi-stage build** with `FROM base AS devcontainer`. The `# syntax=docker/dockerfile:1` BuildKit header **must be line 1** when using `--mount=type=cache`.

### Base Dockerfile (always included)

```dockerfile
# syntax=docker/dockerfile:1
# ============================================================================
# Devcontainer Dockerfile -- <project-name>
# ============================================================================

# Base image
ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE} AS base

# Prevent interactive prompts during package install
ENV DEBIAN_FRONTEND=noninteractive

# ============================================================================
# Core system packages
# ============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    sudo \
    wget \
    unzip \
    jq \
    tar \
    findutils \
    openssh-client \
    less \
    && rm -rf /var/lib/apt/lists/*

# ============================================================================
# uv -- Fast Python package manager (system-wide)
# ============================================================================
RUN export UV_INSTALL_DIR=/usr/local/bin && curl -LsSf https://astral.sh/uv/install.sh | sh
```

### GPU variant

If GPU support is requested, change the `BASE_IMAGE` default:

```dockerfile
ARG BASE_IMAGE=nvidia/cuda:12.1.0-runtime-ubuntu22.04
```

### Language-specific system packages

Append to the core `apt-get install` or add a new layer depending on the language:

**Python** -- add to the core `apt-get install` list:
```dockerfile
    python3 \
    python3-venv \
    python3-pip \
```

**C++** -- add a separate layer after core:
```dockerfile
# C++ build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    gdb \
    ninja-build \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*
```

**Go** -- add after core (pin a specific version):
```dockerfile
# Go
ARG GO_VERSION=1.22.0
RUN wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
    && tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz" \
    && rm "go${GO_VERSION}.linux-amd64.tar.gz"
ENV PATH="/usr/local/go/bin:${PATH}"
```

**Rust** -- installed as appuser after `USER` directive (see below).

**Node.js / TypeScript** -- add the NodeSource block (also required if OpenSpec is included):
```dockerfile
# Node.js LTS via NodeSource (required for npm global tools)
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
```

### Non-root user setup and devcontainer stage (always last)

```dockerfile
# ============================================================================
# Non-root user setup
# ============================================================================
ARG USERNAME=appuser
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

RUN groupadd -f -g ${USER_GID} ${USERNAME} || true \
    && if id -u ${USER_UID} >/dev/null 2>&1; then \
        existing_user=$(id -un ${USER_UID}) && \
        if [ "$existing_user" != "${USERNAME}" ]; then \
            usermod -l ${USERNAME} $existing_user && \
            groupmod -n ${USERNAME} $(id -gn ${USER_UID}) 2>/dev/null || true; \
        fi; \
    else \
        useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash ${USERNAME}; \
    fi \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && mkdir -p /workspaces \
    && chown -R ${USERNAME}:${USERNAME} /workspaces

# Set PATH in Dockerfile ENV (NOT in remoteEnv)
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

WORKDIR /workspaces
CMD ["/bin/bash"]

# ============================================================================
# Devcontainer stage
# ============================================================================
FROM base AS devcontainer
ARG USERNAME=appuser

USER ${USERNAME}

# NOTE: User-space tools are installed by setup.sh (postCreateCommand):
#   Claude Code CLI -> ~/.local/bin/claude
#   Dolt            -> ~/.local/bin/dolt
#   Beads (bd)      -> ~/.local/bin/bd
#   OpenSpec        -> ~/.npm-global/bin/openspec
```

**Rust** (if selected) -- add after the `USER` directive in the devcontainer stage:
```dockerfile
# Rust toolchain (installed as appuser)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/appuser/.cargo/bin:${PATH}"
```

---

## Step 4 -- Generate devcontainer.json

Use the plugin's template at `plugins/sdd-setup/templates/devcontainer.json.tmpl` as a reference. Generate a clean JSON file with project-specific values substituted.

### Base structure

```jsonc
{
  "name": "<project-name>",
  "build": {
    "dockerfile": "Dockerfile",
    "context": "..",
    "target": "devcontainer"
  },

  // Container user (must match Dockerfile ARG USERNAME)
  "containerUser": "appuser",

  // Workspace mount -- note /workspaces/ (plural)
  "workspaceMount": "source=${localWorkspaceFolder},target=/workspaces/<project-name>,type=bind,consistency=cached",
  "workspaceFolder": "/workspaces/<project-name>",

  // Per-project Claude config isolation
  "mounts": [
    "source=${localEnv:HOME}/.claude-<project-name>/data,target=/home/appuser/.claude,type=bind",
    "source=${localEnv:HOME}/.claude-<project-name>/claude.json,target=/home/appuser/.claude.json,type=bind"
  ],

  // Environment
  "remoteEnv": {
    "GITHUB_PERSONAL_ACCESS_TOKEN": "${localEnv:GITHUB_PERSONAL_ACCESS_TOKEN}"
  },

  // Lifecycle commands -- two-script pattern
  "initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize.sh <project-name>",
  "postCreateCommand": "/bin/bash /workspaces/<project-name>/.devcontainer/setup.sh --claude --uv",

  // VS Code customizations
  "customizations": {
    "vscode": {
      "extensions": [
        "anthropic.claude-code"
      ],
      "settings": {}
    }
  }
}
```

### Authentication env vars

Add to `remoteEnv` based on the user's chosen method:

**API key** (default):
```jsonc
    "ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}"
```

**AWS Bedrock** -- add to `remoteEnv`, add AWS mount, and add VS Code settings:
```jsonc
// remoteEnv additions:
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "us-west-2"

// Add to mounts array:
    "source=${localEnv:HOME}/.aws,target=/home/appuser/.aws,type=bind,readonly"

// Add to customizations.vscode.settings:
    "claude-code.apiProvider": "bedrock",
    "claude-code.awsRegion": "us-west-2"
```

**Google Vertex**:
```jsonc
    "CLAUDE_CODE_USE_VERTEX": "1",
    "CLOUD_ML_REGION": "us-east5",
    "ANTHROPIC_VERTEX_PROJECT_ID": "${localEnv:ANTHROPIC_VERTEX_PROJECT_ID}"
```

### GPU support

If GPU is requested, add:
```jsonc
  "runArgs": ["--gpus", "all"],
```

### initializeCommand flags

Customize the `initializeCommand` based on user choices:

```jsonc
  "initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize.sh <project-name>"
```

If a custom permission mode is specified (the default is `bypassPermissions`):
```jsonc
  "initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize.sh <project-name> --permissions-mode <mode>"
```

### postCreateCommand flags

Build the `setup.sh` flags based on selected tools:

- Always include: `--claude --uv`
- If Beads: add `--beads`
- If OpenSpec: add `--openspec`

Example with all tools:
```jsonc
  "postCreateCommand": "/bin/bash /workspaces/<project-name>/.devcontainer/setup.sh --claude --uv --beads --openspec"
```

Or use `--all` as a shortcut:
```jsonc
  "postCreateCommand": "/bin/bash /workspaces/<project-name>/.devcontainer/setup.sh --all"
```

### Language-specific VS Code extensions

Add to `customizations.vscode.extensions`:

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

---

## Step 5 -- Generate Supporting Files

### .gitignore

Combine language-specific ignores with AI development additions. Use the plugin's template at `plugins/sdd-setup/templates/gitignore-additions.txt` as the AI-specific section.

Start with language-specific patterns, then append the AI development block:

**Language-specific patterns**:

Python:
```
.venv/
__pycache__/
*.pyc
*.egg-info/
dist/
build/
```

C++:
```
build/
*.o
*.so
*.a
.cache/
compile_commands.json
```

Node.js / TypeScript:
```
node_modules/
dist/
```

Rust:
```
target/
```

Go:
```
bin/
```

**AI development additions (always append)**:
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
- uv (Python package manager)
```

If Beads is included, add:
```markdown
- Beads (`bd`) -- graph-based issue tracker
```

If OpenSpec is included, add:
```markdown
- OpenSpec (`openspec`) -- specification management
```

### Language-specific files

**Python**:
- `requirements.txt` -- empty file
- `pyproject.toml` -- minimal if using uv:
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
- If TypeScript: also create `tsconfig.json`:
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
- Create `go.mod`:
  ```
  module <project-name>

  go 1.22
  ```
- Create `main.go`:
  ```go
  package main

  import "fmt"

  func main() {
      fmt.Println("Hello from <project-name>")
  }
  ```

---

## Step 6 -- Generate initialize.sh (project-specific)

Copy the plugin's shared script from `plugins/sdd-setup/scripts/initialize.sh` into `.devcontainer/initialize.sh`. The script is parameterized and takes the project name as the first argument, so it works as-is when called from `initializeCommand`.

```bash
# Read the plugin's initialize.sh template
# Copy it to .devcontainer/initialize.sh
# Make it executable
chmod +x .devcontainer/initialize.sh
```

The `initializeCommand` in devcontainer.json already passes the project name and options:

```jsonc
"initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize.sh <project-name>"
```

The full contents of `initialize.sh` (copy from plugin scripts):

```bash
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
```

---

## Step 7 -- Generate setup.sh

Copy from the plugin's `plugins/sdd-setup/scripts/setup.sh` into `.devcontainer/setup.sh`. The script is parameterized via flags so it works as-is.

```bash
chmod +x .devcontainer/setup.sh
```

The `postCreateCommand` in devcontainer.json passes the appropriate flags:

```jsonc
"postCreateCommand": "/bin/bash /workspaces/<project-name>/.devcontainer/setup.sh --claude --uv --beads --openspec"
```

The full contents of `setup.sh` (copy from plugin scripts):

```bash
#!/usr/bin/env bash
# setup.sh — Runs INSIDE the container after creation.
# Called via devcontainer.json "postCreateCommand".
#
# Purpose:
#   Install user-space development tools that aren't baked into the Dockerfile.
#   These install to ~/.local/bin (Claude, dolt, bd) or ~/.npm-global (openspec)
#   so they work as a non-root container user.
#
# Usage:
#   ./setup.sh [--claude] [--beads] [--openspec] [--uv] [--all]
#
# Each flag installs/configures the named tool. --all enables everything.
# With no flags, only basic environment setup is performed.
#
# Versions are pinned here — bump manually when upgrading.
#
set -euo pipefail

# --- Pinned versions ---
DOLT_VERSION="${DOLT_VERSION:-1.83.6}"
BD_VERSION="${BD_VERSION:-0.62.0}"
OPENSPEC_VERSION="${OPENSPEC_VERSION:-1.2.0}"

# --- Feature flags ---
INSTALL_CLAUDE=false
INSTALL_BEADS=false
INSTALL_OPENSPEC=false
INSTALL_UV=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --claude)   INSTALL_CLAUDE=true; shift ;;
    --beads)    INSTALL_BEADS=true; shift ;;
    --openspec) INSTALL_OPENSPEC=true; shift ;;
    --uv)       INSTALL_UV=true; shift ;;
    --all)      INSTALL_CLAUDE=true; INSTALL_BEADS=true; INSTALL_OPENSPEC=true; INSTALL_UV=true; shift ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "=== Devcontainer setup ==="
echo "Claude: $INSTALL_CLAUDE | Beads: $INSTALL_BEADS | OpenSpec: $INSTALL_OPENSPEC | uv: $INSTALL_UV"
echo ""

# --- Ensure ~/.local/bin exists and is on PATH ---
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# --- Helper: check if command exists ---
has() { command -v "$1" &>/dev/null; }

# =========================================================================
# 1. Claude Code CLI
# =========================================================================
if [[ "$INSTALL_CLAUDE" == "true" ]]; then
  echo "[claude] Installing Claude Code CLI..."
  if has claude; then
    echo "  Already installed: $(claude --version 2>/dev/null || echo 'unknown version')"
  else
    curl -fsSL https://claude.ai/install.sh | bash || echo 'WARNING: Claude Code install failed - continuing'
    echo "  Installed: $(claude --version 2>/dev/null || echo 'check manually')"
  fi
  # Ensure PATH persistence in .bashrc
  if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo "  Added ~/.local/bin to .bashrc PATH"
  fi
  echo ""
fi

# =========================================================================
# 2. uv (Python package manager)
# =========================================================================
if [[ "$INSTALL_UV" == "true" ]]; then
  echo "[uv] Installing uv..."
  if has uv; then
    echo "  Already installed: $(uv --version 2>/dev/null)"
  else
    curl -LsSf https://astral.sh/uv/install.sh | sh
    echo "  Installed: $(uv --version 2>/dev/null || echo 'check manually')"
  fi
  echo ""
fi

# =========================================================================
# 3. OpenSpec (requires Node.js + npm in the Dockerfile)
# =========================================================================
if [[ "$INSTALL_OPENSPEC" == "true" ]]; then
  echo "[openspec] Installing OpenSpec v${OPENSPEC_VERSION}..."

  if ! has npm; then
    echo "  ERROR: npm not found. Node.js must be installed in the Dockerfile first."
    echo "  See the add-openspec-to-project skill for Dockerfile instructions."
  elif has openspec; then
    echo "  Already installed: $(openspec --version 2>/dev/null || echo 'available')"
  else
    # Configure npm to install global packages in a user-writable directory.
    # This avoids EACCES errors when running as non-root user.
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"
    export PATH="$HOME/.npm-global/bin:$PATH"
    if ! grep -q '\.npm-global/bin' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    npm install -g @fission-ai/openspec@${OPENSPEC_VERSION}
    echo "  Installed: openspec@${OPENSPEC_VERSION}"
  fi
  echo ""
fi

# =========================================================================
# 4. Dolt + Beads (bd CLI)
# =========================================================================
if [[ "$INSTALL_BEADS" == "true" ]]; then
  echo "[dolt] Installing Dolt v${DOLT_VERSION}..."
  if has dolt; then
    echo "  Already installed: $(dolt version 2>/dev/null | head -1 || echo 'available')"
  else
    # Direct tarball download to ~/.local/bin (user-space, no root needed)
    curl -fsSL "https://github.com/dolthub/dolt/releases/download/v${DOLT_VERSION}/dolt-linux-amd64.tar.gz" -o /tmp/dolt.tar.gz \
        && tar -xzf /tmp/dolt.tar.gz -C /tmp \
        && cp /tmp/dolt-linux-amd64/bin/dolt "$HOME/.local/bin/" \
        && rm -rf /tmp/dolt.tar.gz /tmp/dolt-linux-amd64
    echo "  Installed: dolt v${DOLT_VERSION} to ~/.local/bin/"
  fi
  echo ""

  # --- Beads (bd CLI) ---
  echo "[beads] Installing Beads v${BD_VERSION}..."
  if has bd; then
    echo "  Already installed: $(bd --version 2>/dev/null || echo 'available')"
  else
    # Direct binary download — do NOT use upstream install.sh in Docker
    # (known bug: ANSI escape codes in detect_platform() corrupt the download URL)
    curl -fsSL "https://github.com/steveyegge/beads/releases/download/v${BD_VERSION}/beads_${BD_VERSION}_linux_amd64.tar.gz" -o /tmp/beads.tar.gz \
        && tar -xzf /tmp/beads.tar.gz -C "$HOME/.local/bin" bd \
        && rm /tmp/beads.tar.gz
    echo "  Installed: bd v${BD_VERSION} to ~/.local/bin/"
  fi
  echo ""
fi

# =========================================================================
# 5. Fix executable permissions (lost on container rebuild)
# =========================================================================
echo "[permissions] Fixing executable bits on scripts and hooks..."
find .devcontainer -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
if [[ -d ".beads/hooks" ]]; then
  find .beads/hooks -type f -exec chmod +x {} \; 2>/dev/null || true
fi
find scripts -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
echo "  Done."
echo ""

# =========================================================================
# 6. Git safe directory (bind-mounted repos trigger ownership check)
# =========================================================================
echo "[git] Configuring git safe directories..."
WORKSPACE="$(pwd)"
git config --global --add safe.directory "$WORKSPACE" 2>/dev/null || true
echo "  Added $WORKSPACE as safe directory."
echo ""

echo "=== Setup complete ==="
```

---

## Step 8 -- Initial Git Commit

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
   - Create Claude config directories on your host (initialize.sh)
   - Install Claude Code CLI, dolt, bd, openspec inside the container (setup.sh)

4. Claude Code will be available in the VS Code sidebar and terminal.

If the container build fails, use the builder agent to diagnose:
  @builder help me fix the devcontainer build
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

## Complete Example -- Python project with all options

For a project named `my-ml-project` with Python, GPU, Bedrock auth, bypassPermissions mode, Beads, and OpenSpec:

### .devcontainer/Dockerfile

```dockerfile
# syntax=docker/dockerfile:1
# ============================================================================
# Devcontainer Dockerfile -- my-ml-project
# ============================================================================

ARG BASE_IMAGE=nvidia/cuda:12.1.0-runtime-ubuntu22.04
FROM ${BASE_IMAGE} AS base

ENV DEBIAN_FRONTEND=noninteractive

# Core + Python system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    ca-certificates \
    sudo \
    wget \
    unzip \
    jq \
    tar \
    findutils \
    openssh-client \
    less \
    python3 \
    python3-venv \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# uv (system-wide)
RUN export UV_INSTALL_DIR=/usr/local/bin && curl -LsSf https://astral.sh/uv/install.sh | sh

# Node.js LTS (required for OpenSpec)
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Non-root user
ARG USERNAME=appuser
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

RUN groupadd -f -g ${USER_GID} ${USERNAME} || true \
    && if id -u ${USER_UID} >/dev/null 2>&1; then \
        existing_user=$(id -un ${USER_UID}) && \
        if [ "$existing_user" != "${USERNAME}" ]; then \
            usermod -l ${USERNAME} $existing_user && \
            groupmod -n ${USERNAME} $(id -gn ${USER_UID}) 2>/dev/null || true; \
        fi; \
    else \
        useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash ${USERNAME}; \
    fi \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME} \
    && mkdir -p /workspaces \
    && chown -R ${USERNAME}:${USERNAME} /workspaces

ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

WORKDIR /workspaces
CMD ["/bin/bash"]

# Devcontainer stage
FROM base AS devcontainer
ARG USERNAME=appuser
USER ${USERNAME}
```

### .devcontainer/devcontainer.json

```jsonc
{
  "name": "my-ml-project",
  "build": {
    "dockerfile": "Dockerfile",
    "context": "..",
    "target": "devcontainer"
  },

  "containerUser": "appuser",

  "workspaceMount": "source=${localWorkspaceFolder},target=/workspaces/my-ml-project,type=bind,consistency=cached",
  "workspaceFolder": "/workspaces/my-ml-project",

  "mounts": [
    "source=${localEnv:HOME}/.claude-my-ml-project/data,target=/home/appuser/.claude,type=bind",
    "source=${localEnv:HOME}/.claude-my-ml-project/claude.json,target=/home/appuser/.claude.json,type=bind",
    "source=${localEnv:HOME}/.aws,target=/home/appuser/.aws,type=bind,readonly"
  ],

  "runArgs": ["--gpus", "all"],

  "remoteEnv": {
    "CLAUDE_CODE_USE_BEDROCK": "1",
    "AWS_REGION": "us-west-2",
    "GITHUB_PERSONAL_ACCESS_TOKEN": "${localEnv:GITHUB_PERSONAL_ACCESS_TOKEN}"
  },

  "initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize.sh my-ml-project",
  "postCreateCommand": "/bin/bash /workspaces/my-ml-project/.devcontainer/setup.sh --all",

  "customizations": {
    "vscode": {
      "extensions": [
        "anthropic.claude-code",
        "ms-python.python",
        "ms-python.debugpy",
        "ms-python.vscode-pylance"
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

## Common Pitfalls

| Mistake | Fix |
|---------|-----|
| BuildKit `--mount` fails | `# syntax=docker/dockerfile:1` must be line 1 of Dockerfile |
| Bind mount fails on first build | `initialize.sh` must create all host-side source paths before container builds. Docker bind mounts FAIL if source does not exist. |
| Extension ID `anthropics.claude-code` (with 's') | Correct ID is `anthropic.claude-code` (no 's') |
| Installing Claude Code via npm | Deprecated. Use `curl -fsSL https://claude.ai/install.sh \| bash` in setup.sh |
| Installing Claude Code in Dockerfile | Claude CLI installs to `~/.local/bin` (user-space). Install in setup.sh via postCreateCommand, not Dockerfile. |
| Installing dolt/bd/openspec in Dockerfile | These are user-space tools. Install them in setup.sh (postCreateCommand), not in the Dockerfile. |
| Beads `install.sh` fails in Docker | Known ANSI escape code bug. Use direct binary download in setup.sh instead. |
| BD_VERSION or beads URL wrong | BD_VERSION is `0.62.0`, GitHub URL is `steveyegge/beads` (not `fission-codes/beads`) |
| Using `onCreateCommand` for setup.sh | Use `postCreateCommand`, not `onCreateCommand`. The ground truth pattern is postCreateCommand. |
| Named volume for config (`type=volume`) | Use `type=bind`. Named volumes start empty and don't sync with host. |
| Shared `~/.claude` across projects | Use `~/.claude-<project>/data` per project for isolation. |
| `claude` not found in PATH | Set `ENV PATH="/home/appuser/.local/bin:${PATH}"` in the Dockerfile, NOT in `remoteEnv`. |
| Using `remoteUser` instead of `containerUser` | Use `"containerUser": "appuser"`, not `"remoteUser": "vscode"`. |
| USERNAME=vscode | The default username is `appuser`, not `vscode`. |
| Workspace path uses `/workspace/` (singular) | Use `/workspaces/<project-name>` (plural: `/workspaces/`). |
| `initialPermissionMode` in settings.json | Set `initialPermissionMode` in `claude.json` via `add_json_property`, NOT in `settings.json`. |
| OpenSpec npm install fails as non-root | Use the npm global prefix trick: `mkdir -p ~/.npm-global && npm config set prefix ~/.npm-global` then add `~/.npm-global/bin` to PATH. |
| Distro nodejs too old for OpenSpec | Use NodeSource `setup_22.x`, not `apt-get install nodejs` which gives v12 on Ubuntu 22.04. |
| Floating versions in Dockerfile | Pin all tool versions via `ARG` for reproducible, cache-friendly builds. |
| Three scripts with post-start.sh | There is NO post-start.sh. Use only two scripts: initialize.sh (host) and setup.sh (postCreateCommand). |
| Dolt installed via `install.sh` pipe | Use direct tarball download to `~/.local/bin` in setup.sh: `curl ... dolt-linux-amd64.tar.gz` |
