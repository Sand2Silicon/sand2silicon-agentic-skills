---
name: implement-beads
description: Implement a body of work tracked in Beads, guided by OpenSpec artifacts. Use when Beads issues have been created for an OpenSpec change and implementation should begin or resume. Accepts an OpenSpec change name (e.g. fix-core-inference-pipeline), a Beads epic ID (e.g. workspace-3ti), or no argument to auto-detect active work.
---

# Implement Beads

Drive implementation of a body of work using Beads for task tracking and OpenSpec for spec context.

**Orchestration model:** You (the top-level AI) are the **orchestrator**, not a worker. Your primary job is to plan waves, dispatch subagents and Team Agents, track bead state, and manage the overall flow. You should be delegating implementation, test-writing, and review work to specialized agents — not doing it all sequentially yourself. Maximize concurrency: any beads that are independent of each other should be dispatched to parallel agents simultaneously. Use Beads to manage every step — claim, implement, review, close — so all work is tracked and auditable.

**Input**: One of:
- An OpenSpec change name: `/implement-beads fix-core-inference-pipeline`
- A Beads epic ID: `/implement-beads workspace-3ti`
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

**As the orchestrator, your default mode is parallel dispatch.** When multiple beads are unblocked and independent, **do not work them one at a time**. Instead:

- **Use `Agent` tool (classic subagents)** for focused, bounded tasks where token efficiency matters — e.g., a single bead with a clear spec and no coordination needed. Each subagent handles one bead end-to-end (claim → read spec → implement → close).
- **Use Team Agents** for waves with multiple independent beads that benefit from true parallel execution, shared workspace visibility, and longer-running work. Don't hesitate to use them whenever their concurrency and coordination benefits apply — they are the better tool for multi-bead waves.
- **Work sequentially** only when tasks have true data dependencies (e.g., bead B requires an interface defined in bead A).
- **Always check `bd ready` after each wave** to find newly unblocked work and dispatch the next wave immediately.

### Dispatch test-writer agents in parallel with implementation agents

Each feature bead should have a companion test bead (created by `/generate-spec-beads`). The test-writer agent and implementation agent work **concurrently and independently**:

- **Test-writer agent**: writes tests from the **spec and acceptance criteria** (and ultimately JIRA ticket acceptance criteria), NOT from the implementation code. It must not read or depend on the implementation.
- **Implementation agent**: writes production code for the feature.
- Both are dispatched simultaneously as part of the same wave.

**Example parallel dispatch with test-writers:**
```
Wave 1 (all dispatched in parallel):
  → Agent (impl):       implement workspace-5ka (add dependency)
  → Agent (test-writer): test workspace-5ka-test (tests for dependency — from spec)
  → Agent (impl):       implement workspace-olb (scaffold module)
  → Agent (test-writer): test workspace-olb-test (tests for module — from spec)
  → Agent (impl):       implement workspace-q2r (write config loader)
  → Agent (test-writer): test workspace-q2r-test (tests for config — from spec)

Wave 1 review (after impl + test beads close, review beads unblock):
  → Agent (review):     review workspace-5ka-review
  → Agent (review):     review workspace-olb-review
  → Agent (review):     review workspace-q2r-review

Wave 2 (after Wave 1 reviews close, now unblocked):
  → Agent (impl):       implement workspace-7mn (integrates all three above)
  → Agent (test-writer): test workspace-7mn-test
```

After launching parallel agents, **wait for all to complete**, then run `bd ready` to identify the next wave.

### Per-bead workflow (each agent or sequential step)

The orchestrator dispatches each bead to the appropriate agent type based on the `Agent:` field in the bead description. Each agent follows this workflow:

#### Implementation agent (`Agent: implementation-agent`)

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

#### Test-writer agent (`Agent: test-writer-agent`)

1. **Read the test bead** — `bd show <id>` to get the spec and acceptance criteria references
2. **Claim it** — `bd update <id> --claim`
3. **Read the spec, acceptance criteria, and JIRA ticket criteria** — write tests from these sources, NOT from the implementation code. The test-writer must work independently of the implementation agent.
4. **Write tests** that verify each acceptance scenario. Tests should be runnable even before the implementation exists (they will fail, which is expected — they define the contract).
5. **Close the bead** — `bd close <id>` and verify `✓ Closed`

#### Review agent (`Agent: review-agent`) — per-feature gate

1. **Read the review bead** — `bd show <id>` to understand what was implemented and tested
2. **Claim it** — `bd update <id> --claim`
3. **Independently read the source code and tests** — do not rely on the implementation agent's summary
4. **Verify each spec scenario** is satisfied by the implementation and covered by tests
5. **If gaps are found**: file new beads for each action item and assign them back to `implementation-agent` or `test-writer-agent`. Do NOT close the review bead. The orchestrator routes the new beads to the appropriate agents, and the review agent re-verifies after they complete.
6. **Only close when all scenarios pass** — `bd close <id>` and verify `✓ Closed`

#### Wave completion verification (orchestrator responsibility)

After each wave completes:
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

## Step 5: Final Review & Build Gate epic — separate review agents

**Note:** Per-feature review gates happen inline during Step 4 (see review-agent workflow above). This step covers the **final Review & Build Gate epic** that runs after all feature implementation and per-feature reviews are complete.

**CRITICAL: Implementation agents must NOT review their own work. All review beads — both per-feature and final — must be handled by separate review agents.**

Spawn a **separate Agent** (subagent) for each review bead in the gate epic. The review agent:
1. Reads the review bead's description and acceptance criteria
2. Reads the relevant source code independently
3. Verifies each spec scenario is satisfied
4. If a scenario fails: the review agent reports the gap. The orchestrator creates a new Beads task for the gap, dispatches it to an implementation or test-writer agent, and the review agent re-verifies after completion.
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

**IMPORTANT:** This gate runs ONLY after all implementation beads, test beads, and per-feature review beads are closed. Do not run build/test validation while work is still in progress — partial implementations cause spurious failures. The dependency graph enforces this (the gate bead should be blocked by all other epics), but verify with `bd show <gate-id>` before proceeding.

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
Wave 1 impl+test complete (6 beads closed):
  ✓ workspace-5ka (impl) — Add chronos-forecasting [change:.../tasks.md: 1.1]
  ✓ workspace-5ka-test (test) — Tests for chronos dep
  ✓ workspace-olb (impl) — Scaffold DataFeed module [change:.../tasks.md: 1.2]
  ✓ workspace-olb-test (test) — Tests for DataFeed module
  ✓ workspace-q2r (impl) — Write config loader [change:.../tasks.md: 1.3]
  ✓ workspace-q2r-test (test) — Tests for config loader
  Verification: 0 in_progress | 3 review beads now unblocked → dispatching reviews

Wave 1 reviews complete (3 beads closed):
  ✓ workspace-5ka-review — Review: passed
  ✓ workspace-olb-review — Review: passed, 1 gap filed → workspace-xyz (impl-agent)
  ✓ workspace-q2r-review — Review: passed
  Verification: 0 in_progress | 2 now unblocked → dispatching Wave 2
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

- **You are the orchestrator** — delegate implementation, test-writing, and review to subagents/Team Agents. Do not do everything sequentially yourself.
- **Maximize parallelism** — always check `bd ready` for independent beads and dispatch them concurrently. Sequential work is only for true data dependencies.
- **Test-writer agents work independently from implementation agents** — tests come from specs and acceptance criteria, never from reading the implementation code. Dispatch them in parallel.
- **Every feature goes through a review gate** — a review-agent verifies the work, files beads for gaps, and sends them back. Do not skip per-feature reviews.
- **Build/test validation gates run ONLY after all implementation is complete** — do not run them on work in progress.
- **All work is tracked in Beads** — every step (impl, test, review, gate) has a bead. Claim before starting, close on completion.
- Always read the relevant spec section before implementing a task
- Follow design decisions in `design.md` — flag deviations, don't silently override
- **NEVER suppress `bd close` output** — always verify the `✓ Closed` confirmation
- **ALWAYS run `bd list --status=in_progress` after each wave** — catch stuck beads immediately
- **Review beads MUST be handled by a separate agent** — the implementation agent must not review its own work
- Build/smoke gates require actually running the code — not just claiming they passed
- **Do NOT commit while beads remain in_progress** — alert the user and get explicit direction
- Close beads one at a time as each task completes — don't bulk-close without doing the work
