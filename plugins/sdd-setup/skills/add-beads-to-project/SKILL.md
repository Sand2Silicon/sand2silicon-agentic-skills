---
name: add-beads-to-project
description: Integrate beads (`bd` CLI) into a project's dev container. Beads is a distributed, graph-based issue tracker for AI coding agents — it replaces markdown task plans with a dependency-aware task graph backed by an embedded version-controlled database. Use when the user wants to add beads to a devcontainer, set up the bd CLI, or configure Claude Code hooks for beads.
tools: Read, Edit, Write, Bash
---

# Add Beads to a Dev Container Project

This skill adds the `bd` (beads) CLI and its `dolt` database backend to an **existing** devcontainer project as **user-space tools** installed by the setup script — not baked into the Dockerfile. Both binaries install to `~/.local/bin` at container creation time via `postCreateCommand`, so they require no root privileges and survive as non-root user installs.

**What beads provides**: A dependency-aware issue graph for AI coding agents. Issues are stored in a Dolt database (an embedded, version-controlled SQL store) — not markdown files — so the agent can query, update, and traverse task graphs programmatically. No external services or ports required.

**Architecture**: Dolt and bd are **not** installed in the Dockerfile. The Dockerfile only provides system packages (curl, git, etc.) and sets `ENV PATH="/home/appuser/.local/bin:${PATH}"`. The actual tool installs happen in `setup.sh`, which runs as the container user via `postCreateCommand`.

**Plugin resources**: This plugin provides shared infrastructure you should reference:

| Resource | Path | Purpose |
|----------|------|---------|
| Builder agent | `agents/builder/AGENT.md` | Dispatch Dockerfile/devcontainer troubleshooting to this subagent |
| initialize.sh | `scripts/initialize.sh` | Host-side pre-build script (creates bind-mount paths) |
| setup.sh | `scripts/setup.sh` | In-container setup script (has `--beads` flag for dolt + bd install) |
| Dockerfile.base | `templates/Dockerfile.base` | Reference Dockerfile (does NOT install dolt or bd) |
| devcontainer.json.tmpl | `templates/devcontainer.json.tmpl` | Reference devcontainer with postCreateCommand |

---

## Step 1 — Read existing devcontainer state

Read these files before making any changes:

- `.devcontainer/Dockerfile`
- `.devcontainer/devcontainer.json`
- `.devcontainer/setup.sh` (if it exists)
- `.claude/settings.local.json` (if it exists)
- `.gitignore` (if it exists at the repo root)

Identify:

- Which base image is used (must be Debian/Ubuntu-based for `apt-get`)
- Whether `curl` is in the `apt-get install` list (required for downloading dolt and bd)
- Whether the Dockerfile sets `ENV PATH="/home/<user>/.local/bin:${PATH}"` (required so dolt and bd are on PATH)
- Which user the container runs as (`containerUser` in devcontainer.json)
- Whether a setup script already exists and what it installs
- Which lifecycle commands already exist in `devcontainer.json` (`initializeCommand`, `postCreateCommand`)
- Whether `dolt` or `bd` installs are already present in the setup script
- Whether `.beads/` is already mentioned in `.gitignore`
- Whether `.claude/settings.local.json` already has beads hooks

If the base image is not Debian/Ubuntu-based (e.g., Alpine, Fedora), stop and inform the user that this skill assumes an apt-based image.

---

## Step 2 — Add dolt + bd install to setup script

Both dolt and bd install to `$HOME/.local/bin` as user-space tools. They are **not** installed in the Dockerfile. Add them to the project's setup script, which runs via `postCreateCommand`.

### If the project uses the shared `setup.sh`

Copy `scripts/setup.sh` to `.devcontainer/setup.sh` (if not already present) and ensure the `--beads` flag is passed in `postCreateCommand`. The shared script already contains the correct install logic:

**Dolt install** (direct tarball to `~/.local/bin`):

```bash
DOLT_VERSION=1.83.6
curl -fsSL "https://github.com/dolthub/dolt/releases/download/v${DOLT_VERSION}/dolt-linux-amd64.tar.gz" -o /tmp/dolt.tar.gz \
    && tar -xzf /tmp/dolt.tar.gz -C /tmp \
    && cp /tmp/dolt-linux-amd64/bin/dolt "$HOME/.local/bin/" \
    && rm -rf /tmp/dolt.tar.gz /tmp/dolt-linux-amd64
```

**Beads (bd) install** (direct binary to `~/.local/bin`):

```bash
BD_VERSION=0.62.0
curl -fsSL "https://github.com/steveyegge/beads/releases/download/v${BD_VERSION}/beads_${BD_VERSION}_linux_amd64.tar.gz" -o /tmp/beads.tar.gz \
    && tar -xzf /tmp/beads.tar.gz -C "$HOME/.local/bin" bd \
    && rm /tmp/beads.tar.gz
```

> **Known bug (as of v0.62.0):** Do NOT use the upstream `curl ... install.sh | bash` method inside Docker/WSL. The `detect_platform()` function in the install script captures its own stdout via command substitution, but the WSL-detection warning writes ANSI escape codes to stdout, corrupting the download URL. Use the direct binary download method above.

### If the project has its own setup script

Add the dolt and bd install blocks above to the existing script. Ensure:

1. `mkdir -p "$HOME/.local/bin"` runs before the installs
2. `export PATH="$HOME/.local/bin:$PATH"` is set in the script
3. Dolt installs before bd (bd depends on dolt at runtime)
4. Both installs are idempotent (check `command -v dolt` / `command -v bd` first)

### If the project has no setup script

Create `.devcontainer/setup.sh` with the install blocks above, wrapped in proper bash scaffolding:

```bash
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"

# Install dolt (database backend for beads)
if ! command -v dolt &>/dev/null; then
    DOLT_VERSION=1.83.6
    curl -fsSL "https://github.com/dolthub/dolt/releases/download/v${DOLT_VERSION}/dolt-linux-amd64.tar.gz" -o /tmp/dolt.tar.gz \
        && tar -xzf /tmp/dolt.tar.gz -C /tmp \
        && cp /tmp/dolt-linux-amd64/bin/dolt "$HOME/.local/bin/" \
        && rm -rf /tmp/dolt.tar.gz /tmp/dolt-linux-amd64
    echo "Installed dolt v${DOLT_VERSION} to ~/.local/bin/"
fi

# Install beads (bd) — distributed task graph tracker for AI agents
if ! command -v bd &>/dev/null; then
    BD_VERSION=0.62.0
    curl -fsSL "https://github.com/steveyegge/beads/releases/download/v${BD_VERSION}/beads_${BD_VERSION}_linux_amd64.tar.gz" -o /tmp/beads.tar.gz \
        && tar -xzf /tmp/beads.tar.gz -C "$HOME/.local/bin" bd \
        && rm /tmp/beads.tar.gz
    echo "Installed bd v${BD_VERSION} to ~/.local/bin/"
fi
```

---

## Step 3 — Ensure PATH includes `~/.local/bin`

The Dockerfile must set the PATH so that dolt and bd (installed by `setup.sh` to `~/.local/bin`) are available in all subsequent shells without requiring `.bashrc` sourcing.

Check the Dockerfile for this line:

```dockerfile
ENV PATH="/home/appuser/.local/bin:${PATH}"
```

Replace `appuser` with the actual username if different. This line should appear **after** the user creation block and **before** the `USER` directive.

If this `ENV` line is missing, add it. Without it, dolt and bd will only be on PATH in interactive bash sessions (via `.bashrc`), not in non-interactive contexts like VS Code tasks or lifecycle commands.

---

## Step 4 — Update devcontainer.json

Several changes may be needed in `devcontainer.json`. Apply only the parts that are not already present.

### 4a — Set containerUser

Ensure the container user matches the Dockerfile. Use `containerUser`, not `remoteUser`:

```json
"containerUser": "appuser"
```

Replace `appuser` with the actual username from the Dockerfile's `ARG USERNAME`.

### 4b — Set postCreateCommand

The setup script runs via `postCreateCommand` (not `onCreateCommand`). If the project uses the shared `setup.sh`, add or update:

```json
"postCreateCommand": "/bin/bash /workspaces/<project-name>/.devcontainer/setup.sh --beads"
```

If other flags are already present (e.g., `--claude --uv`), append `--beads`:

```json
"postCreateCommand": "/bin/bash /workspaces/<project-name>/.devcontainer/setup.sh --claude --uv --beads"
```

If the project does **not** use the shared `setup.sh`, point to the project's own setup script:

```json
"postCreateCommand": "bash .devcontainer/setup.sh"
```

### 4c — Add .beads bind mount (optional)

Ask the user: **"Do you want to persist the .beads database across container rebuilds via a bind mount?"**

If yes, add a mount entry:

```json
"mounts": [
  "source=${localWorkspaceFolder}/.beads,target=/workspaces/<project-name>/.beads,type=bind,consistency=cached"
]
```

If mounts already exist, append this entry to the existing array. The bind mount requires the `.beads/` directory to exist on the host before the container builds — add `mkdir -p .beads` to the `initializeCommand` or host-side initialize script.

If the user declines or does not care, skip the mount. The `.beads/` directory will be created inside the container by `bd init` and will live within the workspace bind mount (persisted as part of the project directory).

### 4d — Update initializeCommand (only if bind mount is used)

If you added the `.beads/` bind mount in 4c, ensure the host-side init creates the directory. If the project uses the shared `initialize.sh`:

```json
"initializeCommand": "bash ${localWorkspaceFolder}/.devcontainer/initialize.sh <project-name>"
```

The `.beads/` directory should also be created. Add `mkdir -p .beads` to the initialize script or to a separate command:

```json
"initializeCommand": "mkdir -p ${localWorkspaceFolder}/.beads && bash ${localWorkspaceFolder}/.devcontainer/initialize.sh <project-name>"
```

Only needed if the bind mount was added in 4c.

---

## Step 5 — Handle `.beads/` in `.gitignore`

Ask the user: **"Do you want to commit the .beads/ directory to git (shared task graph) or ignore it (local-only tracking)?"**

**Option A — Ignore it (recommended for most projects):**

Add to `.gitignore`:

```
# Beads local task graph database
.beads/
```

This is appropriate when:
- Using a Dolt remote for sync across machines
- Each developer has their own local task graph
- You want to avoid double-tracking (Dolt + git)

**Option B — Commit it (shared task graph):**

Do **not** add `.beads/` to `.gitignore`. This lets the team share a single task graph as a plain directory committed to the repo. Only choose this if the user explicitly asks for it.

Unless the user specifies otherwise, use Option A.

---

## Step 6 — Rebuild the container

After saving all changes, tell the user to rebuild:

- **VS Code**: `Ctrl+Shift+P` then "Dev Containers: Rebuild Container"
- **CLI**: `devcontainer build --workspace-folder .`

**BuildKit**: If the Dockerfile uses `--mount=type=cache` in any layer, the first line must be `# syntax=docker/dockerfile:1`. If this header is missing, add it as the very first line before telling the user to rebuild.

If the build fails, dispatch troubleshooting to the **builder agent** (`agents/builder/AGENT.md`).

---

## Step 7 — Post-rebuild verification

After the container rebuilds successfully, verify inside the container terminal:

```bash
which dolt                    # Should be /home/appuser/.local/bin/dolt (NOT /usr/local/bin/dolt)
which bd                      # Should be /home/appuser/.local/bin/bd (NOT /usr/local/bin/bd)
dolt version                  # Should print the dolt version (e.g., 1.83.6)
bd --version                  # Should print the beads version (e.g., 0.62.0)
```

Replace `appuser` with the actual container username. Both binaries must be in `~/.local/bin`, confirming they were installed by `setup.sh` as user-space tools (not in the Dockerfile).

Next, initialize beads and set up Claude Code hooks:

```bash
bd init                       # Initialize the task graph in the project
bd status                     # Should show beads project status
ls .beads/                    # Should show the database directory
```

Then configure Claude Code hooks (see Step 8).

---

## Step 8 — Configure Claude Code hooks and first-use commands

### Beads hooks for Claude Code

Beads hooks go in `.claude/settings.local.json` (not `.claude/settings.json`). These hooks run `bd prime` to load beads context at session start and before compaction:

```json
{
  "hooks": {
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
    ],
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
    ]
  }
}
```

If `.claude/settings.local.json` already exists with other content, merge the `hooks` section into it. If the file has existing hooks, add the `PreCompact` and `SessionStart` entries alongside them.

### First-use commands

Once beads is initialized and hooks are configured, the user can start working with the task graph:

```bash
bd create "Short description of a task"    # Create a new issue
bd list                                     # List all issues
bd ready                                    # Show issues ready to work on (all deps met)
bd show <issue-id>                          # Show details of a specific issue
bd start <issue-id>                         # Start working on an issue
bd done <issue-id>                          # Mark an issue as complete
bd prime                                    # Print full session context (used by hooks)
```

For distributed sync (optional):

```bash
bd dolt remote add origin <remote-url>     # Connect to a Dolt remote
bd dolt push origin main                   # Push task graph to remote
bd dolt pull origin main                   # Pull updates from remote
```

---

## Common pitfalls

| Mistake | Fix |
|---------|-----|
| Installing dolt or bd in the Dockerfile | Both are user-space tools installed by `setup.sh` to `~/.local/bin`. They do not belong in the Dockerfile. |
| Missing `curl` in Dockerfile | Ensure `curl` is in the `apt-get install` list — it is needed by setup.sh to download dolt and bd. |
| Missing `ENV PATH` in Dockerfile | The Dockerfile must have `ENV PATH="/home/appuser/.local/bin:${PATH}"` so dolt and bd are on PATH in non-interactive shells. |
| Beads installed before dolt in setup script | Dolt must install first — beads depends on it at runtime for `bd dolt` commands and database operations. |
| Using `onCreateCommand` instead of `postCreateCommand` | The setup script runs via `postCreateCommand`, not `onCreateCommand`. |
| Using `remoteUser` instead of `containerUser` | Use `"containerUser": "appuser"` in devcontainer.json. |
| `install.sh` fails with "bad range in URL" in Docker | Upstream bug: ANSI codes leak into download URL. Use the direct tarball download method, not the upstream install.sh pipe. |
| BD_VERSION set to wrong version | Current version is `0.62.0`. GitHub URL is `steveyegge/beads` (not `fission-codes/beads`). |
| `bd init` run outside project directory | Always run from the project root (e.g., `/workspaces/<project>`). The `.beads/` dir is created in the current working directory. |
| Hooks placed in `settings.json` instead of `settings.local.json` | Beads hooks (`bd prime` on SessionStart/PreCompact) go in `.claude/settings.local.json`. |
| `bd prime` not running on session start | Add the hooks to `.claude/settings.local.json` as shown in Step 8. Verify by starting a new Claude Code session and checking for beads context. |
| npm global prefix not set | If openspec is also installed via npm, the npm prefix must be configured to `~/.npm-global` to avoid EACCES errors. The shared `setup.sh` handles this automatically. |
| Committing `.beads/` unintentionally | Add `.beads/` to `.gitignore` unless the team explicitly wants a shared task graph. |
| Floating versions in setup script | Pin dolt and bd versions for reproducible installs. Bump manually when upgrading. |
| BuildKit cache mount fails | Add `# syntax=docker/dockerfile:1` as the first line of the Dockerfile to enable BuildKit syntax. |
| Bind mount fails because `.beads/` does not exist on host | Create `.beads/` in the `initializeCommand` or host-side init script before building. Only relevant if using a `.beads/` bind mount. |
