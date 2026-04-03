---
name: implement-beads
description: Implement a body of work tracked in Beads, guided by spec artifacts (OpenSpec, JIRA, or roadmap). Use when Beads issues exist and implementation should begin or resume. Accepts an OpenSpec change name (e.g. add-auth-middleware), a Beads epic ID (e.g. workspace-3ti), or no argument to auto-detect active work.
---

# Implement Beads

Drive implementation of Beads-tracked work. Beads is the execution engine; OpenSpec, JIRA, and roadmap epics provide context when available.

**Input** (one of):
- OpenSpec change name: `/implement-beads add-auth-middleware`
- Beads epic ID: `/implement-beads workspace-3ti`
- No argument: auto-detect from active/ready work

---

## Orchestration Model — READ FIRST

**You are the orchestrator, not a worker.** Your job: plan waves, dispatch child agents, track bead state, manage flow. You do not write code, author test suites, or write reviews — you delegate all of that.

**Hard rules:**
1. **Parallelize aggressively.** Before each wave, identify ALL independent beads and dispatch them simultaneously. Sequential only for true data dependencies.
2. **Use child agents for all work.** Each bead is handled by a dispatched agent — implementation, test-authoring, or review.
3. **Every non-trivial feature follows the impl/test/review triad.** Impl and test-writer agents run concurrently and independently. Review runs after both complete.
4. **Test suites are authored from specs and acceptance criteria, not implementation code.** Test-writer agents must never read the implementation.
5. **Review agents file gaps as new beads** routed back to impl/test agents. Never skip review gates.
6. **All work is tracked in Beads.** Claim before starting, close on completion, verify every closure.

**Agent selection:**
- **Classic SubAgents** (`Agent` tool): Best for focused, bounded tasks — one bead, clear spec, no cross-agent coordination. Faster and more token-efficient.
- **Team Agents** (when enabled in project config): Best for multi-bead waves needing shared workspace visibility or longer-running coordinated work. Prefer when their concurrency benefits apply.

Default to classic subagents for individual beads. Use Team Agents for coordinated wave dispatch when available.

**Model selection — use the right model for the job:**

| Agent role | Model | Rationale |
|---|---|---|
| **implementation-agent** | `sonnet` | Code generation is sonnet's strength; fast enough for parallel waves |
| **test-writer-agent** | `sonnet` | Structured, spec-driven test authoring — well within sonnet's capability |
| **review-agent** | `sonnet` | Code review against acceptance criteria — bounded reasoning |
| **Exploration / search subagents** | `haiku` | Read-only tasks (grep, glob, file reads) need speed, not deep reasoning |
| **Scaffolding / boilerplate agents** | `haiku` | Template expansion, config file creation, simple mechanical edits |
| **Orchestrator (you)** | `opus` | Planning waves, dependency analysis, judgment calls — run at opus |

When dispatching via the `Agent` tool, always pass the `model` parameter. Example: `Agent(model: "sonnet", ...)`. When dispatching exploration-only subagents (subagent_type: "Explore"), use `model: "haiku"`.

**Escalation:** If a sonnet agent fails a task or produces low-quality output, retry once at `opus` before filing a gap bead. Note the escalation in the wave summary.

---

## Step 0: Pre-flight

### 0a. Detect project context

Read project configuration to determine the toolchain. Check `CLAUDE.md`, then inspect for `pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, `Makefile`, etc.

Store these for all subagent prompts:

| Setting | Detect from | Fallback |
|---------|------------|----------|
| Package install | `pyproject.toml` with `[tool.uv]` → `uv sync`; `package.json` → `npm install` | `pip install -r requirements.txt` |
| Test execution command | CLAUDE.md or `pytest.ini` / `pyproject.toml [tool.pytest]` | `python3 -m pytest tests/ -v` |
| Lint command | CLAUDE.md or lint tool in deps | Skip if not found |
| Type check | CLAUDE.md or `mypy`/`pyright` in deps | Skip if not found |
| Source root | Top-level package dir (`app/`, `src/`, project name) | `.` |
| Entry point | CLAUDE.md or `pyproject.toml [project.scripts]` | None |

### 0b. Ensure Dolt server is running

Parallel subagents share the Dolt server. Without it running persistently, each `bd` command auto-starts/stops Dolt, causing lock contention.

```bash
if bd stats 2>/dev/null; then
  echo "Dolt server already running"
else
  rm -f .beads/dolt-server.lock .beads/dolt/.dolt/noms/LOCK .beads/dolt/.dolt/stats/.dolt/noms/LOCK
  bd dolt start && sleep 2 && bd stats
fi
```

If `bd stats` fails, check `.beads/dolt-server.log`. Fix before proceeding.

### 0c. Detect context sources

Determine which context layers are available:

```bash
ls openspec/changes/ 2>/dev/null                    # OpenSpec?
ls roadmap.md docs/roadmap.md 2>/dev/null            # Roadmap?
# JIRA: check if JIRA MCP server is configured in the environment
```

**Context hierarchy:**
- **JIRA** (when active): Ultimate authority for requirements and acceptance criteria. Query via JIRA MCP server — fetch once, cache, refer back when criteria are unclear. If JIRA and a spec conflict, JIRA wins.
- **OpenSpec** (when active): Provides design decisions, spec scenarios, task structure, and expanded acceptance criteria. This is where the bulk of implementation detail lives.
- **Roadmap** (when present): Groups work into phases/epics for batching. When JIRA is active, the roadmap is just an organizational bridge — track to JIRA ticket numbers, not roadmap phases. When no JIRA, roadmap epic descriptions provide milestone context, but OpenSpec specs/tasks still carry the full requirements.
- **None of the above**: Beads descriptions alone provide the work context.

Also scan ready beads for `Reference:` lines pointing to external codebases — note org/repo pairs for subagent prompts.

### 0d. Detect test folder conventions

Scan open and ready bead descriptions for `Test location:` or `Target:` fields that specify where tests should be written:

```bash
bd list --status=open 2>/dev/null | head -20
bd ready 2>/dev/null | head -5
```

If bead descriptions contain conventions like `Test location: tests/unit/` or `Target: tests/test_ported/`, note them for test-writer-agent prompts. If multiple folders are specified (e.g., `tests/test_ported/` for adapted reference tests, `tests/unit/` for spec-derived tests), list all. Default to the project's standard test directory if no conventions are specified.

### 0e. Ask workflow mode

> **Workflow options:**
> 1. **Worktree** (recommended for large changes) — isolated feature branch via `bd worktree create`
> 2. **Current branch** — work in place; changes staged for review, NOT auto-committed
>
> **Choose: worktree / current branch**

**If worktree:**
```bash
# ALWAYS use bd worktree, never git worktree add.
# bd worktree create sets up .beads/redirect so bd commands resolve to the main database.
bd worktree create ".worktrees/<change-name>" --branch "impl/<change-name>"
cd ".worktrees/<change-name>"
```

**If current branch:** Work proceeds in place. Changes are staged for user review — do NOT commit automatically.

Store the choice for Step 7.

---

## Step 1: Identify the body of work

**If a change name was given:**
```bash
ls openspec/changes/<name>/ 2>/dev/null    # Verify change exists (if OpenSpec active)
bd search "<name>" 2>/dev/null              # Find related epic
```

**If a Beads epic ID was given:**
```bash
bd show <id>                                # Read epic description
```
Extract the change name from the epic description if present.

**If no argument given**, auto-detect:
```bash
bd list --status=in_progress --json         # Resume in-progress work first
bd ready                                     # Check unblocked work
ls openspec/changes/ 2>/dev/null            # List active changes
```
- If exactly one candidate: proceed
- If multiple: **AskUserQuestion** to let the user choose

Announce: "Implementing: **\<change-name\>** (epic: \<id\>)"

---

## Step 2: Load context

### OpenSpec (when active)

Read before writing any code (paths relative to `openspec/changes/<change-name>/`):

| File | Purpose |
|------|---------|
| `proposal.md` | Goals, non-goals, motivation |
| `design.md` | Key decisions (D1–DN) — read before touching architecture |
| `specs/*/spec.md` | Requirements and acceptance scenarios |
| `tasks.md` | Ordered task list with section numbers |

### JIRA (when active)

JIRA requirements should already be reflected in the OpenSpec artifacts and bead descriptions from earlier planning phases. Verify by spot-checking key tickets via JIRA MCP. Cache the acceptance criteria — these are ground truth for "done." When a bead's acceptance criteria and JIRA conflict, JIRA wins. Always refer back to JIRA when acceptance criteria are ambiguous during implementation.

### Roadmap (when active, no JIRA)

Read `roadmap.md` and identify which epic this work belongs to. Track which roadmap epic tasks are being addressed.

### Mark spec-tasks in progress

When OpenSpec is active, update `tasks.md` entries covered by this session's beads from `[ ]` to `[~]` to indicate work is underway.

---

## Step 3: Orient with Beads

```bash
bd ready                         # Unblocked issues ready to work
bd list --status=in_progress     # Already claimed — resume these first
bd show <epic-id>                # Full dependency tree
```

Show the user:
- Total / closed / remaining beads
- Which are unblocked now (grouped by type: impl, test-authoring, review)
- Any in-progress beads (resume these first)

---

## Step 4: Implement — parallel waves

Steps 4 and 5 overlap in time. As soon as a feature's impl+test beads close, its review bead unblocks and Step 5 review agents launch — while the next wave of implementation is already running. Step 6 (build/validate) is the only strictly sequential gate: it runs once, after every bead in both steps is closed.

### 4a. Plan waves

Before claiming any bead, map the full dependency graph:

```bash
bd ready                         # All currently unblocked
bd show <epic-id>                # Dependency tree
```

Group beads into waves — beads with no mutual dependencies go in the same wave. Within each wave, identify impl/test-authoring pairs for simultaneous dispatch.

### 4b. Dispatch agents

**Default mode is parallel dispatch.** When N impl/test-authoring bead pairs are unblocked and independent, dispatch all N pairs simultaneously.

```
Wave 1 (all dispatched in parallel):
  -> Agent (impl, model=sonnet):        workspace-5ka  — add cache layer
  -> Agent (test-writer, model=sonnet): workspace-5kt  — author tests for cache layer (from spec)
  -> Agent (impl, model=sonnet):        workspace-olb  — scaffold API module
  -> Agent (test-writer, model=sonnet): workspace-olt  — author tests for API module (from spec)
[wait for all to complete]

Wave 1 reviews (review beads unblock after impl+test-authoring close):
  -> Agent (review, model=sonnet): workspace-5kr  — review cache layer
  -> Agent (review, model=sonnet): workspace-olr  — review API module
[wait; handle gap beads if filed]

Wave 2 (unblocked after Wave 1 reviews close):
  -> Agent (impl, model=sonnet):        workspace-7mn  — integrate cache + API
  -> Agent (test-writer, model=sonnet): workspace-7mt  — author integration tests
```

After each wave completes, run `bd ready` to identify the next wave and dispatch immediately.

### 4c. Per-agent workflows

The `Agent:` field in each bead's description determines which agent type handles it.

#### Implementation agent (`Agent: implementation-agent`)

1. `bd show <id>` — read the issue; note `OpenSpec:`, `Spec:`, `Design:`, `Accept:` refs
2. `bd update <id> --claim`
3. Read the spec/acceptance criteria for this task before coding
4. **If bead has `Reference:` lines** — fetch source from the external repo via GitHub MCP (`mcp__github__get_file_contents`). Adapt to fit the target project; do not copy blindly. Note any reference test files for the test-writer agent.
5. Implement. Keep changes minimal and scoped. Follow `design.md` decisions — flag deviations, don't silently override.
6. `bd close <id>` — **verify output contains `Closed`**. If not, diagnose before continuing.

#### Test-writer agent (`Agent: test-writer-agent`)

1. `bd show <id>` — read spec/acceptance refs
2. `bd update <id> --claim`
3. Read the spec and acceptance criteria. **If JIRA active**, also check JIRA ticket criteria — these are ground truth.
4. **Author tests from specs and acceptance criteria ONLY — never from implementation code.** Test suites define the contract and should be valid before the implementation exists.
5. **If bead has `Reference:` lines pointing to existing test files** — fetch and adapt into a `ported` test suite (e.g., `tests/ported/test_<feature>.py`). Label clearly. These complement spec-derived tests.
6. `bd close <id>` — verify `Closed`

#### Review agent (`Agent: review-agent`)

1. `bd show <id>` — read review scope and acceptance criteria
2. `bd update <id> --claim`
3. **Independently** read implementation code and the authored test suite — do not rely on other agents' summaries
4. **Execute the test suite** against the implementation using the detected test execution command
5. Verify each acceptance scenario is satisfied by the code AND covered by test cases
6. Invoke `/simplify` on changed files for quality/efficiency check
7. **If gaps found:** create a new bead for each gap:
   ```bash
   bd create --title="<prefix>: Gap — <description>" \
     --description="<what is missing or incorrect>
   Accept: <specific criteria for the fix>
   OpenSpec: change:<change-name>/tasks.md: X.Y
   Agent: implementation-agent" \
     --type=task --parent <epic-id> \
     --deps <review-bead-id>
   ```
   Always include `Agent:` (route to `implementation-agent` or `test-writer-agent`) and `OpenSpec:` (for sync tracking) in gap bead descriptions. Report gap bead IDs to the orchestrator. Do NOT close the review bead.
8. After gap beads are resolved by the orchestrator: re-verify
9. **Only close when all scenarios pass.** `bd close <id>` — verify `Closed`

### 4d. Wave completion verification (orchestrator)

After each wave:
```bash
bd list --status=in_progress     # Must be ZERO for completed waves
bd ready                         # What unlocked next
```
If any beads are stuck in `in_progress`, STOP and investigate before proceeding.

**Sync tasks.md after every wave** (if OpenSpec active) — do not wait until session end:
```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/sync-openspec-tasks.py
```
Review the output. If tasks that should have been marked `[x]` were skipped, check that the closed bead descriptions contain `OpenSpec: change:<name>/tasks.md: X.Y` refs for **all** tasks that bead covers — not just the first. Fix missing refs with `bd update <id> --description="..."` before continuing.

### 4e. Subagent prompt template

Include this context in every subagent dispatch. **Always set the `model` parameter** per the model selection table above.

```
Agent(
  model: "<sonnet|haiku>",                    # Per model selection table
  subagent_type: "<general-purpose|Explore>",  # Explore + haiku for read-only tasks
  prompt: """
    Bead: <id> — <title>
    Role: implementation-agent | test-writer-agent | review-agent
    Project: test-run=<cmd>, lint=<cmd>, install=<cmd>, source_root=<path>
    <if JIRA active>  JIRA: <ticket-key> — acceptance criteria cached from MCP
    <if reference repos>  Reference: use mcp__github__get_file_contents owner="<org>" repo="<repo>"
    <if test folder conventions>  Test file locations: <list from Step 0d>
    <if test-writer>  Author tests from spec/acceptance criteria ONLY — do not read implementation code.
    <if review-agent>  File gap beads for issues found — do not fix them. Only close when all criteria verified.

    Steps: bd show <id> -> bd update <id> --claim -> [do work] -> bd close <id> (verify Closed)
  """
)
```

### Pause conditions

- Task unclear → ask before implementing
- Design contradiction → flag and ask
- Error blocks progress → report and wait
- `bd close` fails → diagnose before continuing
- User interrupts

---

## Step 5: Build/smoke gate

**Runs ONLY after ALL implementation, test-authoring, and review beads are closed.** Never mid-implementation — partial code causes spurious failures.

```bash
# Confirm readiness
bd list --status=in_progress                        # Must be EMPTY
bd list --status=open | grep -v "BUILD\|GATE"       # Must be EMPTY (only gate bead remains)
```

Run validation using the commands detected in Step 0:
```bash
<package_install>                                    # Install/sync deps
<entry_point>                                        # Run entry point (if detected)
<test_execution_command> --cov=<source_root>          # Execute full test suite + coverage
<lint_command>                                        # Lint (if configured)
<type_check_command>                                  # Type check (if configured)
```

**The gate MUST actually execute.** Do not close the gate bead without running the commands and verifying output.

---

## Step 6: Pre-commit verification — MANDATORY

```bash
# 1. Check for stuck beads
bd list --status=in_progress
# If ANY remain → STOP. Do not proceed.

# 2. Sync spec state — MANDATORY (if OpenSpec active)
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/sync-openspec-tasks.py
# Review script output. Every closed bead's tasks should now be [x].
# If tasks remain [ ] after sync, bead descriptions are missing OpenSpec refs.
# Fix the refs or manually mark tasks before proceeding — do not skip this check.

# 3. Spec completion audit — MANDATORY (if OpenSpec active)
# This is NOT optional. Catches bead/task mismatches the sync script can't resolve
# (e.g., multi-task beads with incomplete refs, manually closed beads, coverage gaps).
/spec-completion-auditor <change-name>
# If gaps reported → STOP. Resolve all mismatches before proceeding.

# 4. Final test suite execution
<test_execution_command>
```

**If beads remain in_progress:** list them, explain why, ask the user: (a) complete now, (b) defer with `bd update <id> --status=open`, or (c) proceed with explicit approval. Do NOT silently proceed.

---

## Step 7: Session close

### Worktree mode
```bash
# 1. Commit in worktree
git add <changed-files>
git commit -m "<prefix><change-name>: <summary>"

# 2. Return to original working directory
cd <original-directory>

# 3. Merge the feature branch
git merge --no-ff "impl/<change-name>"

# 4. Regenerate build artifacts if applicable
# Generated files (gRPC stubs, protobuf, codegen output) are gitignored and
# do NOT survive a worktree merge. Check if any were added or modified:
git diff --name-only HEAD~1 | grep -E '\.(proto|graphql|thrift)$'
# If matches: run the project's code generation command detected in Step 0a.
# Example: ./generate-grpc-code.sh
# Verify generated files exist before proceeding.

# 5. Clean up (bd worktree remove runs safety checks)
bd worktree remove ".worktrees/<change-name>"
rmdir ".worktrees" 2>/dev/null || true  # Remove empty parent dir if leftover

# 6. Push (with user approval)
git push
```

### Current branch mode
```bash
# Stage changes for user review — DO NOT commit automatically
git add <changed-files>
git status
```
Present staged changes and suggest a commit message. The user decides when to commit.

### Ticket/change prefix for commits

When JIRA is active, prefix with the **JIRA story** (not the epic) that the bead belongs to: `PROJ-123: 1.1 add cache layer`. This enables per-story commit grouping for PR splitting. When using a roadmap epic (no JIRA), prefix with the epic identifier. Otherwise, use the change name alone.

Structured commit message format:
```
<PROJ-123>: <task-number> <short description>

Bead: <bead-id>
OpenSpec: change:<change-name>/tasks.md: X.Y
```

The JIRA story ID on the first line enables `git log --grep="PROJ-123"` to extract all commits for a specific story. The `Bead:` trailer links back to the issue tracker.

### PR submission (after pre-commit verification passes)

When JIRA is active and the change spans multiple stories, offer the user a choice before pushing:

> **PR submission options:**
> 1. **Single PR** — one PR for the entire change (fast, simple review)
> 2. **Per-ticket PRs** — split into separate PRs per JIRA story (granular review, traceable)
>
> Choose: single / per-ticket

**If per-ticket:**
```bash
# 1. Identify unique JIRA stories from closed beads
STORIES=$(bd list --status=closed --parent $EPIC_ID --json | \
  jq -r '.[].external_ref' | grep '^jira:' | sort -u | sed 's/^jira://')

# 2. For each story, create a branch with its commits
PREV_BRANCH="main"
for STORY in $STORIES; do
  git checkout -b "pr/$STORY" "$PREV_BRANCH"
  # Cherry-pick commits matching this story
  git log "impl/<change-name>" --grep="$STORY" --format="%H" --reverse | \
    xargs git cherry-pick
  PREV_BRANCH="pr/$STORY"  # Stack dependent stories
done

# 3. Create PRs (with user approval for each)
for STORY in $STORIES; do
  gh pr create --base main --head "pr/$STORY" \
    --title "$STORY: <story title>" \
    --body "Part of <change-name>."
done
```

**Notes:**
- If stories have dependencies (Story B depends on Story A's changes), stack the branches: B's base is A's branch.
- Spec/doc files (openspec/, .beads/) should be excluded from per-ticket PRs — they are process artifacts, not shippable code. Commit them separately or add `openspec/** linguist-generated=true` to `.gitattributes` so GitHub collapses them.
- If cherry-pick conflicts arise, report to user and offer to resolve or fall back to a single PR.

### Post-session (both modes)

When OpenSpec is active and all beads are closed:
1. Run `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/sync-openspec-tasks.py` to mark spec-tasks `[x]`
2. Run `/spec-completion-auditor <change-name>` to verify completeness
3. If all tasks verified: suggest `/openspec-archive-change <change-name>`

---

## Output Format

**At start:**
```
## Implementing: <change-name>
Epic: <id> | Progress: 0/N beads closed
Unblocked: <list of ready beads by type>
Mode: <worktree | current branch>
Context: <OpenSpec | JIRA PROJ-123 | Roadmap Phase 2 | Beads only>
```

**After each wave:**
```
Wave 1 impl+test-authoring complete (N beads closed):
  V <id> (impl)        [sonnet] — <title>
  V <id> (test-writer) [sonnet] — <title>
  Verification: 0 in_progress | N review beads unblocked -> dispatching reviews

Wave 1 reviews (N closed):
  V <id> — Review: passed [sonnet]
  ! <id> — Review: 1 gap filed -> <gap-id> (routed to impl-agent)
  ^ <id> — Escalated to opus after sonnet failure; passed on retry
```

**On completion:**
```
## Done: <change-name>
N/N beads closed
Spec: M/M tasks complete   (if OpenSpec active)
Reviews: passed
Build gate: passed
Next: <suggested action>
```

---

## Guardrails

- **You are the orchestrator** — delegate all implementation, testing, and review to child agents
- **Parallelize by default** — `bd ready` for independent beads, dispatch concurrently; sequential only for true data dependencies
- **Test-writer agents work from specs, not implementation** — dispatch in parallel with (not after) implementation agents
- **Every feature goes through review** — a separate review-agent verifies, files gap beads, and iterates
- **Build gate runs ONLY after all beads close** — never mid-implementation
- **Never suppress `bd close` output** — always verify the `Closed` confirmation
- **Always verify wave completion** — `bd list --status=in_progress` after each wave; catch stuck beads immediately
- **Review agents never review their own work** — separation of concerns is mandatory
- **No auto-commit on current branch** — stage and present to user
- **Use `bd worktree create`, never `git worktree add`** — bd sets up the database redirect
- **All work tracked in Beads** — claim before starting, close on completion, file gaps as beads
- **Close beads individually** as tasks complete — no bulk-close without doing the work
- **Sync tasks.md after every wave** — run sync script, verify output, catch missing OpenSpec refs early; do not defer to session end
- **Never skip the spec-completion-auditor** — it catches what the sync script misses (multi-task beads, incomplete refs, manual gaps); it is NOT optional
- **Post-merge: regenerate build artifacts** — generated code (gRPC, protobuf, codegen) is gitignored and will not survive a worktree merge; check and regenerate before pushing
- **CLAUDE.md is not authoritative for plugin scripts** — if CLAUDE.md says a plugin script is a stub or disabled, verify against the actual script before skipping it

ARGUMENTS: $ARGUMENTS
- Follow `design.md` decisions — flag deviations, don't silently override
- Build/validate gate requires actually running the code, not claiming it passed
