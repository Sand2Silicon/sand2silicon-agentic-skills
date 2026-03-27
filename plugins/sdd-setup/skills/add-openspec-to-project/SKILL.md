---
name: add-openspec-to-project
description: Add the @fission-ai/openspec CLI tool to a project's devcontainer. Ensures Node.js is in the Dockerfile (system package) and adds the openspec npm install to setup.sh (postCreateCommand) as a non-root user with an npm global prefix. Use when the user wants to set up openspec in a new or existing devcontainer project.
tools: Read, Edit, Write, Bash
---

# Add OpenSpec to a Dev Container

This skill installs the `@fission-ai/openspec` CLI tool into an existing devcontainer project. OpenSpec is a specification management tool for structured project planning.

**Installation pattern**: Node.js is installed as a system package in the Dockerfile (it requires root/apt). OpenSpec itself is installed in `setup.sh` (the `postCreateCommand` script) as the non-root container user, using an npm global prefix trick to avoid EACCES permission errors.

**Base compatibility**: Works with any apt-based image (`ubuntu:22.04`, `nvidia/cuda:*-ubuntu22.04`, `debian:*`). The NodeSource setup script requires `apt-get`. For yum-based images (Amazon Linux), a separate NodeSource command is available (see Step 2). If the base image uses a different package manager (Alpine, Fedora, etc.), stop and inform the user that this skill assumes an apt-based or yum-based image.

**Pinned version**: The openspec version is pinned in `setup.sh` for reproducible installs.

**Plugin resources**: This plugin provides shared scripts at `plugins/sdd-setup/scripts/` (including `setup.sh` with `--openspec` flag) and a builder agent at `plugins/sdd-setup/agents/builder/` for troubleshooting build failures.

---

## Step 1 — Read existing devcontainer state

Before making any changes, read:

- `.devcontainer/Dockerfile`
- `.devcontainer/devcontainer.json`
- `.devcontainer/setup.sh` (if it exists)

Confirm the base image is apt-based or yum-based. If it uses a different package manager, stop and inform the user.

Identify:
- Whether Node.js is already installed in the Dockerfile (look for `nodesource.com/setup`, `apt-get install.*nodejs`, `nvm install`, `NODE_VERSION`, `NODE_MAJOR`, or a `FROM node:` base layer)
- Whether openspec is already installed (look for `@fission-ai/openspec` or `openspec` in `setup.sh` or any `npm install` line)
- Whether `curl` and `ca-certificates` are in the `apt-get install` list
- Whether a `postCreateCommand` exists in `devcontainer.json` and what it runs
- Whether `containerUser` is set in `devcontainer.json` (e.g., `"containerUser": "appuser"`)

If openspec is already installed in `setup.sh`, inform the user and stop — nothing to do.

---

## Step 2 — Ensure Node.js is in the Dockerfile

OpenSpec is distributed via npm, so Node.js and npm must be available as system packages. Check whether Node.js is already installed in the Dockerfile.

**If Node.js is present (any version >= 18)**: Skip to Step 3. Node.js 18, 20, and 22 all work with openspec.

**If Node.js is not present**: Add the NodeSource install to the Dockerfile. This is the ONLY Dockerfile change this skill makes. Insert the following block **after** the main `apt-get install` block.

For **apt-based images** (Ubuntu, Debian):

```dockerfile
# Install Node.js LTS via NodeSource (required for openspec)
ARG NODE_MAJOR=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
```

For **yum-based images** (Amazon Linux):

```dockerfile
# Install Node.js via NodeSource (required for openspec)
RUN curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - && yum install -y nodejs
```

**Requirements**: `curl` and `ca-certificates` must already be in the base package install list. If they are missing, add them to the existing install line rather than creating a separate layer.

Do **not** use the distro-default `apt-get install nodejs` without NodeSource — on ubuntu:22.04 it ships Node.js v12, which is far too old for openspec.

**Node.js version guidance**: Node 22 is the current LTS and recommended for new projects. Node 20 also works and is common in existing setups. Do not change a working Node.js version that is >= 18.

---

## Step 3 — Add openspec install to setup script (postCreateCommand)

OpenSpec is installed as a **user-space npm global** in the setup script, not in the Dockerfile. This avoids running `npm install -g` as root and ensures the binary is owned by the container user.

If the project already has a `.devcontainer/setup.sh` script, add the openspec section to it. If no setup script exists, create `.devcontainer/setup.sh`.

Add the following block to the setup script:

```bash
# --- OpenSpec ---
# Configure npm global prefix for non-root user (avoids EACCES errors)
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
if ! grep -q '\.npm-global/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
fi

# Install OpenSpec CLI (specification management for structured project planning)
OPENSPEC_VERSION="${OPENSPEC_VERSION:-1.2.0}"
npm install -g @fission-ai/openspec@${OPENSPEC_VERSION}
```

**Why this pattern**: Running `npm install -g` as a non-root user without configuring a prefix fails with EACCES because the default global directory (`/usr/local/lib/node_modules`) is root-owned. The `npm config set prefix` redirects global installs to `~/.npm-global/`, which the container user owns.

Make sure the setup script:
1. Has `#!/usr/bin/env bash` as its shebang
2. Has `set -euo pipefail` for error handling
3. Is executable (`chmod +x .devcontainer/setup.sh`)

Ensure `devcontainer.json` has a `postCreateCommand` that calls this script:

```json
"postCreateCommand": "bash .devcontainer/setup.sh"
```

If a `postCreateCommand` already exists, integrate the setup script call appropriately. If the existing command already calls `setup.sh`, just ensure the openspec section is in the script.

Alternatively, if using the plugin's shared `setup.sh` as a base, pass the `--openspec` flag:

```json
"postCreateCommand": "bash .devcontainer/setup.sh --openspec"
```

---

## Step 4 — Optionally add openspec init to postCreateCommand

If the project does not yet have an openspec config (`openspec.yaml`, `openspec.json`, or `.openspec/` directory), you can add automatic initialization to the setup script:

```bash
# Initialize openspec config if not present
if [ ! -f openspec.yaml ] && [ ! -f openspec.json ] && [ ! -d .openspec ]; then
  openspec init
fi
```

Add this block **after** the openspec install block in `setup.sh`.

This is optional — the user can also run `openspec init` manually after rebuild. Only add it if the user wants automatic initialization.

---

## Step 5 — Tell the user to rebuild the container

After saving all Dockerfile, setup.sh, and devcontainer.json changes, the container must be rebuilt:

- **VS Code**: `Ctrl+Shift+P` then "Dev Containers: Rebuild Container"
- **CLI**: `devcontainer build --workspace-folder .`

Print this summary to the user:

```
OpenSpec has been added to your devcontainer.

Changes made:
  - Dockerfile: Ensured Node.js is installed (system package)
  - setup.sh: Added openspec npm global install (user-space)
  - devcontainer.json: Ensured postCreateCommand runs setup.sh

Rebuild the container now:
  VS Code: Ctrl+Shift+P -> "Dev Containers: Rebuild Container"
  CLI:     devcontainer build --workspace-folder .

After rebuild, verify with:
  which openspec        # Should be ~/.npm-global/bin/openspec
  openspec --version
```

---

## Step 6 — Verify installation inside rebuilt container

After the container rebuilds, verify inside the container terminal:

```bash
node --version        # Should show v22.x.x (or >= 18.x.x if pre-existing)
npm --version         # Should show 10.x.x or similar
which openspec        # Should be /home/<user>/.npm-global/bin/openspec
openspec --version    # Should print the openspec version string
```

If `which openspec` returns nothing:

1. Check that `~/.npm-global/bin` is on your PATH: `echo $PATH`
2. Check that `npm config get prefix` returns `~/.npm-global` (not `/usr/local`)
3. Try sourcing bashrc: `source ~/.bashrc && which openspec`

If `npm install -g` failed with EACCES during setup, the npm global prefix was not configured before the install. Re-run:

```bash
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
npm install -g @fission-ai/openspec@1.2.0
```

---

## Step 7 — Create an openspec config (if not present)

If the project does not yet have an openspec config, initialize one inside the container:

```bash
openspec init
```

This creates `openspec.yaml` (or `openspec.json`) in the project root. The config should be committed to version control so all contributors share the same spec setup.

If the project already has an openspec config, skip this step.

---

## Troubleshooting

If the build fails or openspec is not available after rebuild, use the builder agent (`plugins/sdd-setup/agents/builder/`) for diagnosis. Common debugging commands:

```bash
# Check if Node.js is available (installed via Dockerfile)
node --version
npm --version

# Check npm global prefix (should be ~/.npm-global for non-root user)
npm config get prefix
ls -la ~/.npm-global/bin/

# Check what's on PATH
echo $PATH

# Try installing openspec manually to debug
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
npm install -g @fission-ai/openspec@1.2.0

# Check Docker build output for Node.js install errors
docker build --progress=plain -f .devcontainer/Dockerfile .
```

---

## Common pitfalls

| Mistake | Fix |
|---------|-----|
| npm global prefix not configured before `npm install -g` | Non-root users get EACCES errors without `npm config set prefix "$HOME/.npm-global"`. This must be set BEFORE running `npm install -g` |
| PATH does not include `~/.npm-global/bin` | Must be exported in the current session AND added to `~/.bashrc` for persistence. Without this, `which openspec` returns nothing |
| Missing `curl` or `ca-certificates` in Dockerfile apt packages | Add them to the existing `apt-get install` line — the NodeSource setup script downloads via HTTPS |
| Using distro-default `apt-get install nodejs` without NodeSource | Distro-default Node.js on ubuntu:22.04 is v12, far too old for openspec. Use NodeSource 20.x or 22.x LTS |
| Floating `@latest` tag instead of pinned version | Pin to a specific version (`@fission-ai/openspec@1.2.0`) for reproducible installs. Check latest with `npm view @fission-ai/openspec version` |
| openspec installed in Dockerfile instead of setup.sh | Install openspec in `setup.sh` (postCreateCommand) as the container user, not in the Dockerfile as root. Only Node.js itself goes in the Dockerfile |
| Using `onCreateCommand` instead of `postCreateCommand` | The setup script should run via `postCreateCommand` so it executes after the container is fully created and the user environment is ready |
| Using `remoteUser` instead of `containerUser` | Use `"containerUser": "appuser"` in devcontainer.json to set the non-root user |
| openspec config files not committed to git | Run `openspec init` once and commit the resulting config files so all team members share the same spec setup |
| Multiple Node.js install methods conflicting (nvm + NodeSource, etc.) | Use only one method. NodeSource is recommended for Dockerfiles. Remove `nvm` or `FROM node:` approaches if switching to NodeSource |
| Node.js ARG set to version > 22 | Node 22 is LTS (stable). Node 23+ is Current (unstable) and not recommended for production tooling |
| Openspec installed but `openspec init` never run | The CLI installs via npm but the project config is created by `openspec init`. Run it once in the project root after first container build |
