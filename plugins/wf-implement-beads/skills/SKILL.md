---
name: wf-implement-beads
description: Implement a body of work tracked in Beads, guided by OpenSpec artifacts. Use when Beads issues have been created for an OpenSpec change and implementation should begin or resume. Accepts an OpenSpec change name (e.g. fix-core-inference-pipeline), a Beads epic ID (e.g. workspace-3ti), or no argument to auto-detect active work.
---

# Implement Beads

Drive implementation of a body of work using Beads for task tracking and OpenSpec for spec context.

**Input**: One of:
- An OpenSpec change name: `/wf-implement-beads fix-core-inference-pipeline`
- A Beads epic ID: `/wf-implement-beads workspace-3ti`
- No argument: auto-detect from active/ready work

---

## Step 0: Pre-flight — ask the user about workflow mode

Before starting any work, prompt the user:

> **Workflow options:**
> 1. **Work in a git worktree?** (Recommended for large changes) — creates a feature branch off the current branch and works in an isolated worktree. Changes are reviewed before merging back.
> 2. **Work on the current branch?** — implements directly on the current branch. Still requires review before commit.
>
> **Choose: worktree / current branch**

**If worktree is chosen:**
```bash
# IMPORTANT: Use bd worktree, NOT git worktree add.
# bd worktree create sets up a .beads/redirect file so all bd commands
# in the worktree resolve to the main repo's .beads database.
# Without this, bd auto-discovers a local .beads/ in the worktree and
# starts a Dolt server against it — which has no database.
bd worktree create ".worktrees/<change-name>" --branch "impl/<change-name>"
cd ".worktrees/<change-name>"
```
All subsequent work happens in the worktree. At session close, changes are reviewed before merging.

**If current branch is chosen:**
Work proceeds on the current branch. No worktree is created.

Store the choice — it affects the session close procedure (Step 8).

---

## Step 1: Identify the body of work

**If a change name was given** (contains `-` and no `-` prefix, e.g. `fix-core-inference-pipeline`):
```bash
ls openspec/changes/<name>/          # Verify change exists
bd search "<name>" 2>/dev/null        # Find related epic
```

**If a Beads ID was given** (e.g. `workspace-abc`):
```bash
bd show <id>                          # Read epic description
```
Extract the OpenSpec change name from the epic description if present.

**If no argument given**, auto-detect:
```bash
bd list --status=in_progress --json  # Resume in-progress work first
bd ready                              # Then check unblocked work
ls openspec/changes/                  # List active changes
```
- If exactly one in-progress item or one active change: proceed
- If multiple: use **AskUserQuestion** to let the user choose

Always announce: "Implementing: **<change-name>** (epic: <id>)" and how to override.

---

## Step 2: Load spec context

Read these files before writing any code (paths relative to `openspec/changes/<change-name>/`):

| File | Purpose |
|------|---------|
| `proposal.md` | Why this change exists, goals/non-goals |
| `design.md` | Key decisions (D1–DN) — read before touching architecture |
| `specs/*/spec.md` | Requirements and acceptance scenarios per spec |
| `tasks.md` | Ordered task list with section numbers |

Read the following files for context:
- `openspec/changes/<name>/proposal.md`
- `openspec/changes/<name>/design.md`
- `openspec/changes/<name>/tasks.md`
- Each spec file listed in tasks.md or design.md

---

## Step 3: Orient with Beads

```bash
bd ready                         # Unblocked issues ready to work
bd list --status=in_progress     # Already claimed work
bd show <epic-id>                # Full epic context and dependency tree
```

Show the user:
- How many beads total / closed / remaining
- Which are unblocked right now
- Any already in-progress (resume these first)

---

## Step 4: Implement (loop until done or blocked)

### Parallelism first — identify concurrent work before starting

Before claiming any bead, scan the full dependency graph to find which beads can be worked concurrently:

```bash
bd ready                      # All unblocked beads right now
bd show <epic-id>             # Full dependency tree
```

**Group beads by wave**: beads with no dependencies between each other can be worked simultaneously. Always look for this before working sequentially.

### Use subagents and Team Agents for parallel execution

When multiple beads are unblocked and independent, **do not work them one at a time**. Instead:

- **Use `Agent` tool (subagents)** to fan out independent tasks in parallel — each subagent handles one bead end-to-end (claim → read spec → implement → close).
- **Use Claude Team Agents** when available for even higher concurrency on large bodies of work.
- **Work sequentially** only when tasks have true data dependencies (e.g., bead B requires an interface defined in bead A).

**Example parallel dispatch:**
```
Wave 1 (run in parallel):
  → Agent: implement workspace-5ka (add dependency)
  → Agent: implement workspace-olb (scaffold module)
  → Agent: implement workspace-q2r (write config loader)

Wave 2 (after Wave 1 closes, now unblocked):
  → Agent: implement workspace-7mn (integrates all three above)
```

After launching parallel agents, **wait for all to complete**, then run `bd ready` to identify the next wave.

### Per-bead workflow (each agent or sequential step)

For each bead being worked:

1. **Read the issue**
   ```bash
   bd show <id>
   ```
   Note: the `OpenSpec: change:<name>/tasks.md: X.Y` cross-ref and `Spec:` and `Design:` refs in the description.

2. **Claim it**
   ```bash
   bd update <id> --claim
   ```

3. **Read the spec context** for this specific task
   Locate the referenced requirement in the spec file. Understand acceptance scenarios before writing code.

4. **Implement the change**
   - Keep changes minimal and scoped to this task
   - Follow decisions in `design.md` — don't deviate without flagging
   - If you discover a design issue, pause and report before continuing

5. **Close the bead — VERIFY CLOSURE**
   ```bash
   bd close <id>
   ```
   **CRITICAL:** Check that the output contains `✓ Closed`. If it does not, the close FAILED. Do NOT proceed — diagnose the failure (usually a dependency still in_progress).

   **NEVER** pipe `bd close` output to `/dev/null`. Always read the output.

   The PostToolUse hook will automatically sync this to `tasks.md`.

6. **Verify wave completion after each wave**
   ```bash
   bd list --status=in_progress    # Must show ZERO in_progress for completed waves
   bd ready                        # Shows what unlocked
   ```
   If any beads are stuck in `in_progress`, STOP and investigate before proceeding.

**Pause if:**
- A task is unclear → ask before implementing
- Implementation contradicts a design decision → flag and ask
- An error or unexpected behavior blocks progress → report and wait
- A `bd close` fails → diagnose before continuing
- User interrupts

---

## Step 5: Review tasks — MUST use a separate review agent

When you reach review-type beads (title contains "Review:", "Spec compliance", or description contains `Agent: review-agent`):

**CRITICAL: Implementation agents must NOT review their own work.**

Spawn a **separate Agent** (subagent) for each review bead. The review agent:
1. Reads the review bead's description and acceptance criteria
2. Reads the relevant source code independently
3. Verifies each spec scenario is satisfied
4. If a scenario fails: the review agent reports the gap. The implementation agent then creates a new Beads task for the gap, implements it, and the review agent re-verifies.
5. Only when the review agent confirms all scenarios pass does the review bead get closed.

**Example:**
```
→ Agent (review): "Review workspace-tfu — read all spec scenarios in specs/*/spec.md,
   verify each is satisfied in the implementation code. Report gaps."
```

For the **code quality audit** bead, the review agent should also invoke the `/simplify` skill on changed files to check for reuse, quality, and efficiency issues.

For the **test suite** bead, the review agent MUST actually run:
```bash
python3 -m pytest tests/ --cov=src --cov-report=term-missing -v
```

---

## Step 6: Build/smoke gate (if a gate bead exists)

Run the project-specific validation steps listed in the gate bead's description. Common pattern:
```bash
# Install deps
pip install -r requirements.txt   # or npm install, etc.
# Run the entry point
python -m src.predictor            # or equivalent
# Run tests
python3 -m pytest tests/ -v
```
Confirm: no exceptions, output values are plausible, key log lines present.

**The build gate MUST actually be executed.** Do not close the build gate bead without running the commands and verifying the output.

---

## Step 7: Pre-commit verification — MANDATORY before commit

Before creating any commit, run this checklist:

```bash
# 1. Check for stuck beads
bd list --status=in_progress
# If ANY in_progress beads remain for this body of work → STOP. Do not commit.
# Alert the user: "N beads still in_progress: <list>. These must be completed or
# explicitly deferred before committing."

# 2. Run the sync script
python3 scripts/sync-openspec-tasks.py

# 3. Run the spec completion auditor
# /spec-completion-auditor <change-name>
# If auditor reports gaps → STOP. Do not commit until gaps are resolved.

# 4. Final test run
python3 -m pytest tests/ -v
```

**If beads remain in_progress:**
- List which beads are stuck and why
- Ask the user whether to: (a) complete them now, (b) defer them with `bd update <id> --status=open`, or (c) proceed anyway with the user's explicit approval
- Do NOT silently commit with incomplete beads

---

## Step 8: Session close

### If working in a worktree (Step 0 choice):
```bash
# 1. Commit in worktree
git add <changed-files>
git commit -m "<change-name>: <one-line summary>"

# 2. Return to main working directory
cd /workspace

# 3. Merge the feature branch
git merge --no-ff "impl/<change-name>"

# 4. Clean up worktree (bd worktree remove runs safety checks for uncommitted work)
bd worktree remove ".worktrees/<change-name>"

# 5. Push
bd dolt push
git push
```

### If working on current branch (Step 0 choice):
```bash
# 1. Stage and commit
git add <changed-files>
git commit -m "<change-name>: <one-line summary of what was implemented>"

# 2. Push beads and code
bd dolt push
git push
```

### Post-commit (both modes):

If the sync script reports all tasks complete, suggest archiving:
```
/openspec-archive-change <change-name>
```

---

## Output Format

**At start:**
```
## Implementing: fix-core-inference-pipeline
Epic: workspace-3ti | Progress: 0/24 beads closed
Unblocked now: workspace-5ka, workspace-olb
Mode: worktree (branch: impl/fix-core-inference-pipeline)
```

**After each wave** (display-format summaries):
```
Wave 1 complete (3 beads closed):
  ✓ workspace-5ka — Add chronos-forecasting to requirements.txt [change:fix-core-inference-pipeline/tasks.md: 1.1]
  ✓ workspace-olb — Scaffold DataFeed module [change:fix-core-inference-pipeline/tasks.md: 1.2]
  ✓ workspace-q2r — Write config loader [change:fix-core-inference-pipeline/tasks.md: 1.3]
  Verification: 0 in_progress | 4 now unblocked → dispatching Wave 2
```

**On completion:**
```
## Done: fix-core-inference-pipeline
24/24 beads closed ✓
tasks.md: 15/15 tasks complete ✓
Review: passed (independent agent verified)
Build gate: passed
Next: /openspec-archive-change fix-core-inference-pipeline
```

---

## Guardrails

- Always read the relevant spec section before implementing a task
- Follow design decisions in `design.md` — flag deviations, don't silently override
- **NEVER suppress `bd close` output** — always verify the `✓ Closed` confirmation
- **ALWAYS run `bd list --status=in_progress` after each wave** — catch stuck beads immediately
- **Review beads MUST be handled by a separate agent** — the implementation agent must not review its own work
- Build/smoke gates require actually running the code — not just claiming they passed
- **Do NOT commit while beads remain in_progress** — alert the user and get explicit direction
- Close beads one at a time as each task completes — don't bulk-close without doing the work
