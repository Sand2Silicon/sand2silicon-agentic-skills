---
name: add-beads-to-project
description: Add Beads (bd CLI + dolt database) to an existing devcontainer project. Beads is a dependency-aware issue graph for AI coding agents, backed by an embedded Dolt database. Both dolt and bd are user-space tools installed to ~/.local/bin by setup_devcontainer.sh (postCreateCommand) -- NOT in the Dockerfile. Use when the user wants to add beads to a devcontainer, set up the bd CLI, or configure Claude Code hooks for beads. Do NOT ask about Bedrock vs Anthropic -- beads does not care about auth method.
tools: Read, Edit, Write, Bash
---

# Add Beads to an Existing Dev Container Project

This skill adds the `bd` (beads) CLI and its `dolt` database backend to an **existing** devcontainer project. Both are **user-space tools** installed to `~/.local/bin` by `setup_devcontainer.sh` via `postCreateCommand`. They are NOT installed in the Dockerfile.

**Key architecture**: The Dockerfile only needs `ENV PATH="/home/appuser/.local/bin:${PATH}"` so that dolt and bd are on PATH. The actual binary installs happen in `setup_devcontainer.sh`, which runs as the container user at container creation time.

**What beads provides**: A dependency-aware issue graph for AI coding agents. Issues are stored in a Dolt database (an embedded, version-controlled SQL store) so the agent can query, update, and traverse task graphs programmatically. No external services or ports required.

**Auth is irrelevant**: Beads does not care about Bedrock vs Anthropic vs Vertex. Do NOT ask the user about authentication method -- that is a Claude Code concern, not a beads concern.

---

## Step 1 -- Read existing devcontainer state

Read these files before making any changes:

- `.devcontainer/setup_devcontainer.sh` (must exist or will be created)
- `.devcontainer/devcontainer.json`
- `.devcontainer/Dockerfile` (or `Dockerfile` at repo root if no `.devcontainer/Dockerfile`)
- `.gitignore` (if it exists at the repo root)

Determine:

1. **Is dolt already installed?** -- Search the setup script for `dolt` install commands
2. **Is bd already installed?** -- Search the setup script for `bd` or `beads` install commands
3. **Is `~/.local/bin` on PATH in the Dockerfile?** -- Look for `ENV PATH="/home/appuser/.local/bin:${PATH}"` (or equivalent with the actual username)
4. **Does `postCreateCommand` already point to `setup_devcontainer.sh`?** -- Check `devcontainer.json`
5. **Is `.beads/` in `.gitignore`?** -- Check the gitignore file

If dolt and bd are both already installed, inform the user and skip to Step 7 for verification.

---

## Step 2 -- Update or create setup_devcontainer.sh

Add these install blocks to `.devcontainer/setup_devcontainer.sh`. Both tools install to `$HOME/.local/bin` as user-space tools.

### Install blocks to add

```bash
# Install dolt (database backend for beads) -- pinned, bump manually when upgrading
mkdir -p "$HOME/.local/bin"
DOLT_VERSION=1.83.6
curl -fsSL "https://github.com/dolthub/dolt/releases/download/v${DOLT_VERSION}/dolt-linux-amd64.tar.gz" -o /tmp/dolt.tar.gz \
    && tar -xzf /tmp/dolt.tar.gz -C /tmp \
    && cp /tmp/dolt-linux-amd64/bin/dolt "$HOME/.local/bin/" \
    && rm -rf /tmp/dolt.tar.gz /tmp/dolt-linux-amd64

# Install beads (bd) -- pinned, bump manually when upgrading
BD_VERSION=0.62.0
curl -fsSL "https://github.com/steveyegge/beads/releases/download/v${BD_VERSION}/beads_${BD_VERSION}_linux_amd64.tar.gz" -o /tmp/beads.tar.gz \
    && tar -xzf /tmp/beads.tar.gz -C "$HOME/.local/bin" bd \
    && rm /tmp/beads.tar.gz
```

### If `setup_devcontainer.sh` exists

Add the install blocks above to the existing script. Insert them before any final `cd` command or final `echo` statement at the end of the script. Ensure `mkdir -p "$HOME/.local/bin"` appears before both install blocks (it may already exist in the script).

### If `setup_devcontainer.sh` does not exist

Create `.devcontainer/setup_devcontainer.sh` with a complete script:

```bash
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# Install dolt (database backend for beads) -- pinned, bump manually when upgrading
DOLT_VERSION=1.83.6
curl -fsSL "https://github.com/dolthub/dolt/releases/download/v${DOLT_VERSION}/dolt-linux-amd64.tar.gz" -o /tmp/dolt.tar.gz \
    && tar -xzf /tmp/dolt.tar.gz -C /tmp \
    && cp /tmp/dolt-linux-amd64/bin/dolt "$HOME/.local/bin/" \
    && rm -rf /tmp/dolt.tar.gz /tmp/dolt-linux-amd64

# Install beads (bd) -- pinned, bump manually when upgrading
BD_VERSION=0.62.0
curl -fsSL "https://github.com/steveyegge/beads/releases/download/v${BD_VERSION}/beads_${BD_VERSION}_linux_amd64.tar.gz" -o /tmp/beads.tar.gz \
    && tar -xzf /tmp/beads.tar.gz -C "$HOME/.local/bin" bd \
    && rm /tmp/beads.tar.gz

echo "setup_devcontainer.sh complete."
```

Make the script executable:

```bash
chmod +x .devcontainer/setup_devcontainer.sh
```

---

## Step 3 -- Ensure PATH in Dockerfile

Check the Dockerfile for this line:

```dockerfile
ENV PATH="/home/appuser/.local/bin:${PATH}"
```

Replace `appuser` with the actual username if different (look for `ARG USERNAME` or `RUN useradd` in the Dockerfile).

This line must appear in the devcontainer stage, **before** the `USER appuser` directive. If it is missing, add it.

Without this `ENV` line, dolt and bd will only be available in interactive bash sessions (via `.bashrc`), not in non-interactive contexts like VS Code tasks, lifecycle commands, or Claude Code hooks.

---

## Step 4 -- Update devcontainer.json if needed

Only update `devcontainer.json` if `postCreateCommand` does NOT already point to `setup_devcontainer.sh`. If it already does, the setup script update from Step 2 is sufficient -- no changes needed here.

If there is no `postCreateCommand` at all, add it:

```json
"postCreateCommand": "/bin/bash /workspaces/PROJECT_NAME/.devcontainer/setup_devcontainer.sh"
```

Replace `PROJECT_NAME` with the actual project name (the workspace folder name).

If `postCreateCommand` exists but points to a different script, either:
- Add the dolt/bd install blocks to that existing script instead (go back to Step 2), or
- Change it to point to `setup_devcontainer.sh` if appropriate

---

## Step 5 -- Handle .gitignore

Ask the user: **"Do you want to commit the `.beads/` directory to git, or ignore it? Default is ignore."**

**Option A -- Ignore (default, recommended):**

Add to `.gitignore`:

```
# Beads local task graph database
.beads/
```

This is appropriate when each developer has their own local task graph or when using a Dolt remote for sync.

**Option B -- Commit (shared task graph):**

Do NOT add `.beads/` to `.gitignore`. Only choose this if the user explicitly requests it.

Unless the user specifies otherwise, use Option A.

---

## Step 6 -- Rebuild the container

After saving all changes, tell the user to rebuild:

- **VS Code**: `Ctrl+Shift+P` then "Dev Containers: Rebuild Container"
- **CLI**: `devcontainer build --workspace-folder .`

---

## Step 7 -- Post-rebuild verification

After the container rebuilds, verify inside the container terminal:

```bash
which bd       # Should be ~/.local/bin/bd
which dolt     # Should be ~/.local/bin/dolt
bd --version   # Should print beads version (e.g., 0.62.0)
dolt version   # Should print dolt version (e.g., 1.83.6)
```

Both binaries must be in `~/.local/bin`, confirming they were installed by `setup_devcontainer.sh` as user-space tools (NOT in `/usr/local/bin`).

---

## Step 8 -- Post-setup: Initialize beads

After rebuild, the user must run:

```bash
bd init
bd setup claude --project
```

**What `bd init` does**: Creates the `.beads/` directory and initializes the Dolt database in the current project directory.

**What `bd setup claude --project` does**: Adds hooks to `.claude/settings.local.json` so that beads context is loaded automatically at session start and before compaction:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "command": "bd prime",
            "type": "command"
          }
        ],
        "matcher": ""
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "command": "bd prime",
            "type": "command"
          }
        ],
        "matcher": ""
      }
    ]
  }
}
```

The `--project` flag scopes the hooks to the project's `settings.local.json` (not global settings). If `.claude/settings.local.json` already exists with other content, the hooks section is merged into it.

---

## Step 9 -- First-use commands

Once beads is initialized and hooks are configured, the user can start working with the task graph:

```bash
bd create "Short description of a task"    # Create a new issue
bd ready                                    # Show issues ready to work on (all deps met)
bd show <issue-id>                          # Show details of a specific issue
bd prime                                    # Print full session context (used by hooks)
```

---

## Common pitfalls

| Mistake | Fix |
|---------|-----|
| Using upstream `install.sh` pipe in Docker | The upstream `curl ... install.sh \| bash` method has an ANSI escape code bug that corrupts the download URL in Docker/WSL. Always use the direct binary tarball download method shown in Step 2. |
| Wrong GitHub repo for bd | The correct repo is `steveyegge/beads`, NOT `fission-codes/beads`. Current version is `0.62.0`. |
| Installing dolt via `install.sh` to `/usr/local/bin` | Dolt must be installed via tarball to `~/.local/bin` as a user-space tool. Do NOT use the upstream dolt install script which installs to `/usr/local/bin`. |
| Installing dolt or bd in the Dockerfile | Both are user-space tools installed by `setup_devcontainer.sh` to `~/.local/bin`. They do NOT belong in the Dockerfile. The Dockerfile only needs the `ENV PATH` line. |
| Missing `ENV PATH` in Dockerfile | The Dockerfile must have `ENV PATH="/home/appuser/.local/bin:${PATH}"` so dolt and bd are on PATH in non-interactive shells. Without this, they work in terminal but fail in hooks and lifecycle commands. |
| Asking about Bedrock vs Anthropic | Beads does not care about authentication method. That is a Claude Code concern, not a beads concern. Do NOT ask the user about auth. |
| Running `bd init` inside the setup script | `bd init` must run AFTER the container is fully built and the user is in the project directory. It is an interactive post-setup step, not part of `setup_devcontainer.sh`. |
| Using `bd setup claude` without `--project` | The `--project` flag scopes hooks to `.claude/settings.local.json`. Without it, hooks would be added globally. Always use `bd setup claude --project`. |
| Hook files losing +x on rebuild | Hook scripts may lose execute permission on container rebuild. Run `bd hooks install` or `chmod +x` manually to restore permissions. |
| Using `remoteUser` instead of `containerUser` | Use `"containerUser": "appuser"` in devcontainer.json, NOT `"remoteUser"`. |
| Floating versions in setup script | Pin dolt and bd versions (`DOLT_VERSION=1.83.6`, `BD_VERSION=0.62.0`) for reproducible builds. Bump manually when upgrading. |
| Committing `.beads/` unintentionally | Add `.beads/` to `.gitignore` unless the team explicitly wants a shared task graph committed to git. |
