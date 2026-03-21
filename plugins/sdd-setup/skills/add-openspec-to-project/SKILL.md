---
name: add-openspec-to-project
description: Add the @fission-ai/openspec CLI tool to a project's devcontainer. Installs Node.js (if missing) and the openspec npm package into the Dockerfile so the tool persists across container rebuilds. Use when the user wants to set up openspec in a new or existing devcontainer project.
tools: Read, Edit, Write, Bash
---

# Add OpenSpec to a Dev Container

This skill installs the `@fission-ai/openspec` CLI tool into an existing devcontainer project. It ensures Node.js is present, adds openspec as a pinned global npm install in the Dockerfile, and documents how to verify and initialize openspec after rebuild.

**Base compatibility**: Works with `ubuntu:22.04` as the base image — no nvidia/cuda dependency required.

**Pinned version**: The openspec version is pinned in the Dockerfile for reproducible builds.

---

## Step 1 — Read existing devcontainer state

Before making any changes, read:

- `.devcontainer/Dockerfile`
- `.devcontainer/devcontainer.json`

Confirm the base image is Ubuntu/Debian-based (e.g., `ubuntu:22.04`, `nvidia/cuda:*-ubuntu22.04`, `debian:*`). The NodeSource setup script requires `apt-get`. If the base image uses a different package manager (Alpine, Fedora, etc.), stop and inform the user that this skill assumes an apt-based image.

Identify:
- Whether Node.js is already installed (look for `nodesource.com/setup`, `apt-get install.*nodejs`, `nvm install`, `NODE_VERSION`, or a `FROM node:` base layer)
- Whether a BuildKit syntax header (`# syntax=docker/dockerfile:1`) is present
- Whether openspec is already installed

---

## Step 2 — Ensure Node.js is in the Dockerfile

If Node.js is already present, skip to Step 3.

If not, add Node.js via NodeSource. Insert the following block **after** the main `apt-get` install block and **before** any `USER` directives. Node.js must be installed as root.

```dockerfile
# Install Node.js LTS (for openspec and other npm tools)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*
```

**Requirements**: `curl` and `ca-certificates` must already be in the base `apt-get install` list. If they are missing, add them to the existing `apt-get install` line rather than creating a separate `RUN` layer.

Use NodeSource 20.x (current LTS). Do not use the distro-default `nodejs` package from `apt-get` — on ubuntu:22.04 it is typically v12 and too old for openspec.

---

## Step 3 — Add the openspec global install

Insert the following **after** the Node.js installation block and **before** any `USER` directive. Use a BuildKit cache mount to avoid re-downloading on every rebuild:

```dockerfile
# Install npm globals (pinned for layer cache stability).
# BuildKit cache mount: npm's download cache persists on the Docker host between
# builds (fast rebuilds) but is NOT baked into the image layer (small image).
RUN --mount=type=cache,target=/root/.npm \
    npm install -g @fission-ai/openspec@1.2.0
```

This must run as root so the package installs to the system-wide `node_modules` and the `openspec` binary lands in a PATH directory (typically `/usr/local/bin`).

**BuildKit header**: The `--mount=type=cache` syntax requires BuildKit. Ensure the first line of the Dockerfile is:

```dockerfile
# syntax=docker/dockerfile:1
```

If this header is missing, add it as the very first line.

**Checking the current version**: To find the latest published version:

```bash
npm view @fission-ai/openspec version
```

Then substitute that version into the Dockerfile.

**Combining with other npm globals**: If other global npm packages are needed (e.g., `claude-code`), combine them in a single `RUN` layer to share the cache mount and reduce layers:

```dockerfile
RUN --mount=type=cache,target=/root/.npm \
    npm install -g \
      @fission-ai/openspec@1.2.0 \
      @anthropic-ai/claude-code@2.1.78
```

---

## Step 4 — Rebuild the container

After saving all Dockerfile changes, rebuild:

- **VS Code**: `Ctrl+Shift+P` → "Dev Containers: Rebuild Container"
- **CLI**: `devcontainer build --workspace-folder .`

---

## Step 5 — Verify installation

After rebuild, verify inside the container:

```bash
node --version        # Should show v20.x.x
npm --version         # Should show 10.x.x or similar
openspec --version    # Should print version string
which openspec        # Should be /usr/local/bin/openspec
```

If `which openspec` returns nothing, check whether `npm root -g` points to a directory on PATH. For non-root users (e.g., `vscode`), the global bin may be `/home/vscode/.npm-global/bin` — add to PATH via `remoteEnv` in `devcontainer.json` if needed:

```json
"remoteEnv": {
  "PATH": "/home/vscode/.npm-global/bin:${containerEnv:PATH}"
}
```

---

## Step 6 — Create an openspec config (if not present)

If the project does not yet have an openspec config, initialize one inside the container:

```bash
openspec init
```

This creates the necessary config files in the project root. The config should be committed to version control so all contributors share the same spec setup.

If the project already has an openspec config (e.g., `openspec.json` or a `.openspec/` directory), skip this step.

---

## Common pitfalls

| Mistake | Fix |
|---------|-----|
| `npm install -g` after `USER` switch in Dockerfile | Move the `RUN npm install -g` line above the `USER` directive so it runs as root |
| Missing `curl` or `ca-certificates` in base packages | Add them to the existing `apt-get install` line |
| Using distro-default `apt-get install nodejs` without NodeSource | Distro-default Node.js on ubuntu:22.04 is too old for openspec; use NodeSource 20.x |
| Floating `@latest` version in Dockerfile | Pin to a specific version for reproducible builds — check current with `npm view @fission-ai/openspec version` |
| `--mount=type=cache` fails at build | Add `# syntax=docker/dockerfile:1` as the first line of the Dockerfile |
| `openspec` not found after rebuild | Check npm global bin is on PATH; add to `remoteEnv.PATH` in devcontainer.json if needed |
| openspec config not committed | Run `openspec init` once and commit the resulting config files |
| Multiple Node.js install methods conflicting | Use only one method (NodeSource recommended); remove `nvm` or `FROM node` approaches if switching |
