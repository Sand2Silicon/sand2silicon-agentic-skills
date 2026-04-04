# Task-Bead Mapping & PR Strategy Analysis

**Date**: 2026-04-03
**Context**: SDD-workflow produces great implementation results but the commit/PR output doesn't map back to JIRA tickets for review. Task-to-bead cardinality is assumed 1:1 but isn't always, and deviations break sync tracking.

---

## Part 1: Task-to-Bead Cardinality Problem

### The three cases

| Case | Example | Current handling | Failure mode |
|------|---------|-----------------|--------------|
| **A: task == bead** (1:1) | Task 1.1 → bead `impl-1.1` | Works perfectly. Sync script marks task [x] on bead close. | None |
| **B: task spans multiple beads** (1:N) | Task 1.1 involves both a config change (bead X) and an API change (bead Y) | Each bead carries `OpenSpec: change:foo/tasks.md: 1.1`. First close marks it [x] — but bead Y is still open, so task 1.1 appears done before the work is finished. | Premature [x]. Auditor doesn't catch it because the bead *is* closed and the task *is* [x]. |
| **C: multiple tasks in single bead** (N:1) | Tasks 3.1–3.4 are closely related file changes, grouped into one bead | Only works if all task refs are listed. Phase 3 gap report showed this fails silently — tasks 3.2–3.4 stay [ ] forever. | Silent sync miss. Fixed in this session by requiring all refs. |

### Why case B is the hard one

Case C was solved by requiring explicit refs for every covered task (applied this session). Case A is the happy path. Case B is structurally harder because:

1. **The sync script marks [x] on first bead close** — it has no concept of "task 1.1 requires beads X AND Y to both be closed."
2. **Adding that concept** (multi-bead completion conditions on a task) would require the sync script to maintain state about which beads map to which tasks *and* only mark [x] when all contributing beads close. That's a significant complexity increase.
3. **The orchestrator doesn't always know at planning time** which tasks will span multiple beads — it emerges during implementation when overlapping file changes force a split.

### Proposed approach: accept imprecision, catch at audit

The pragmatic answer is: **don't try to track N:1 bead-to-task at the sync level. Instead, treat it as an audit concern.**

**Convention (already implicit, make explicit):**
- Each bead references **its primary task** — the one it most directly implements.
- If a bead contributes partially to another task, add a `Contributes: change:foo/tasks.md: 1.1` line (informational, not parsed by sync).
- The sync script marks [x] on first contributing bead close (same as today).
- The **spec-completion-auditor** is where multi-bead tasks get caught: it reads the source code to verify the task is actually done, regardless of bead status. If task 1.1's code isn't complete because bead Y is still open, the auditor reports it as a gap.

This means:
- Sync stays simple (pattern match → mark [x]).
- Auditor catches false positives (task marked [x] but code incomplete).
- No new data model or state tracking needed.

The key insight: **the sync script is a convenience heuristic; the auditor is the source of truth**. As long as the auditor is mandatory (fixed this session), premature [x] marks are caught and corrected.

---

## Part 2: The PR Granularity Problem

### What happened

Two JIRA epics → 6 stories → ~30 beads → implemented in waves → merged into a single branch → one PR with 42 files changed. Reviewer: "can we break this down?"

The reviewer's complaint isn't about code quality — it's about **reviewability**. A 42-file PR is hard to reason about even if every change is correct. They want PRs scoped to individual JIRA stories so each one can be reviewed, approved, and merged independently.

### Why the current workflow produces monolithic PRs

The workflow optimizes for **execution efficiency** (parallel waves, shared worktree, dependency-graph-driven scheduling). This is correct for implementation but produces output shaped like the *execution graph*, not like the *JIRA ticket structure*:

```
Execution view:  Wave 1 (beads 1-8) → Wave 2 (beads 9-16) → Wave 3 (beads 17-24) → Gate
JIRA view:       STORY-1 (beads 3,7,9,15)  |  STORY-2 (beads 1,4,10,16)  |  ...
```

These two views are orthogonal. The workflow currently only materializes the execution view in git.

### What the tooling supports

**Beads capabilities (relevant):**
- `metadata` field: arbitrary JSON, queryable via `--metadata-field`
- `external_ref` field: designed for external ticket IDs (e.g., `jira:PROJ-123`)
- `labels`: array, queryable via `--label`
- `bd list --metadata-field jira.story=PROJ-123 --status=closed --json`: would return all closed beads for a specific JIRA story

**Git capabilities (relevant):**
- Commits are already per-bead (one `bd close` → one commit).
- Commit messages already carry the bead ID and JIRA prefix.
- `git log --grep="PROJ-123"` can extract commits for a specific story.
- `git cherry-pick` can move commits to per-story branches.

**This means the data is already there** — beads have JIRA ticket numbers in titles, commits carry bead IDs, and both are queryable. What's missing is **a step that uses this data to produce per-story branches/PRs**.

### Strategy: Ticket-scoped commit convention + post-implementation PR splitting

Rather than restructuring how the orchestrator works (which would sacrifice parallelism), add a **post-implementation PR preparation step** that reorganizes commits into per-ticket branches.

**Phase 1: Enrich bead metadata at creation time (in `/generate-spec-beads`)**

When JIRA is active, set `external_ref` and `metadata.jira.story` on every bead:
```bash
bd create --title="PROJ-123: 1.1 Add cache layer" \
  --external-ref="jira:PROJ-123" \
  --metadata='{"jira": {"story": "PROJ-123", "epic": "PROJ-100"}}' \
  ...
```

This is low-cost: the data already exists in the title prefix; we're just making it machine-queryable.

**Phase 2: Structured commit messages (in `/implement-beads`)**

When an agent closes a bead via `bd close`, the commit message should follow:
```
PROJ-123: 1.1 Add cache layer

Bead: workspace-5ka
OpenSpec: change:add-auth-middleware/tasks.md: 1.1
```

The JIRA story ID in the first line makes `git log --grep` work perfectly for grouping.

**Phase 3: Post-implementation PR split (new capability)**

After the build gate passes and pre-commit verification succeeds, but *before* pushing, offer:

> **PR submission options:**
> 1. **Single PR** — one PR for the entire change (fast, simple)
> 2. **Per-ticket PRs** — split into stacked PRs, one per JIRA story (reviewable, traceable)
>
> Choose: single / per-ticket

If per-ticket:
```bash
# 1. Identify unique JIRA stories from closed beads
STORIES=$(bd list --status=closed --parent $EPIC_ID --json | \
  jq -r '.[].external_ref' | sort -u)

# 2. For each story, cherry-pick its commits to a dedicated branch
for STORY in $STORIES; do
  git checkout -b "pr/$STORY" main
  # Find commits by grepping for the JIRA prefix
  git log impl/<change-name> --grep="$STORY" --format="%H" --reverse | \
    xargs git cherry-pick
  # Create PR via gh CLI
  gh pr create --base main --head "pr/$STORY" \
    --title "$STORY: <story title>" \
    --body "Part of <change-name>. Implements $STORY."
done
```

**Dependency ordering**: If STORY-2 depends on STORY-1's changes, the second branch bases off the first:
```bash
git checkout -b "pr/PROJ-124" "pr/PROJ-123"  # stacked
```

### Why this works without restructuring the workflow

1. **Implementation stays parallel** — the orchestrator still dispatches waves optimally.
2. **No new data model** — uses existing `external_ref` and commit message conventions.
3. **Splitting happens once, after everything passes** — no risk of partial/broken PRs.
4. **Beads queries do the heavy lifting** — `bd list --metadata-field jira.story=X` gives the exact bead set per story.
5. **Cherry-pick is reliable here** because commits are already atomic per-bead, and beads are scoped to specific files.

### Edge cases

| Edge case | Handling |
|-----------|----------|
| Bead touches files for multiple stories | Commit goes into the *primary* story's branch. The other story's PR will include it as a dependency (stacked base). |
| Shared infrastructure change (no single ticket) | Create a "foundation" PR that all ticket PRs stack on. Common in practice. |
| Merge conflicts during cherry-pick | Likely minimal because beads are file-scoped. If it happens, the orchestrator reports and asks the user to resolve. |
| Spec/doc files (openspec/) | Exclude from per-ticket PRs — they belong in a single "planning artifacts" commit or are omitted from PRs entirely (they're development artifacts, not shippable code). |

---

## Part 3: Spec/Doc File Noise in PRs

The "42 files changed" problem is partly about ticket scoping (Part 2) and partly about **spec/doc files inflating the diff**.

OpenSpec artifacts (`openspec/changes/*/`), planning templates, and beads database files are development process artifacts. They should not appear in implementation PRs because:
- They don't affect the running system.
- Reviewers don't need to approve them.
- They inflate the diff count, making the PR look bigger than it is.

### Approach: separate spec artifacts from implementation commits

**Option A: .gitattributes exclusion (simplest)**
```gitattributes
openspec/** linguist-generated=true
.beads/** linguist-generated=true
```
GitHub collapses files marked `linguist-generated` in PR diffs. They're still committed but hidden by default. This doesn't reduce the file count but makes the PR's "meaningful changes" obvious.

**Option B: Separate commits for spec vs. implementation**
The orchestrator already commits per-bead. Add a convention:
- Implementation commits: `PROJ-123: 1.1 Add cache layer`
- Spec sync commits: `docs: sync tasks.md for add-auth-middleware` (auto-generated by sync script)

Then per-ticket PR branches cherry-pick only implementation commits, and spec changes go in a separate "housekeeping" PR.

**Option C: Don't commit spec files in implementation branches**
OpenSpec artifacts live in the main branch. The worktree only commits source code and tests. Spec sync happens post-merge. This is the cleanest separation but requires the sync script to work post-merge.

**Recommendation: Option A + B.** Mark spec directories as linguist-generated so GitHub collapses them, and separate spec-sync commits so they can be excluded from per-ticket PRs when splitting.

---

## Part 4: Recommended Changes

### Changes to apply now (incremental, non-breaking)

| # | Where | What | Effort |
|---|-------|------|--------|
| 1 | `generate-spec-beads/SKILL.md` | Add `--external-ref` and `metadata.jira` to bead creation when JIRA active | Small |
| 2 | `implement-beads/SKILL.md` | Structured commit messages with JIRA story ID on first line | Small |
| 3 | `implement-beads/SKILL.md` | Add Step 7.5: PR submission options (single vs per-ticket) | Medium |
| 4 | `generate-spec-beads/SKILL.md` | Document the "primary task" convention for N:1 bead-task mapping | Small |
| 5 | README.md | Add section on PR strategy | Small |

### Changes to consider later (require more design)

| # | What | Why wait |
|---|------|----------|
| 6 | Automated `pr-split` skill/script | Needs testing with real multi-ticket implementation; the manual `gh`/`git` commands work first |
| 7 | `.gitattributes` template in `sdd-workflow-init` | Needs per-project customization; add to the init skill's detection |
| 8 | Stacked PR tooling (`ghstack` or `graphite`) | External dependency; evaluate whether org uses stacked-PR workflow |

---

## Part 5: Task-Bead Relationship Summary

The core insight is that perfect task-bead tracking at the sync level isn't worth the complexity. Instead:

```
                    Convenience heuristic              Source of truth
                    (fast, imprecise)                  (slow, correct)
                          │                                  │
   bd close ──→ sync-openspec-tasks.py ──→ tasks.md     auditor ──→ source code
                marks [x] on ref match                  verifies actual completion
                                                        catches premature [x]
```

- **sync script**: marks tasks [x] when beads close. May be premature (case B) or incomplete (case C, now fixed). Fast, runs after every wave.
- **auditor**: reads the actual source code to verify each [x] task is genuinely implemented. Catches false positives. Mandatory at pre-commit.

This two-tier model handles all three cardinality cases without adding data model complexity:

| Case | Sync does | Auditor does |
|------|-----------|--------------|
| A (1:1) | Marks [x] correctly | Confirms |
| B (1:N, task spans beads) | Marks [x] on first close (may be premature) | Catches if code isn't complete yet |
| C (N:1, multi-task bead) | Marks all referenced tasks [x] (now that refs are required) | Confirms all tasks are implemented |
