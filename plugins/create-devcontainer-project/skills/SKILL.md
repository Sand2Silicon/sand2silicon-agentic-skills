---
name: create-devcontainer-project
description: Scaffold a new project with a fully configured VS Code devcontainer, including Claude Code integration. Creates the project directory, Dockerfile, devcontainer.json, initialization scripts, language-specific tooling, and .gitignore. Use this whenever the user wants to start a new project, create a devcontainer, scaffold a project, or set up a development environment from scratch. Even if they just say "new project" or "start a project", this skill applies.
tools: Read, Edit, Write, Bash
---

# Create a New Devcontainer Project

This skill scaffolds a complete project with a VS Code devcontainer, Claude Code integration, and language-appropriate tooling. The target environment is WSL2 on Linux/Windows.

## Gather project details

If the user hasn't provided these in their prompt, ask before proceeding:

1. **Project name** — used for the directory, devcontainer name, and Claude config isolation
2. **GPU support** — yes/no. Determines base Docker image (CUDA vs plain Ubuntu)
3. **Primary language** — Python, C++, Node.js/TypeScript, Rust, Go, etc.

Do not ask more than these three questions. Use sensible defaults for everything else.

---

## Project structure to generate

```
<project-name>/
├── .devcontainer/
│   ├── devcontainer.json
│   ├── Dockerfile
│   └── initialize_devcontainer.sh
├── .gitignore
├── README.md
├── scripts/
│   └── setup-claude-code.sh
└── <language-specific files>
```

---

## Step 1 — Create the project directory

```bash
mkdir -p <project-name>/.devcontainer <project-name>/scripts
cd <project-name>
git init
```

---

## Step 2 — Generate the Dockerfile

### Base image

- **GPU**: `nvidia/cuda:12.1.0-runtime-ubuntu22.04`
- **No GPU**: `ubuntu:22.04`

### Core packages (always install)

Every devcontainer should include these regardless of language, because many tools and language servers install through them:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git curl ca-certificates sudo wget unzip \
       python3 python3-pip python3-venv \
       nodejs npm \
    && rm -rf /var/lib/apt/lists/*

# Install uv (fast Python package manager, used by many tools)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Language-specific additions

**Python** — no extra apt packages needed (python3 already in core). Add after core:
```dockerfile
# Nothing extra — Python is in the base install
```

**C++** — add build tools:
```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       build-essential cmake gdb ninja-build pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Install vcpkg
RUN git clone https://github.com/microsoft/vcpkg.git /opt/vcpkg \
    && /opt/vcpkg/bootstrap-vcpkg.sh
ENV VCPKG_ROOT=/opt/vcpkg
ENV PATH="${VCPKG_ROOT}:${PATH}"
```

**Node.js / TypeScript** — no extra apt packages needed (nodejs/npm already in core).

**Rust** — add rustup:
```dockerfile
# Rust installed as vscode user (see after USER line)
```
Then after `USER $USERNAME`:
```dockerfile
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/home/vscode/.cargo/bin:${PATH}"
```

**Go** — add Go:
```dockerfile
RUN wget -q https://go.dev/dl/go1.22.0.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.22.0.linux-amd64.tar.gz \
    && rm go1.22.0.linux-amd64.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"
```

### User setup (always)

```dockerfile
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

WORKDIR /workspace
USER $USERNAME
```

---

## Step 3 — Generate devcontainer.json

Use this template, adjusting for GPU and language:

```json
{
  "name": "<project-name>",
  "dockerFile": "Dockerfile",
  "context": "..",
  "workspaceFolder": "/workspace",
  "containerUser": "vscode",
  "remoteUser": "vscode",
  "initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize_devcontainer.sh",
  "mounts": [
    "source=${localWorkspaceFolder},target=/workspace,type=bind,consistency=cached",
    "source=${localEnv:HOME}/.claude-<project-name>/data,target=/home/vscode/.claude,type=bind,consistency=cached",
    "source=${localEnv:HOME}/.claude-<project-name>/claude.json,target=/home/vscode/.claude.json,type=bind,consistency=cached"
  ],
  "remoteEnv": {
    "ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}",
    "PATH": "/home/vscode/.local/bin:${containerEnv:PATH}"
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "ms-vscode-remote.remote-containers",
        "anthropic.claude-code"
      ],
      "settings": {
        "terminal.integrated.defaultProfile.linux": "bash"
      }
    }
  },
  "onCreateCommand": "curl -fsSL https://claude.ai/install.sh | bash",
  "postCreateCommand": "<language-specific install command>",
  "postStartCommand": "code --install-extension anthropic.claude-code 2>/dev/null || true"
}
```

### GPU projects

Add `"runArgs": ["--gpus", "all"]` to devcontainer.json.

### Language-specific extensions and postCreateCommand

**Python**:
- Extensions: add `"ms-python.python"`, `"ms-toolsai.jupyter"`
- postCreateCommand: `"python3 -m pip install -r /workspace/requirements.txt"`

**C++**:
- Extensions: add `"ms-vscode.cpptools"`, `"ms-vscode.cmake-tools"`
- postCreateCommand: `"echo 'C++ project ready'"`

**Node.js / TypeScript**:
- Extensions: add `"dbaeumer.vscode-eslint"`
- postCreateCommand: `"cd /workspace && npm install"`

**Rust**:
- Extensions: add `"rust-lang.rust-analyzer"`
- postCreateCommand: `"echo 'Rust project ready'"`

**Go**:
- Extensions: add `"golang.go"`
- postCreateCommand: `"echo 'Go project ready'"`

---

## Step 4 — Generate initialize_devcontainer.sh

This runs on the **host** before the container builds. It creates the per-project Claude config directory so bind mounts succeed.

```bash
#!/bin/bash
set -e

PROJECT_NAME="<project-name>"
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

Make it executable: `chmod +x .devcontainer/initialize_devcontainer.sh`

---

## Step 5 — Generate language-specific files

**Python**:
- `requirements.txt` (empty file)
- `setup.sh`:
  ```bash
  #!/usr/bin/env bash
  set -e
  python3 -m venv .venv
  source .venv/bin/activate
  pip install --upgrade pip
  pip install -r requirements.txt
  echo "Setup complete. Activate with: source .venv/bin/activate"
  ```
  `chmod +x setup.sh`

**C++**:
- `CMakeLists.txt`:
  ```cmake
  cmake_minimum_required(VERSION 3.20)
  project(<project-name> LANGUAGES CXX)
  set(CMAKE_CXX_STANDARD 17)
  ```
- `src/main.cpp` (minimal hello world)

**Node.js / TypeScript**:
- Run `npm init -y` in the project directory
- If TypeScript: also `npm install --save-dev typescript @types/node` and create `tsconfig.json`

**Rust**:
- Run `cargo init` in the project directory (after container is built, or create `Cargo.toml` + `src/main.rs` manually)

**Go**:
- Run `go mod init <project-name>` or create `go.mod` manually
- Create `main.go` (minimal hello world)

---

## Step 6 — Generate .gitignore

Keep it minimal but appropriate for the language.

**Python**:
```
.venv/
__pycache__/
*.pyc
*.egg-info/
dist/
build/
.env
```

**C++**:
```
build/
*.o
*.so
*.a
.cache/
compile_commands.json
.env
```

**Node.js / TypeScript**:
```
node_modules/
dist/
.env
```

**Rust**:
```
target/
.env
```

**Go**:
```
bin/
.env
```

---

## Step 7 — Generate README.md

Keep it minimal:

```markdown
# <project-name>

<one-line description if the user provided project goals, otherwise just the name>

## Development

This project uses a VS Code devcontainer. Open in VS Code and select "Reopen in Container".

### Prerequisites
- Docker
- VS Code with Remote Containers extension
- `ANTHROPIC_API_KEY` set in your environment (or authenticate via `claude` CLI on first run)
```

---

## Step 8 — Generate scripts/setup-claude-code.sh

Same as the initialize script but standalone with verbose output:

```bash
#!/bin/bash
set -e
PROJECT_NAME="${1:-<project-name>}"
# ... (same logic as initialize_devcontainer.sh with echo status messages)
```

`chmod +x scripts/setup-claude-code.sh`

---

## Step 9 — Final setup

```bash
cd <project-name>
git add -A
git commit -m "Initial project scaffold with devcontainer and Claude Code integration"
```

Tell the user:
1. Open the project folder in VS Code
2. Select "Reopen in Container" when prompted
3. Claude Code CLI will authenticate on first run — credentials persist after that
4. The Claude Code extension should appear in the sidebar
