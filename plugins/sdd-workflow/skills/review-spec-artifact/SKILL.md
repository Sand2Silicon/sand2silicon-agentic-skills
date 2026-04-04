---
name: review-spec-artifact
description: Standalone review of OpenSpec planning artifacts using two independent reviewer sub-agents (accuracy + completeness). Use after editing artifacts, after /plan-spec completes, or anytime you want a quality check on planning artifacts. Invokes spec-accuracy-reviewer and spec-completeness-reviewer agents.
user-invocable: true
---

# Review Spec Artifact

Run two independent reviewer sub-agents against OpenSpec planning artifacts to catch errors before implementation begins.

**Input**: `/review-spec-artifact <change-name> [--artifact proposal|specs|design|tasks] [--lens accuracy|completeness|both]`

- `<change-name>`: OpenSpec change name (required)
- `--artifact`: Review only a specific artifact (optional — default reviews all)
- `--lens`: Use only one reviewer (optional — default uses both)

**Prerequisites:** Artifacts must exist at `openspec/changes/<change-name>/`.

---

## Step 1: Load artifacts and context

```bash
# Verify change exists
ls openspec/changes/<change-name>/ 2>/dev/null || { echo "No artifacts found"; exit 1; }

# Load artifacts
cat openspec/changes/<change-name>/proposal.md 2>/dev/null
cat openspec/changes/<change-name>/design.md 2>/dev/null
cat openspec/changes/<change-name>/tasks.md 2>/dev/null
ls openspec/changes/<change-name>/specs/ 2>/dev/null
```

Also load context sources:
- `CLAUDE.md` — project conventions, terminology
- Roadmap docs — scope boundaries
- Authoritative spec documents referenced in the artifacts
- JIRA tickets (via MCP if available) referenced in the artifacts

---

## Step 2: Launch reviewers

Launch both reviewers as independent sub-agents. They must not see each other's output.

### Accuracy reviewer (spec-accuracy-reviewer agent)

```
Review openspec/changes/<change-name>/ for factual accuracy.
<If --artifact specified: Focus on <artifact> only.>

Verify every type, API, path, target, and dependency against the actual codebase
and authoritative source documents. Report findings with severity, evidence, and fix.
```

### Completeness reviewer (spec-completeness-reviewer agent)

```
Review openspec/changes/<change-name>/ for completeness and coherence.
<If --artifact specified: Focus on <artifact> only.>
<JIRA tickets: list if active>
<Roadmap epic: ref if active>

Verify requirements coverage, scope alignment, task ordering, and cross-artifact
consistency. Report findings with severity, evidence, and fix.
```

If `--lens` restricts to one reviewer, launch only that one.

---

## Step 3: Present findings

Merge both reviewers' findings, sorted by severity:

```
## Planning Review: <change-name>

### Critical Findings (must fix)
| # | Source | Artifact | Finding | Suggested Fix |
|---|--------|----------|---------|---------------|

### High-Priority Findings (should fix)
| # | Source | Artifact | Finding | Suggested Fix |
|---|--------|----------|---------|---------------|

### Low-Priority Findings (optional)
| # | Source | Artifact | Finding | Suggested Fix |
|---|--------|----------|---------|---------------|

### Summary
- Critical: N | High: N | Low: N
- Accuracy reviewer: N findings
- Completeness reviewer: N findings
```

**If CRITICAL findings exist:** Recommend fixing before proceeding to `/generate-spec-beads`.

**If no findings:** Report clean review — artifacts are ready for downstream work.

---

## When to use

- **After `/plan-spec` completes** — as an additional review pass (plan-spec already runs this internally, but you can re-run after manual edits)
- **After manually editing artifacts** — to verify changes didn't introduce errors
- **Before `/generate-spec-beads`** — as a quality gate
- **After fixing review findings** — to verify fixes are correct
- **Anytime** — lightweight, non-destructive, read-only review

ARGUMENTS: $ARGUMENTS
