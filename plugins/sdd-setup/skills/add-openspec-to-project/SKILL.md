---
name: add-openspec-to-project
description: Add the @fission-ai/openspec CLI tool to an existing project's devcontainer. Ensures Node.js is installed in the Dockerfile (system package, needs root) and adds the openspec npm install to setup_devcontainer.sh (postCreateCommand) as a non-root user with a user-writable npm global prefix. Use when the user wants to add openspec to a devcontainer, set up the openspec CLI, or integrate specification management into their dev environment. Do NOT ask about authentication method — OpenSpec does not care about Bedrock vs Anthropic.
tools: Read, Edit, Write, Bash
---

# Add OpenSpec to a Dev Container

This skill adds the `@fission-ai/openspec` CLI to an **existing** devcontainer project. OpenSpec is a specification management tool for structured project planning.

**Architecture**: Two things get installed in two different places:

| What | Where | Why |
|------|-------|-----|
| **Node.js** | Dockerfile | System package, needs root for NodeSource apt/yum repo setup |
| **OpenSpec** | `setup_devcontainer.sh` | npm global install as non-root user with `~/.npm-global` prefix |

npm is ONLY here because OpenSpec requires it. If the user did not want OpenSpec, there would be no npm.

**Key principle**: Node.js is a system dependency (Dockerfile). OpenSpec is a user-space tool (setup script via `postCreateCommand`). Never install OpenSpec in the Dockerfile.

---

## Step 1 — Read existing devcontainer state

Read these files before making any changes:

- `.devcontainer/Dockerfile` (or `Dockerfile` if at project root)
- `.devcontainer/setup_devcontainer.sh` (if it exists)
- `.devcontainer/devcontainer.json`

Identify:

- **Is Node.js already installed?** Look for `nodesource.com/setup`, `apt-get install.*nodejs`, `nvm install`, `NODE_VERSION`, `NODE_MAJOR`, or a `FROM node:` base layer.
- **Is OpenSpec already in the setup script?** Look for `@fission-ai/openspec` or `openspec` in any `npm install` line.
- **Is npm available?** If Node.js is installed, npm comes with it.
- **Is the base image apt-based or yum-based?** Look for `apt-get` vs `yum` in the Dockerfile.
- **Where is the `USER` directive?** Node.js must be installed BEFORE any `USER` switch to non-root.
- **Does `devcontainer.json` have a `postCreateCommand`?** And does it already call `setup_devcontainer.sh`?
- **What is the `containerUser`?** (e.g., `"containerUser": "appuser"`)

If OpenSpec is already installed in the setup script, inform the user and stop — nothing to do.

If the base image uses a package manager other than apt or yum (Alpine apk, Fedora dnf, etc.), stop and inform the user that this skill assumes an apt-based or yum-based image.

---

## Step 2 — Add Node.js to the Dockerfile (if not present)

Only modify the Dockerfile if Node.js is NOT already installed. If Node.js >= 18 is already present, skip to Step 3.

The Node.js install block must go **before** any `USER` directive (it needs root). Insert it after the main `apt-get install` or `yum install` block.

**Requirements**: `curl` and `ca-certificates` must already be in the base package install list. If they are missing, add them to the existing install line rather than creating a separate layer.

### For apt-based images (Ubuntu, Debian)

```dockerfile
# Node.js LTS (required for OpenSpec)
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
```

### For yum-based images (Amazon Linux, CentOS)

```dockerfile
# Node.js LTS (required for OpenSpec)
RUN curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - \
    && yum install -y nodejs \
    && yum clean all && rm -rf /var/cache/yum /tmp/*
```

Do **not** use the distro-default `apt-get install nodejs` without NodeSource — on ubuntu:22.04 it ships Node.js v12, which is far too old for OpenSpec.

**Node.js version guidance**: Node 22 is the current LTS and recommended for new projects. Node 20 also works. Do not change a working Node.js version that is >= 18. Never use Node 23+ (Current/unstable).

---

## Step 3 — Update or create setup_devcontainer.sh

OpenSpec is installed as a **user-space npm global** in the setup script, not in the Dockerfile. This avoids running `npm install -g` as root and ensures the binary is owned by the container user.

### If setup_devcontainer.sh exists

Add the following block to the existing script. If the npm global prefix lines (`mkdir -p "$HOME/.npm-global"`, `npm config set prefix`) already exist in the file, do NOT duplicate them — only add the `npm install -g @fission-ai/openspec` line.

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

### If setup_devcontainer.sh does not exist

Create `.devcontainer/setup_devcontainer.sh` with this complete content:

```bash
#!/usr/bin/env bash
set -euo pipefail

# --- OpenSpec ---
# Configure npm to install global packages in user-writable directory
# This avoids EACCES errors when running as non-root (appuser)
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"

# Install OpenSpec
npm install -g @fission-ai/openspec@1.2.0
```

Then make it executable:

```bash
chmod +x .devcontainer/setup_devcontainer.sh
```

---

## Step 4 — Update devcontainer.json if needed

Only update `devcontainer.json` if the `postCreateCommand` does not already call `setup_devcontainer.sh`.

If there is no `postCreateCommand`, add one:

```json
"postCreateCommand": "bash .devcontainer/setup_devcontainer.sh"
```

If a `postCreateCommand` already exists and calls a different script, either:
- Add the OpenSpec block to that existing script (preferred), or
- Chain the commands: `"postCreateCommand": "bash .devcontainer/existing.sh && bash .devcontainer/setup_devcontainer.sh"`

If the `postCreateCommand` already calls `setup_devcontainer.sh`, no change needed — the OpenSpec block was added to the script in Step 3.

---

## Step 5 — Rebuild the container

After saving all changes to the Dockerfile, setup_devcontainer.sh, and devcontainer.json, the container must be rebuilt.

Print this summary to the user:

```
OpenSpec has been added to your devcontainer.

Changes made:
  - Dockerfile: Ensured Node.js is installed (system package via NodeSource)
  - setup_devcontainer.sh: Added openspec npm global install (user-space, ~/.npm-global)
  - devcontainer.json: Ensured postCreateCommand runs setup_devcontainer.sh

Rebuild the container now:
  VS Code: Ctrl+Shift+P -> "Dev Containers: Rebuild Container"
  CLI:     devcontainer build --workspace-folder .
```

---

## Step 6 — Verify installation

After the container rebuilds, verify inside the container terminal:

```bash
node --version     # Should show v22.x.x (or >= 18.x.x if pre-existing)
npm --version      # Should show 10.x.x or similar
which openspec     # Should be ~/.npm-global/bin/openspec
openspec --version # Should print the openspec version string
```

If `which openspec` returns nothing:

1. Check that `~/.npm-global/bin` is on PATH: `echo $PATH`
2. Check that `npm config get prefix` returns the home-relative `.npm-global` path (not `/usr/local`)
3. Try sourcing bashrc: `source ~/.bashrc && which openspec`

If `npm install -g` failed with EACCES during setup, the npm global prefix was not configured before the install. Re-run manually:

```bash
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
npm install -g @fission-ai/openspec@1.2.0
```

---

## Step 7 — Initialize openspec (if no config exists)

If the project does not yet have an openspec config (`openspec.yaml`, `openspec.json`, or `.openspec/` directory), initialize one:

```bash
openspec init
```

This creates `openspec.yaml` in the project root. Commit it to version control so all contributors share the same spec setup.

If the project already has an openspec config, skip this step.

---

## Common Pitfalls

| Mistake | Fix |
|---------|-----|
| npm is added without a reason | npm is ONLY needed because OpenSpec requires it. Do not add npm/Node.js to projects that do not need OpenSpec |
| npm global prefix not configured before `npm install -g` | Non-root users get EACCES errors without `npm config set prefix "$HOME/.npm-global"`. This MUST be set BEFORE running `npm install -g` |
| PATH does not include `~/.npm-global/bin` | Must be exported in the current session AND added to `~/.bashrc` for persistence. Without this, `which openspec` returns nothing |
| Node.js installed in setup script instead of Dockerfile | Node.js needs root for the NodeSource repo setup. It goes in the Dockerfile. Only OpenSpec goes in setup_devcontainer.sh |
| OpenSpec installed in Dockerfile instead of setup script | OpenSpec is a user-space npm global. Install it in setup_devcontainer.sh as the container user, not in the Dockerfile as root |
| Using distro-default `apt-get install nodejs` without NodeSource | Distro-default Node.js on ubuntu:22.04 is v12, far too old. Use NodeSource to get Node 20 or 22 LTS |
| NodeSource URL wrong for package manager | apt-based: `deb.nodesource.com`. yum-based: `rpm.nodesource.com`. Do not mix them |
| Node.js ARG set to version > 22 | Node 22 is LTS (stable). Node 23+ is Current (unstable) and not recommended |
| Asking user about Bedrock vs Anthropic auth | OpenSpec does not care about the authentication method. That is a Claude Code concern, not an OpenSpec concern. Do not ask |
| `openspec init` never run after install | The npm install gives you the CLI binary. The project config is created by `openspec init`. Run it once in the project root after first container build |
| Using `remoteUser` instead of `containerUser` | Use `"containerUser": "appuser"` in devcontainer.json, not `remoteUser` |
| Floating `@latest` tag instead of pinned version | Pin to a specific version (`@fission-ai/openspec@1.2.0`) for reproducible builds. Check latest with `npm view @fission-ai/openspec version` |
| Duplicate npm global prefix lines in setup script | If the setup script already has the `mkdir -p "$HOME/.npm-global"` and `npm config set prefix` lines (e.g., from another npm-based tool), do not add them again. Only add the `npm install -g @fission-ai/openspec` line |
| Missing `curl` or `ca-certificates` in Dockerfile | Add them to the existing `apt-get install` line. The NodeSource setup script downloads via HTTPS and needs both |
