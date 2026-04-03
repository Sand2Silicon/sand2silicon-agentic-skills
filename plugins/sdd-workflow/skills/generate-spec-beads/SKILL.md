---
name: generate-spec-beads
description: Generate Beads epics and issues from an OpenSpec change (or equivalent task source), producing a fully dependency-wired task graph ready for /implement-beads. Use when planning is complete and you need to create Beads issues to track implementation.
user-invocable: true
---

# File Beads from Spec

Convert a planned body of work into a wired Beads dependency graph ready for `/implement-beads`.

**Input**: `/generate-spec-beads <change-name>` (e.g. `add-auth-middleware`)

**Prerequisites:** OpenSpec artifacts should exist at `openspec/changes/<change-name>/`. Use `/plan-spec` or `/spec-from-tickets` to generate them, or create them manually with `/opsx:propose`.

**Primary path:** OpenSpec `tasks.md` is the task source. JIRA ticket acceptance criteria are the ultimate authority when active — if a spec and JIRA conflict, JIRA wins. A roadmap, when present, groups work into phases but is not itself a requirements source; specs/tasks carry the full detail.

---

## Pre-flight

### Ensure Dolt server is running

Start the Dolt server once and keep it running for the whole session. Without a persistent server, each `bd` command auto-starts and auto-stops Dolt, which causes lock contention when running many commands in sequence.

```bash
# Check if already running
if bd stats 2>/dev/null; then
  echo "Dolt server already running"
else
  # Clear stale locks from previous sessions, then start
  rm -f .beads/dolt-server.lock
  rm -f .beads/dolt/.dolt/noms/LOCK
  rm -f .beads/dolt/.dolt/stats/.dolt/noms/LOCK
  bd dolt start && sleep 2 && bd stats
fi
```

If `bd stats` fails, check `.beads/dolt-server.log`. Fix before proceeding.

### Detect context sources

```bash
ls openspec/changes/<name>/ 2>/dev/null        # OpenSpec change exists?
ls roadmap.md docs/roadmap.md 2>/dev/null      # Roadmap available?
# JIRA: check if MCP server is configured
```

**If JIRA is active:** JIRA requirements should already be reflected in the OpenSpec artifacts from the spec planning phase. Verify this by spot-checking key tickets via JIRA MCP. If any JIRA acceptance criteria are missing from the specs, they must be reflected in bead `Accept:` fields — JIRA is the ultimate authority.

**Ticket prefix:** When JIRA is active, all bead titles start with the ticket number (e.g. `PROJ-123: 1.1 Add cache layer`). When using a roadmap epic (no JIRA), prefix with the epic identifier. Otherwise, titles start with the task number directly.

---

## Step 1: Read all spec artifacts

Use a parallel Explore agent to read everything at once:
- `openspec/changes/<name>/proposal.md`
- `openspec/changes/<name>/design.md`
- `openspec/changes/<name>/tasks.md`
- All `openspec/changes/<name>/specs/*/spec.md`

**While reading, verify technical accuracy against the actual codebase:**
- For every referenced class, function, method, or API: confirm it exists with the expected signature
- Note discrepancies — issue descriptions must reflect actual APIs, not aspirational pseudo-code
- Check dependency files (`requirements.txt`, `package.json`, etc.) for any new deps the spec adds

**If JIRA active:** Cross-reference spec acceptance criteria with JIRA ticket criteria via MCP. JIRA is the ultimate authority — if the spec missed or softened a JIRA requirement, the bead must reflect the JIRA version.

**If bead descriptions need reference codebases:** Note any external repos referenced in the spec for inclusion as `Reference:` lines in bead descriptions.

---

## Step 2: Plan the epic and issue structure (output before creating)

Before touching `bd`, write out the full plan. This catches structural mistakes before they're expensive to undo.

```
EPICS (N total):
  E1: <prefix>: <title> -- tasks.md S1, S2 (N impl + N test + N review issues)
  E2: <prefix>: <title> -- tasks.md S3 (N impl + N test + N review issues)
  ...
  E_review: <prefix>: Review & Build Gate (3-4 issues)

PER-FEATURE PATTERN (repeat for each non-trivial task):
  T11_impl  (Agent: implementation-agent) --+
  T11_test  (Agent: test-writer-agent)   ---+-> T11_review (Agent: review-agent)
  - Impl and test beads are INDEPENDENT -- no dep edge between them
  - Review bead depends on BOTH impl and test completing
  - Downstream tasks depend on the REVIEW bead, not impl directly

DEPENDENCY CHAINS:
  Sequential within epic: T11_review -> T12_impl + T12_test
  Parallel within each task: T_impl || T_test (both unblocked together)
  Cross-epic: E_cache blocks E_manager; E_api blocks E_manager
  Unblocked at start: T11_impl, T11_test, T41_impl, T41_test (no deps)

TOTAL: N epics, M issues (~X beads including impl + test + review per feature)
```

If total exceeds 80 beads, confirm with the user before creating. If fewer than 10 total tasks, consider whether epics add value or flat issues suffice.

---

## Step 3: Create all epics

Create all epics in a single bash block, capturing IDs. The server is already running — keep it running.

```bash
extract_id() { grep -oP '(?<=Created issue: )\S+'; }

EPIC_FOUNDATION=$(bd create \
  --title="<prefix>: Epic -- <title>" \
  --description="<what this epic implements>

OpenSpec tasks: X.Y-X.Y
Spec: specs/<name>/spec.md
Design: S<decision-name>

Note: Epic descriptions use human-readable summary format.
Only task-level issues need machine-parseable change:<name>/tasks.md: X.Y refs." \
  --type=feature --priority=1 2>&1 | extract_id)
echo "EPIC_FOUNDATION=$EPIC_FOUNDATION"

# ... repeat for each epic ...

cat > /tmp/beads_ids.env << EOF
EPIC_FOUNDATION=$EPIC_FOUNDATION
EPIC_CACHE=$EPIC_CACHE
# ...
EOF

echo "=== Epics created. Verifying... ==="
bd stats
```

**After creating epics:** run `bd stats` and confirm the open count matches your plan. If any ID is blank, that create failed — fix before continuing.

---

## Step 4: Create task issues (one epic at a time)

**ALWAYS use `--parent <epic_id>` when creating task issues.** This enables tree view in `bd list`, `bd epic status` tracking, `bd children <id>` queries, and label inheritance. Without `--parent`, issues render flat.

**Use `--deps` at create time** for immediate predecessors. **Use `--parent` for epic hierarchy.**

```bash
source /tmp/beads_ids.env

# Implementation bead — first task in chain, no predecessor
T11=$(bd create \
  --title="<prefix>: X.Y <task title>" \
  --description="<what to implement>
Accept: <acceptance criteria from spec; JIRA criteria when active>
OpenSpec: change:<change-name>/tasks.md: X.Y
Spec: specs/<name>/spec.md S<section>
Design: S<decision> (if applicable)
Agent: implementation-agent
<Reference: org/repo#path/to/file.ext (if porting from external codebase)>" \
  --type=task --priority=1 \
  --external-ref="<jira:PROJ-123 when JIRA active>" \
  --parent "$EPIC_FOUNDATION" 2>&1 | extract_id)
echo "T11=$T11"

# Test bead — independent of impl, based on spec acceptance criteria
T11_TEST=$(bd create \
  --title="<prefix>: X.Y Test <task title>" \
  --description="Write tests for <task> based on spec acceptance criteria.
Accept: Tests cover all acceptance scenarios from spec; include JIRA criteria when active.
OpenSpec: change:<change-name>/tasks.md: X.Y
Spec: specs/<name>/spec.md S<section>
Agent: test-writer-agent
Note: Write tests from the SPEC and acceptance criteria, not from the implementation.
Tests must be written independently -- do not read or depend on implementation code.
<Reference: org/repo#tests/test_feature.py (if porting tests from external codebase)
Target: tests/ported/test_<feature>.py (label ported tests clearly)>" \
  --type=task --priority=1 \
  --parent "$EPIC_FOUNDATION" 2>&1 | extract_id)
echo "T11_TEST=$T11_TEST"

# Per-feature review gate — depends on BOTH impl and test
T11_REVIEW=$(bd create \
  --title="<prefix>: X.Y Review <task title>" \
  --description="Review implementation against spec and verify test coverage.
Accept: Impl satisfies all acceptance criteria; tests pass against impl.
OpenSpec: change:<change-name>/tasks.md: X.Y
Agent: review-agent
Note: File new beads for any gaps found. Assign to implementation-agent or test-writer-agent." \
  --type=task --priority=1 \
  --parent "$EPIC_FOUNDATION" \
  --deps "$T11,$T11_TEST" 2>&1 | extract_id)
echo "T11_REVIEW=$T11_REVIEW"

# Next task in chain — depends on prior REVIEW bead, not just impl
T12=$(bd create \
  --title="<prefix>: X.Y <task title>" \
  --description="..." \
  --type=task --priority=1 \
  --parent "$EPIC_FOUNDATION" \
  --deps "$T11_REVIEW" 2>&1 | extract_id)
echo "T12=$T12"

# Task with multiple predecessors
T25=$(bd create \
  --title="<prefix>: X.Y <task title>" \
  --description="..." \
  --type=task --priority=1 \
  --parent "$EPIC_FOUNDATION" \
  --deps "$T21_REVIEW,$T22_REVIEW" 2>&1 | extract_id)
echo "T25=$T25"

# Append IDs after each epic's batch
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
Any blank ID means the create failed. Do not continue — fix the failed create first.

**Work one epic's issues per bash block.** Keeping blocks to 10-15 commands catches problems early.

---

## Step 5: Wire remaining cross-epic dependencies

After all issues are created, wire deps that couldn't be set at creation time (cross-epic, complex multi-predecessor chains).

**Always verify each dep-add result:**

```bash
source /tmp/beads_ids.env

# Cross-epic: provider epics blocked by foundation
bd dep add $EPIC_API $EPIC_FOUNDATION && echo "OK" || echo "FAILED: API<-FOUNDATION"
bd dep add $EPIC_CACHE $EPIC_FOUNDATION && echo "OK" || echo "FAILED: CACHE<-FOUNDATION"

# Integration epic blocked by all providers
for DEP in $EPIC_API $EPIC_CACHE $EPIC_AUTH; do
  bd dep add $EPIC_INTEGRATION $DEP && echo "OK" || echo "FAILED: INTEGRATION<-$DEP"
done

# Review epic blocked by everything
for DEP in $EPIC_FOUNDATION $EPIC_API $EPIC_CACHE $EPIC_INTEGRATION; do
  bd dep add $EPIC_REVIEW $DEP && echo "OK" || echo "FAILED: REVIEW<-$DEP"
done
```

Do NOT use `| tail -1` — the success message may not be the last line. Do NOT run dep wiring in background tasks or parallel subagents — they share the Dolt lock.

---

## Step 6: Verify final state and mark tasks in progress

```bash
bd stats
bd ready                    # Confirm only the right issues are unblocked
bd blocked | head -20       # Confirm blockers are correct
bd show $EPIC_REVIEW        # Confirm review gate has all expected deps
```

**Expected state:**
- Unblocked: foundation tasks (impl + test beads with no deps), standalone beads
- Blocked: everything with a predecessor
- Review/build gate: fully blocked by all impl + test + review epics

If anything looks wrong, add missing deps with `bd dep add`.

**Mark OpenSpec tasks in progress** (when active):

After beads are created, update `tasks.md` entries covered by these beads from `[ ]` to `[~]` to signal work is underway. This gives visibility that planning has advanced to execution.

---

## Issue content guidelines

Every issue description MUST include:

| Field | Format | Purpose |
|-------|--------|---------|
| What to implement | Brief prose | The actual work |
| `Accept:` | Verbatim from spec; JIRA criteria when active | Definition of done |
| `OpenSpec:` | `change:<change-name>/tasks.md: X.Y` | Cross-ref for sync script |
| `Spec:` | `specs/<name>/spec.md S<section>` | Requirement source |
| `Design:` | `S<decision name>` | If task implements a specific design decision |
| `Agent:` | `implementation-agent` / `test-writer-agent` / `review-agent` | Dispatch routing |
| `Reference:` | `org/repo#path/to/file` (optional) | External code to port/adapt |

**When a single bead covers multiple tasks** (e.g., tasks 3.1-3.4 grouped into one impl bead), list ALL task refs on separate lines. The sync script matches on individual `tasks.md: X.Y` patterns — a single ref only marks that one task:
```
OpenSpec: change:<change-name>/tasks.md: 3.1
OpenSpec: change:<change-name>/tasks.md: 3.2
OpenSpec: change:<change-name>/tasks.md: 3.3
OpenSpec: change:<change-name>/tasks.md: 3.4
```
Omitting refs for 3.2-3.4 means those tasks silently stay `[ ]` after the bead closes.

**When a task spans multiple beads** (task 1.1 requires both bead X and bead Y), each bead references the task with `OpenSpec:`. The sync script marks [x] on the first bead close. If the task isn't fully implemented yet (bead Y still open), the spec-completion-auditor catches it at pre-commit by verifying source code against acceptance criteria. No additional tracking is needed — the auditor is the source of truth.

**When JIRA is active**, also set `--external-ref="jira:PROJ-123"` on every bead, using the JIRA story that the task belongs to. This enables per-story queries (`bd list --external-ref=jira:PROJ-123`) for PR splitting later.

**Agent roles:**
- **`implementation-agent`** — writes production code
- **`test-writer-agent`** — writes tests from spec/acceptance criteria independently of implementation; runs in parallel with impl agent
- **`review-agent`** — reviews completed work, files new beads for gaps, sends action items back

**Per-feature triad:** Every non-trivial task produces three beads: impl + test + review. Impl and test are independent (no dep edge). Review depends on both. Downstream tasks depend on the review bead, not the impl bead directly.

**Title prefix:** When JIRA active: `PROJ-123: X.Y <title>`. When roadmap epic (no JIRA): `E1: X.Y <title>`. Otherwise: `X.Y <title>`.

---

## Review & Build Gate epic (always include)

**This epic runs AFTER all implementation and per-feature reviews are complete.** Per-feature review gates catch issues incrementally; this is the final integration check.

The final epic gates on all other epics. It contains 3-4 issues:

1. **Requirements coverage audit** — verify every acceptance criterion in every spec is met. File new beads for gaps; assign to `implementation-agent`.
2. **Full test suite + coverage** — run the project's test command with coverage. File new beads for failures; assign to `test-writer-agent`.
3. **Code quality audit** — check for: circular imports, unconfigurable hardcoded values, missing error handling at boundaries, deviations from `design.md`. File new beads; assign to `implementation-agent`.
4. **Consolidated build gate** — install deps + run entry point + run tests must all pass. Only closed when all preceding review issues are closed.

Wire the review issues sequentially (audit -> test run -> quality audit -> build gate) as a linear chain within the review epic.

---

## Error recovery

**Server won't start / lock contention:**
```bash
pkill -f dolt 2>/dev/null; sleep 2
rm -f .beads/dolt-server.lock
rm -f .beads/dolt/.dolt/noms/LOCK
rm -f .beads/dolt/.dolt/stats/.dolt/noms/LOCK
bd dolt start && sleep 2 && bd stats
```

**`bd create` returns blank ID:**
The create failed. Run the command again standalone (without `extract_id`) to see the full error:
```bash
bd create --title="..." --description="..." --type=task 2>&1
```
Fix the issue (usually server connectivity), then rerun.

**Dep add failing:**
Run a single `bd dep add <issue> <dep>` and read the full output. Most common causes: server down (run recovery above), or ID is wrong (check `/tmp/beads_ids.env`).

---

## Anti-patterns

| Don't | Why |
|-------|-----|
| `bd dep add ... \| tail -1` | Success line may not be last; failures hidden |
| Background bash tasks for bd commands | Dolt lock contention -> silent failures |
| Parallel subagents for bd create/dep-add | Same lock contention issue |
| Start without `bd dolt start` | Auto-start/stop cycle leaves stale locks |
| Wire all deps after all creates | Use `--deps` at create time for immediate predecessors |
| Create 50 issues then check stats | Check after each epic's batch |
| Assume dep wiring succeeded without checking | Always verify with `bd show <key-issue>` |
| Create task issues without `--parent` | Breaks tree view, `bd epic status`, and `bd children` |
| Use `git worktree add` directly | Always use `bd worktree create` for proper database redirect |
| Omit `Agent:` field in descriptions | `/implement-beads` uses it to route work to the right agent type |

ARGUMENTS: $ARGUMENTS
