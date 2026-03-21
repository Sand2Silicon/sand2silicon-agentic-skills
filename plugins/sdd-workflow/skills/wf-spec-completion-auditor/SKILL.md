---
name: wf-spec-completion-auditor
description: Audit for drift between closed Beads issues and open OpenSpec tasks. Use when Beads have been closed but OpenSpec tasks may still show as incomplete, or when you want to verify that work described in spec tasks was actually implemented before archiving. Runs a verification agent that cross-checks state and produces an actionable report.
---

# Spec Completion Auditor

Detects drift between Beads completion state and OpenSpec `tasks.md` state, then verifies whether work was genuinely done.

**Input**: Optionally specify an OpenSpec change name (e.g. `fix-core-inference-pipeline`). If omitted, audits all active changes.

## Steps

### 1. Identify changes to audit

If a change name was provided, use it. Otherwise:
```bash
ls openspec/changes/
```
Audit all changes that have a `tasks.md`.

### 2. For each change: collect state

Run both sides of the comparison in parallel:

**Beads side** — all issues with a task cross-reference:
```bash
bd list --status=closed --json   # closed (should map to [x])
bd list --status=open --json     # open (should map to [ ])
bd list --status=in_progress --json  # in_progress (should also map to [ ])
```
Parse the `change:<name>/tasks.md: X.Y` field from each issue description (or legacy `tasks.md: X.Y` for older issues). Match refs to the correct change by name.

**Scoping rule:** Unscoped legacy refs (`tasks.md: X.Y`) are only matched to a change when it is the sole active (non-archived) change. When multiple changes are active, unscoped refs are ignored to prevent cross-change contamination.

**OpenSpec side** — task checkbox states from `tasks.md`:
```bash
cat openspec/changes/<name>/tasks.md
```
Parse `- [x]` (complete) and `- [ ]` (open) entries with their section numbers.

### 3. Identify mismatches

Four mismatch types to detect:

| Type | Beads state | tasks.md state | Meaning |
|------|------------|----------------|---------|
| **A** | closed | `[ ]` open | Bead closed but spec task not marked done |
| **B** | open/missing | `[x]` complete | Spec task marked done but no closed bead |
| **C** | closed | *(no task ref)* | Bead closed with no spec cross-reference |
| **D** | *(no bead)* | `[ ]` open | Spec task has no corresponding bead at all |

### 4. Verify Type A mismatches (closed bead, open task)

For each Type A mismatch, read the relevant source code to verify if the work was genuinely done:

- Read the bead's full description: `bd show <id>`
- Identify the file(s) and function(s) the task requires
- Read those sections of the source file
- Determine: was this actually implemented?

**If implemented**: Mark the task complete in tasks.md (`[ ]` → `[x]`) and note it as auto-synced. Do NOT reopen or close any Beads issue — only tasks.md is updated.

**If NOT implemented**:
- Do NOT mark it complete in tasks.md
- Do NOT reopen the closed bead
- Report this as a gap in the audit output — the user decides what to do
- Optionally suggest a new Beads issue to fill the gap (user must create it)

### 5. Handle Type D mismatches (spec task, no bead)

For each untracked spec task with no corresponding bead:
- Read the task description in tasks.md
- Check the source code to see if it might already be implemented
- If implemented: mark `[x]` in tasks.md, note as auto-synced
- If not implemented: include in the report as an untracked gap — do NOT create beads or modify Beads state; the user decides whether to create issues

### 6. Run sync script

After verification, run the sync to apply any task state updates:
```bash
python3 scripts/sync-openspec-tasks.py
```

**Note:** The sync script may auto-archive a change if all tasks are `[x]` with full Beads coverage. Steps 4-5 apply direct edits; this step serves as a final consistency check.

### 7. Produce audit report

Output a structured report:

```
## Spec Completion Audit: <change-name>

### Summary
- Beads closed: N
- OpenSpec tasks complete: M / T total
- Mismatches found: X
- Auto-synced (tasks.md updated): Y

### Mismatch Details

#### Auto-synced (work verified in source, tasks.md updated)
- [x] X.Y — <task title> (verified in <file>:<line>)

#### Implemented but task still open — needs your action
- [ ] X.Y — <task title> → work is present in code but task was not auto-synced

#### Gaps: closed bead but work NOT found in source
- ⚠ X.Y — <task title> (bead <id> was closed but implementation not detected)

#### Type B: spec marked [x] but no closed bead
- [x] X.Y — <task title> — no corresponding bead found

#### Type D: spec task open, no bead exists at all
- [ ] X.Y — <task title> — no bead found, implementation: <found | not found>

### Archive Readiness
✓ Ready to archive — all tasks complete and verified
⚠ Not ready — N open tasks remain
```

### 8. Suggest next action

- If all tasks complete and verified: "All tasks verified. Archive with `/openspec-archive-change <name>`"
- If gaps exist: list them clearly — user decides whether to create new Beads issues or investigate further
- If nothing to do: "No drift detected. Beads and spec are in sync."

## Guardrails

- **Never modify Beads state** — no `bd close`, no `bd create`, no `bd update` during this audit
- **Only tasks.md may be updated** — and only when source code confirms the work is done
- **Never mark tasks.md complete** without first verifying the code implements the requirement
- **Verify in the actual source** — don't assume a closed bead means the work is correct
- If source code is ambiguous, report it as uncertain rather than guessing
- Type C mismatches (closed bead, no spec ref) are informational only — no action needed
