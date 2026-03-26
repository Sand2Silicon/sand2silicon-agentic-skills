---
name: generate-spec-beads
description: Generate Beads epics and issues from an OpenSpec change, producing a fully dependency-wired task graph ready for implementation. Use when an OpenSpec change has been planned and you need to create Beads issues to track implementation.
user_invocable: true
---

# File Beads from OpenSpec

Convert an OpenSpec change's `tasks.md` into a wired Beads dependency graph ready for `/implement-beads`.

**Input**: `/generate-spec-beads <change-name>` (e.g. `real-sentiment-data-feed`)

---

## Pre-flight: Start Dolt server once

**This is the single most important step.** Every `bd` command auto-starts and tries to auto-stop the Dolt server. Running many commands in sequence causes lock contention that silently breaks dep wiring. Start the server once and let it stay running for the whole session.

```bash
# Clear any stale lock files from previous sessions
rm -f /workspace/.beads/dolt-server.lock
rm -f /workspace/.beads/dolt/.dolt/noms/LOCK
rm -f /workspace/.beads/dolt/.dolt/stats/.dolt/noms/LOCK

# Start server and verify
bd dolt start && sleep 2 && bd stats
```

If `bd stats` fails, check `/workspace/.beads/dolt-server.log`. Fix before proceeding — do not continue with a broken server.

---

## Step 1: Read all spec artifacts

Use a parallel Explore agent to read everything at once:
- `openspec/changes/<name>/proposal.md`
- `openspec/changes/<name>/design.md`
- `openspec/changes/<name>/tasks.md`
- All `openspec/changes/<name>/specs/*/spec.md`

**While reading, verify technical accuracy against the actual codebase:**
- For every referenced class, function, method, or API: confirm it exists in source with the expected signature
- Note discrepancies — issue descriptions must reflect actual APIs, not aspirational pseudo-code
- Check `requirements.txt` for any new deps the spec adds

---

## Step 2: Plan the epic and issue structure (output before creating)

Before touching `bd`, write out the full plan. This catches structural mistakes before they're expensive to undo.

```
EPICS (N total):
  E1: <title> — tasks.md §1, §2 (N impl issues + N test issues)
  E2: <title> — tasks.md §3 (N impl issues + N test issues)
  ...
  E_review: Review & Build Gate (4 issues)

PER-FEATURE PATTERN (repeat for each task):
  T11_impl (Agent: implementation-agent) ─┐
  T11_test (Agent: test-writer-agent)  ───┤→ T11_review (Agent: review-agent)
  - Test and impl beads are INDEPENDENT — no dep edge between them
  - Review bead depends on BOTH impl and test completing

DEPENDENCY CHAINS:
  Sequential within E1: T11_review → T12_impl; T21_review → T25_impl
  Parallel within each task: T_impl ‖ T_test (both unblocked together)
  Cross-epic: E_cache blocks E_manager; E_agg blocks E_manager
  Unblocked at start: T11_impl, T11_test, T83_impl, T83_test (no deps)

TOTAL: N epics, M task issues (~X beads, including impl + test + review per feature)
```

If total exceeds 80 beads, confirm with the user before creating. If fewer than 10 total tasks across the whole change, consider whether epics are necessary or if flat issues suffice.

---

## Step 3: Create all epics

Create all epics in a single bash block, capturing IDs to a temp file. The server is already running — keep it running.

```bash
extract_id() { grep -oP '(?<=Created issue: )\S+'; }

EPIC_FOUNDATION=$(bd create \
  --title=": Epic – <title>" \
  --description="<what this epic implements>

OpenSpec tasks: X.Y-X.Y
Spec: specs/<name>/spec.md
Design: §<decision-name>
Agent: implementation-agent

Note: Epic descriptions use a human-readable summary format (OpenSpec tasks: X.Y-X.Y).
Only task-level issues need machine-parseable change:<name>/tasks.md: X.Y refs for sync-script tracking." \
  --type=feature --priority=1 2>&1 | extract_id)
echo "EPIC_FOUNDATION=$EPIC_FOUNDATION"

# ... repeat for each epic ...

# Save all epic IDs
cat > /tmp/beads_ids.env << EOF
EPIC_FOUNDATION=$EPIC_FOUNDATION
EPIC_CACHE=$EPIC_CACHE
# ...
EOF

echo "=== Epics created. Verifying... ==="
bd stats
```

**After creating epics:** run `bd stats` and confirm the open count matches your plan. If any ID is blank, that create failed — fix before continuing (see Error Recovery).

---

## Step 4: Create task issues (one epic at a time)

**ALWAYS use `--parent <epic_id>` when creating task issues under an epic.** This enables the indented tree view in `bd list`, `bd epic status` completion tracking, `bd children <id>` queries, and automatic label inheritance. Without `--parent`, issues render flat even when dependencies exist — the tree view only works with parent-child relationships, not dependency edges.

Source the IDs file and create task issues. **Use `--deps` at create time** for any issue whose predecessor was just created — this eliminates most of the dep-wiring pass later. **Use `--parent` at create time** to establish the epic hierarchy.

```bash
source /tmp/beads_ids.env

# First task in a chain — no predecessor yet
T11=$(bd create \
  --title=": X.Y <task title>" \
  --description="<what to implement>
Accept: <verbatim acceptance criteria from spec>
OpenSpec: change:<change-name>/tasks.md: X.Y
Spec: specs/<name>/spec.md §<section>
Agent: implementation-agent" \
  --type=task --priority=1 \
  --parent "$EPIC_FOUNDATION" 2>&1 | extract_id)
echo "T11=$T11"

# Parallel test bead for T11 — independent of impl, based on spec acceptance criteria
T11_TEST=$(bd create \
  --title=": X.Y Test <task title>" \
  --description="Write tests for <task> based on spec acceptance criteria.
Accept: Tests cover all acceptance scenarios from spec and JIRA criteria.
OpenSpec: change:<change-name>/tasks.md: X.Y
Spec: specs/<name>/spec.md §<section>
Agent: test-writer-agent
Note: Write tests from the SPEC, not from the implementation. Tests must be
written independently — do not read or depend on implementation code." \
  --type=task --priority=1 \
  --parent "$EPIC_FOUNDATION" 2>&1 | extract_id)
echo "T11_TEST=$T11_TEST"

# Per-feature review gate — depends on BOTH impl and test completing
T11_REVIEW=$(bd create \
  --title=": X.Y Review <task title>" \
  --description="Review implementation against spec and test coverage.
Accept: Impl satisfies all acceptance criteria; tests pass against impl.
OpenSpec: change:<change-name>/tasks.md: X.Y
Agent: review-agent
Note: File new beads for any gaps found and send back to implementation-agent." \
  --type=task --priority=1 \
  --parent "$EPIC_FOUNDATION" \
  --deps "$T11,$T11_TEST" 2>&1 | extract_id)
echo "T11_REVIEW=$T11_REVIEW"

# Next task in the chain — depends on prior task's REVIEW bead, not just impl
T12=$(bd create \
  --title=": X.Y <task title>" \
  --description="..." \
  --type=task --priority=1 \
  --parent "$EPIC_FOUNDATION" \
  --deps "$T11_REVIEW" 2>&1 | extract_id)
echo "T12=$T12"

# Task with multiple immediate predecessors
T25=$(bd create \
  --title=": X.Y <task title>" \
  --description="..." \
  --type=task --priority=1 \
  --parent "$EPIC_FOUNDATION" \
  --deps "$T21_REVIEW,$T22_REVIEW" 2>&1 | extract_id)
echo "T25=$T25"

# Append IDs to the file after each epic's batch
cat >> /tmp/beads_ids.env << EOF
T11=$T11
T11_TEST=$T11_TEST
T11_REVIEW=$T11_REVIEW
T12=$T12
T25=$T25
EOF
echo "=== Epic <name> issues created ==="
```

**Verify after each epic's batch:**
```bash
bd stats
```
Any blank ID means that create failed. Do not continue — fix the failed create first.

**Work one epic's issues per bash block.** Keeping blocks to 10-15 commands catches problems earlier and avoids losing all your IDs if the shell exits.

---

## Step 5: Wire remaining cross-epic dependencies

After all issues are created, wire the deps that couldn't be set at creation time (cross-epic, complex multi-predecessor chains).

**Always use `&& echo "OK" || echo "FAILED: <label>"` so failures are visible:**

```bash
source /tmp/beads_ids.env

# Cross-epic: each provider epic blocked by Foundation
bd dep add $EPIC_RSS $EPIC_FOUNDATION && echo "OK" || echo "FAILED: RSS<-FOUNDATION"
bd dep add $EPIC_CACHE $EPIC_FOUNDATION && echo "OK" || echo "FAILED: CACHE<-FOUNDATION"

# Manager epic blocked by all providers + cache + aggregation
for DEP in $EPIC_RSS $EPIC_CP $EPIC_CACHE $EPIC_AGG; do
  bd dep add $EPIC_MGR $DEP && echo "OK" || echo "FAILED: MGR<-$DEP"
done

# Review epic blocked by everything
for DEP in $EPIC_FOUNDATION $EPIC_RSS $EPIC_CACHE $EPIC_MGR $EPIC_PIPE \
           $EPIC_TEST_PROV $EPIC_TEST_CACHE $EPIC_SMOKE $EPIC_DOCS; do
  bd dep add $EPIC_REVIEW $DEP && echo "OK" || echo "FAILED: REVIEW<-$DEP"
done
```

Do NOT use `| tail -1` — the success message may not be the last line of output. Do NOT run dep wiring in background tasks or parallel subagents — they share the Dolt lock.

---

## Step 6: Verify final state

```bash
bd stats
bd ready            # confirm only the right issues are unblocked
bd blocked | head -20   # confirm blockers are correct
bd show $EPIC_REVIEW    # confirm review gate has all expected deps
```

**Expected state:**
- Unblocked: foundation tasks, standalone pure-function tasks, docs (no deps)
- Blocked: everything that has a real predecessor
- Review/build gate: fully blocked by all impl + test + smoke + docs epics

If anything looks wrong, add missing deps now with `bd dep add`.

---

## Issue content guidelines

Every issue description MUST include:

| Field | Example |
|-------|---------|
| What to implement | Brief prose, not just the title |
| `Accept:` | Verbatim acceptance criteria from the spec |
| `OpenSpec:` | `change:<change-name>/tasks.md: X.Y` |
| `Spec:` | `specs/<name>/spec.md §<section>` |
| `Design:` | `§<decision name>` (if the task implements a specific design decision) |
| `Agent:` | `implementation-agent` / `test-writer-agent` / `review-agent` |

**Agent roles:**
- **`implementation-agent`** — writes production code for the feature
- **`test-writer-agent`** — writes tests independently from the spec/acceptance criteria, NOT from the implementation. Tests should be derived from the spec scenarios and ultimately the JIRA ticket acceptance criteria. Runs in parallel with (but independently of) the implementation agent.
- **`review-agent`** — reviews completed work against spec, files new beads for gaps, sends action items back to the implementation agent

**Per-feature triad:** Every non-trivial task should produce three beads: impl + test + review. The impl and test beads are independent (no dep edge between them). The review bead depends on both. Downstream tasks depend on the review bead, not the impl bead directly.

Prefix every title with `: ` for traceability.

---

## Review & Build Gate epic (always include)

**IMPORTANT:** The build gate runs AFTER all implementation and per-feature reviews are complete. Do not run build/test validation gates while work is still in progress — partial implementations will cause spurious failures. Per-feature review gates (above) catch issues incrementally; the build gate is a final integration check.

The final epic gates on all other epics completing. It contains 3-4 issues:

1. **Requirements coverage audit** — verify every acceptance criterion in every spec is met by the implementation. File new beads for gaps; assign to implementation-agent.
2. **Full test suite + coverage** — run `pytest --cov=src`. File new beads for failures; assign to test-agent.
3. **Code quality audit** — check for: circular imports, unconfigurable hardcoded values, missing error handling at boundaries, deviations from `design.md` decisions. File new beads; assign to implementation-agent.
4. **Consolidated build gate** — `pip install -r requirements.txt && python -m src.<entrypoint>` and `pytest` must both pass. This bead is only closed when all preceding review issues are closed.

Wire the review issues sequentially (audit → test run → quality audit → build gate), so they form a linear chain within the review epic.

---

## Error recovery

**Server won't start / lock contention:**
```bash
pkill -f dolt 2>/dev/null; sleep 2
rm -f /workspace/.beads/dolt-server.lock
rm -f /workspace/.beads/dolt/.dolt/noms/LOCK
rm -f /workspace/.beads/dolt/.dolt/stats/.dolt/noms/LOCK
bd dolt start && sleep 2 && bd stats
```

**`bd create` returns blank ID:**
The create failed. Run the command again standalone (without `extract_id`) to see the full error:
```bash
bd create --title="..." --description="..." --type=task 2>&1
```
Fix the issue (usually a server connectivity problem), then rerun.

**Dep add failing:**
Run a single `bd dep add <issue> <dep>` and read the full output. Most common causes: server down (run recovery above), or one of the IDs is wrong (check `/tmp/beads_ids.env`).

---

## Anti-patterns

| Don't | Why |
|-------|-----|
| `bd dep add ... \| tail -1` | Success line may not be last; failures are hidden |
| Background bash tasks for bd commands | Share the Dolt lock → silent failures |
| Parallel subagents for bd create/dep-add | Same lock contention issue |
| Start without `bd dolt start` | Auto-start/stop cycle leaves stale locks |
| Wire all deps after all creates | Use `--deps` at create time for immediate predecessors |
| Create 50 issues then check stats | Check after each epic's batch, not at the very end |
| Assume background dep wiring succeeded | Always check `bd show <key-issue>` to verify the dep graph |
| Create task issues without `--parent` | Without `--parent`, `bd list` renders flat; `bd epic status` won't track completion; tree view is lost |
| Use `git worktree add` directly | Always use `bd worktree create` — it sets up a `.beads/redirect` file so `bd` commands in the worktree resolve to the main database. Without it, `bd` finds the worktree's local `.beads/` and starts a Dolt server with no database. |
