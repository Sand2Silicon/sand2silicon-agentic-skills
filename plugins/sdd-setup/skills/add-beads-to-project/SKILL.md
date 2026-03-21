---
name: add-beads-to-project
description: Integrate beads (`bd` CLI) into a project's dev container. Beads is a distributed, graph-based issue tracker for AI coding agents — it replaces markdown task plans with a dependency-aware task graph backed by an embedded version-controlled database. Use when the user wants to add beads to a devcontainer, set up the bd CLI, or configure Claude Code hooks for beads.
tools: Read, Edit, Write, Bash
---

# Add Beads to a Dev Container Project

This skill installs the `bd` (beads) CLI and its `dolt` database backend into an existing devcontainer, then wires up Claude Code hooks so beads context loads automatically at the start of every session.

**What beads provides**: A dependency-aware issue graph for AI coding agents. Issues are stored in a Dolt database (an embedded, version-controlled SQL store) — not markdown files — so the agent can query, update, and traverse task graphs programmatically. No external services or ports required.

---

## Step 1 — Read existing devcontainer state

Read the existing files before making changes:

- `.devcontainer/Dockerfile`
- `.devcontainer/devcontainer.json`

Identify:
- Which user the Dockerfile switches to (all installs must run as root, before any `USER` switch)
- Whether a `postCreateCommand` already exists in `devcontainer.json`
- Whether `.gitignore` exists at the repo root
- Whether `dolt` and `bd` are already present in the Dockerfile

---

## Step 2 — Add dolt to the Dockerfile

Beads requires `dolt` as its database backend. Install dolt before beads in the Dockerfile.

Pin the version using a build ARG for layer cache stability:

```dockerfile
# Install dolt (database backend for beads)
# Pinned version for layer cache stability — bump manually when upgrading.
ARG DOLT_VERSION=1.83.6
RUN curl -fsSL "https://github.com/dolthub/dolt/releases/download/v${DOLT_VERSION}/install.sh" | bash
```

**Placement rules**:
- Place it after `apt-get install` (requires `curl`)
- Place it **before** any `USER` directive that drops to a non-root user

If the Dockerfile does not already have `curl` installed, ensure it is in the `apt-get install` list.

---

## Step 3 — Install the `bd` CLI in the Dockerfile

> **Known bug (as of v0.61.0):** The upstream `install.sh` script fails when
> run inside Docker on WSL. The `detect_platform()` function captures its own
> stdout via command substitution, but the WSL-detection warning writes ANSI
> color codes to stdout, corrupting the download URL. A fix has been submitted
> upstream (redirecting warnings to stderr). **Until the fix is released, use
> the direct binary download method below instead of piping `install.sh`.**
>
> Before applying this workaround, check whether the bug has been fixed by
> inspecting the install script's `detect_platform()` function — if the WSL
> warning block already redirects output to `>&2`, the pipe method is safe.

**Preferred method (direct binary download — works everywhere):**

Pin the version using a build ARG for layer cache stability:

```dockerfile
# Install beads (bd) — distributed task graph tracker for AI agents
# Note: piping install.sh fails in WSL/Docker because ANSI color codes from the
# WSL-detection warning leak into the download URL. Download the binary directly.
# Pinned version for layer cache stability — bump manually when upgrading.
ARG BD_VERSION=0.61.0
RUN curl -fsSL "https://github.com/steveyegge/beads/releases/download/v${BD_VERSION}/beads_${BD_VERSION}_linux_amd64.tar.gz" -o /tmp/beads.tar.gz \
    && tar -xzf /tmp/beads.tar.gz -C /usr/local/bin bd \
    && rm /tmp/beads.tar.gz \
    && bd --version
```

**Alternative (once the upstream bug is fixed):**

```dockerfile
# Install beads (bd) — graph-based issue tracker for AI agents
RUN curl -fsSL https://raw.githubusercontent.com/steveyegge/beads/main/scripts/install.sh | bash
```

When run as root, both methods install the `bd` binary to `/usr/local/bin`, which is already on PATH for all users.

**Placement rules**:
- Place it after the dolt install (Step 2)
- Place it **before** any `USER` directive that drops to a non-root user

Do **not** use the npm or Go install alternatives in a Dockerfile — the curl/binary method is the simplest path with no runtime dependencies.

---

## Step 4 — Handle `.beads/` in `.gitignore`

The `.beads/` directory contains the local task graph database, version-controlled internally by Dolt.

**Option A — Ignore it (default, recommended for most projects):**

Add to `.gitignore`:

```
# Beads local task graph database
.beads/
```

This is appropriate when using a Dolt remote for sync, to avoid double-tracking.

**Option B — Commit it (shared task graph):**

Do **not** add `.beads/` to `.gitignore`. This lets the team share a single task graph as a plain directory backup. Only choose this if the user explicitly asks for it.

Unless the user specifies otherwise, use Option A.

---

## Step 5 — Rebuild the container

After saving all Dockerfile changes, rebuild the container:

- **VS Code**: `Ctrl+Shift+P` → "Dev Containers: Rebuild Container"
- **CLI**: `devcontainer build --workspace-folder .`

**BuildKit**: The Dockerfile must start with `# syntax=docker/dockerfile:1` if any layers use `--mount=type=cache`. If this header is missing, add it as the very first line.

---

## Step 6 — Post-rebuild one-time setup

> **Tell the user to run the following commands manually in the container terminal after rebuilding. These are one-time setup steps, not container lifecycle commands.**

```bash
# 1. Initialize the beads task graph for this project (run once per project)
bd init

# 2. Install Claude Code hooks so bd prime runs on session start
bd setup claude --project
```

Print this to the user clearly at the end of the skill:

```
✅ Beads is installed in your devcontainer.

After rebuilding, open a terminal in the container and run these two commands once:

  bd init
  bd setup claude --project

That's it — beads will automatically inject task context at the start of every Claude Code session.
```

If using a Dolt remote for distributed sync:

```bash
bd dolt remote add origin <remote-url>
```

---

## Verification

Inside the container terminal after running the one-time setup:

```bash
bd --version                  # Should print the beads version
which bd                      # Should be /usr/local/bin/bd
dolt version                  # Should print the dolt version
bd setup claude --check       # Should confirm hooks are installed
ls .beads/                    # Should show the database directory
bd prime                      # Should print session context
```

---

## Common pitfalls

| Mistake | Fix |
|---------|-----|
| Installing `bd` after `USER` switch in Dockerfile | The binary download needs root to write to `/usr/local/bin`. Place the `RUN` line before any `USER` directive. |
| Missing `curl` in Dockerfile | Ensure `curl` is in the `apt-get install` list before the dolt/beads install steps. |
| Beads installed before dolt | Dolt must be installed first — beads depends on it at runtime for `bd dolt` commands. |
| `install.sh` fails with "bad range in URL" on WSL/Docker | Upstream bug: ANSI codes leak into download URL. Use the direct binary download method in Step 3 until the fix is released. |
| `bd init` run outside project directory | Always `cd /workspace` (or the correct project root) before running `bd init`. The `.beads/` dir is created in the current working directory. |
| Using `bd setup claude` without `--project` | Without `--project`, hooks install globally. Use `--project` to keep hooks scoped to this project only. |
| Committing `.beads/` unintentionally | Add `.beads/` to `.gitignore` unless the team explicitly wants a shared task graph. |
| Floating versions in Dockerfile | Pin dolt and bd versions via `ARG` for reproducible, cache-friendly builds. Bump manually when upgrading. |
| BuildKit cache mount fails | Add `# syntax=docker/dockerfile:1` as the first line of the Dockerfile to enable BuildKit syntax. |
| `bd prime` not configured as a hook | Run `bd setup claude --project` after init — without the `SessionStart` hook, the agent has no beads context. |
