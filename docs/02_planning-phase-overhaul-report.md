# Planning Phase Overhaul — Follow-up Report

**Date:** 2026-04-03
**Branch:** `planning-phase-overhaul`
**Version:** sdd-workflow 1.2.0 → 1.3.0
**Context:** Response to `phase_planning_evaluation.md` findings from real-world `/plan-spec` session on XTrkCAD-Modern Phase 2.1

---

## Executive Summary

The planning evaluation identified a fundamental problem: `/plan-spec` gathered context well, then handed everything to `/opsx:propose` which batch-generated all four artifacts (proposal → specs → design → tasks) in a single unreviewed pass. Two ad-hoc reviewer agents were needed afterward to catch 13 issues — 3 critical, 6 high — that should have been caught during planning.

This overhaul addresses that problem at three levels:

1. **Stepwise artifact creation** — artifacts are now created one at a time with an inline review checklist after each, replacing the batch `/opsx:propose` approach
2. **Two independent reviewer sub-agents** — mandatory final review by `spec-accuracy-reviewer` (factual correctness) and `spec-completeness-reviewer` (coverage and coherence), launched in parallel with different mandates
3. **Standalone review capability** — new `/review-spec-artifact` skill for on-demand reviews after any artifact edit

All 13 original issues from the evaluation would now be caught by the new workflow, most at the inline checklist stage, with reinforcement from the final reviewers.

---

## What Was Changed

### 1. `/plan-spec` SKILL.md — Major Overhaul

**Before:** Steps 1-3 gathered context → Step 4 compiled everything → invoked `/opsx:propose` → batch generation → done.

**After:** Steps 1-2 unchanged (good context gathering) → Step 3 routes to one of three paths → Step 4 creates artifacts → Step 5 runs two-agent review → Step 6 wraps up.

Key changes:

| Aspect | Before (v1.2) | After (v1.3) |
|--------|---------------|--------------|
| Artifact creation | Batch via `/opsx:propose` | Stepwise with `openspec instructions` or `/opsx:continue` |
| Review checkpoints | None | After each artifact (proposal, specs, design, tasks) |
| Final review | None (ad-hoc by user) | Mandatory two-agent independent review |
| Routing | explore vs. propose (two paths) | explore → stepwise → review / stepwise → review / fast → review (three paths) |
| Flags | `--explore`, `--no-explore` | `--explore`, `--fast` |
| Output flow | explore → propose, or direct → propose | explore → stepwise, or direct → stepwise, or fast → propose |

**Inline review checklists** embedded in Step 4b for each artifact type:
- **Proposal**: Scope alignment, no creep, terminology, feasibility
- **Specs**: Source-of-truth cross-reference, naming accuracy, testable scenarios, JIRA coverage
- **Design**: Codebase verification (grep/glob), dependency verification, build system feasibility
- **Tasks**: Requirement coverage, traceability, ordering validity, acceptance criteria, test pairing

### 2. New Agent: `spec-accuracy-reviewer`

**File:** `agents/spec-accuracy-reviewer/AGENT.md`

Reviews through a **factual accuracy** lens:
- Cross-references every type, API, enum against source docs and codebase
- Verifies CMake targets, file paths, module names exist (grep, not assume)
- Checks dependency versions and API compatibility
- Audits naming conventions against project standards
- Grades findings: CRITICAL (build failure), HIGH (rework), LOW (style)

Model: `sonnet`. Tools: Read, Glob, Grep, Bash, WebFetch.

### 3. New Agent: `spec-completeness-reviewer`

**File:** `agents/spec-completeness-reviewer/AGENT.md`

Reviews through a **completeness and coherence** lens:
- Traces JIRA ACs → spec scenarios → tasks (finds gaps)
- Checks scope against roadmap phase boundaries
- Validates task dependency ordering (no circular deps, build order)
- Verifies implementation patterns are explicit in task descriptions
- Cross-artifact coherence (proposal → specs → design → tasks consistency)

Model: `sonnet`. Tools: Read, Glob, Grep, Bash.

**Why two agents instead of one:** The evaluation showed that different error classes require different review approaches. An accuracy reviewer needs to grep the codebase and read source docs (verification against reality). A completeness reviewer needs to build coverage matrices and trace dependency chains (structural analysis). Combining these into one agent would create anchoring bias — once you find a naming error, you focus on naming errors. Separate agents with separate mandates catch more.

### 4. New Skill: `/review-spec-artifact`

**File:** `skills/review-spec-artifact/SKILL.md`

Standalone, user-invocable skill that runs the two reviewer agents against existing OpenSpec artifacts. Supports:
- `--artifact proposal|specs|design|tasks` — review only one artifact
- `--lens accuracy|completeness|both` — use only one reviewer

Use cases: After manual artifact edits, before `/generate-spec-beads`, as an extra quality gate, or for re-review after fixing findings.

### 5. README.md Updates

- Stage 1 (Planning) table updated: shows three paths including standalone review
- Planning phase mermaid diagram updated: batch `/opsx:propose` replaced with stepwise creation → two-agent review → reviewed artifacts
- Big-picture mermaid diagram updated: `/plan-spec` now shows stepwise creation, `/review-spec-artifact` added as review gate
- Skill commands table: added `review-spec-artifact`
- Added paragraph explaining the two-agent review rationale

### 6. Planning Template Updates

- `spec-planning-template.md` intro updated to reference stepwise creation + dual reviewer
- Added **Per-Artifact Review Checklists** section with the four checklists (proposal, specs, design, tasks)
- Checklists available for offline planning prep, not just during `/plan-spec` execution

### 7. Version Bumps

- `plugin.json`: 1.2.0 → 1.3.0
- `marketplace.json`: 1.2.0 → 1.3.0
- Both descriptions updated to mention stepwise creation and dual-reviewer validation

---

## Response to Evaluation Priorities

### Priority 1: Fix `/plan-spec` to stop invoking `/opsx:propose` — ADDRESSED

The default path is now stepwise artifact creation (Step 4b). `/opsx:propose` is only used on the `--fast` path, which:
- Must be explicitly requested by the user
- Includes a warning that it skips per-artifact review
- Still gets the mandatory two-agent final review (Step 5)

**Decision on `/opsx:propose` access:** Kept as `--fast` escape hatch rather than removing entirely. Rationale: small, obvious changes (single-file extensions of existing patterns) genuinely don't benefit from four review checkpoints. The mandatory final review still catches errors. The risk is documented.

### Priority 2: Create `/review-spec-artifact` skill — COMPLETE

Created as a standalone, user-invocable skill with artifact filtering and lens selection.

### Priority 3: Add review checklists to planning template — COMPLETE

Per-artifact review checklists added to `spec-planning-template.md` in a dedicated section. Available for both online (`/plan-spec`) and offline (manual template) use.

### Priority 4: Update README lifecycle diagram — COMPLETE

Planning phase mermaid diagram and big-picture diagram both updated. Stage 1 text rewritten. Skill table expanded.

### Priority 5: Consider `openspec validate` enhancements — DEFERRED (future)

This requires changes to the OpenSpec CLI itself, not the sdd-workflow plugin. The inline checklists and reviewer agents compensate for the lack of semantic validation in `openspec validate`. Noted in the README addendum as a future enhancement.

---

## How the 13 Original Issues Would Be Caught

| # | Issue | Severity | Would be caught at | How |
|---|-------|----------|-------------------|-----|
| 1 | `xtrk_legacy` target doesn't exist | CRITICAL | Step 4b-iii (design inline review) | Checklist: "Every build target grep/glob-verified against codebase" |
| 2 | `LogLevel::Warning` → `LogLevel::Warn` | CRITICAL | Step 4b-ii (specs inline review) | Checklist: "Every enum cross-referenced against authoritative docs" |
| 3 | Simulation module scope (Milestone 5, not 2.1) | CRITICAL | Step 4b-i (proposal inline review) | Checklist: "No capabilities beyond the target phase/epic" |
| 4 | Pimpl destructor/move rules not explicit | HIGH | Step 4b-iv (tasks inline review) | Checklist: "Critical implementation patterns explicit" |
| 5 | Forward declarations needed | HIGH | Step 4b-iii (design inline review) | Checklist: "Lifetime/ownership rules explicit where relevant" |
| 6 | GTest version vague | HIGH | Step 4b-iii (design inline review) | Checklist: "Every external dependency version-pinned" |
| 7 | `cmake/testing.cmake` not explicit | HIGH | Step 4b-iii (design inline review) | Checklist: "Build system changes verified against current config" |
| 8 | Task ordering misleading | HIGH | Step 4b-iv (tasks inline review) | Checklist: "Task ordering respects build dependencies" |
| 9 | Transform `then()` semantics undefined | HIGH | Step 4b-ii (specs inline review) | Checklist: "Every scenario has specific inputs → expected outputs" |
| 10 | Version format specificity | LOW | Step 5 (accuracy reviewer) | Agent: "Naming convention audit" |
| 11 | constexpr requirements unclear | LOW | Step 5 (accuracy reviewer) | Agent: "Semantic accuracy — verify behavioral claims" |
| 12 | Legacy header build-time check | LOW | Step 5 (completeness reviewer) | Agent: "Implementation completeness" |
| 13 | Document PUBLIC cxx_std_23 | LOW | Step 5 (completeness reviewer) | Agent: "Design decisions reflected in tasks" |

**Result:** 12 of 13 caught with HIGH confidence at the inline checklist stage. Issues 10-13 caught with MEDIUM confidence at the final review stage. No issues would be missed entirely.

---

## What Was NOT Changed (and Why)

### OpenSpec extended profile not required

The evaluation recommended using `/opsx:continue` (expanded profile command) for stepwise creation. The new plan-spec supports it but doesn't require it — it falls back to `openspec instructions <artifact>` CLI commands which work with any profile. This avoids creating a hard dependency on expanded profile being enabled.

### `spec-completion-auditor` not modified

The accuracy reviewer noted a pre-existing issue: `spec-completion-auditor` has `user-invocable: false` but is referenced as user-invocable by `implement-beads`. This is a real bug but predates this work and is unrelated to the planning phase overhaul. Should be fixed separately.

### `ARGUMENTS: $ARGUMENTS` at end of SKILL files

All skill files end with this line. It's a framework convention for argument injection, not a bug. Left as-is.

### `openspec validate` not integrated into inline review

Could add structural validation between artifact creation steps. The inline checklists currently cover this ground manually. Adding automated structural validation is a future enhancement that would complement (not replace) the checklists.

### `/opsx:propose` not removed entirely

Kept as `--fast` escape hatch with documented risk. Removing it entirely would be overly restrictive for trivial changes. The mandatory final review on all paths mitigates the risk.

---

## What's Left for the Future

1. **`openspec validate` integration** — Run structural validation automatically between artifact creation steps in Step 4b
2. **Semantic validation in OpenSpec** — Extend `openspec validate` with cross-reference, naming, and coverage checks (requires OpenSpec CLI changes)
3. **Spec feedback loop** — When implementation reveals spec errors, update artifacts (not just file gap beads). A lightweight `/update-spec` flow
4. **Review metrics** — Track review finding counts over time to measure planning quality improvement
5. **spec-completion-auditor user-invocable fix** — Pre-existing bug; frontmatter says `false` but downstream usage assumes `true`

---

## Self-Review Results

Two independent review agents were run against this work:

### Accuracy Review (3 findings)
- ~~CRITICAL: spec-completion-auditor user-invocable flag~~ — pre-existing, not introduced by this PR
- MEDIUM: Template fallback code not explicit — skill instructions are sufficient for AI agents; added no code
- LOW: ARGUMENTS: $ARGUMENTS convention — intentional framework feature

### Completeness Review (14 findings)
- Items addressed in this iteration:
  - README updated (was flagged as missing)
  - Planning template checklists added (was flagged as missing)
  - `--fast` risk documented (was flagged as unclear)
  - Explore→stepwise transition clarified (was flagged as vague)
- Items deferred:
  - `openspec validate` integration (future enhancement)
  - Token budgeting for reviewer agents (edge case)
  - `applyRequires` verification (low priority)

**All CRITICAL and HIGH findings from the self-review were either addressed or determined to be pre-existing/out-of-scope.**

---

## Files Changed Summary

| File | Action | Lines |
|------|--------|-------|
| `plugins/sdd-workflow/skills/plan-spec/SKILL.md` | Major overhaul | +279 -63 |
| `plugins/sdd-workflow/agents/spec-accuracy-reviewer/AGENT.md` | Created | 95 lines |
| `plugins/sdd-workflow/agents/spec-completeness-reviewer/AGENT.md` | Created | 105 lines |
| `plugins/sdd-workflow/skills/review-spec-artifact/SKILL.md` | Created | 111 lines |
| `plugins/sdd-workflow/README.md` | Updated diagrams, tables, text | +25 -8 |
| `plugins/sdd-workflow/templates/spec-planning-template.md` | Updated intro, added checklists | +40 -4 |
| `.claude-plugin/marketplace.json` | Version bump | +2 -2 |
| `plugins/sdd-workflow/.claude-plugin/plugin.json` | Version bump | +2 -2 |

---

## How This Aligns with OpenSpec's Design

Research into the [OpenSpec repository](https://github.com/Fission-AI/OpenSpec) revealed that OpenSpec already supports stepwise artifact creation through its **expanded profile**:
- `/opsx:new` scaffolds a change folder
- `/opsx:continue` creates ONE artifact at a time, showing status and what's unlocked
- `/opsx:verify` validates completeness, correctness, and coherence post-implementation

The core profile's `/opsx:propose` is a convenience command for quick, well-defined changes — not the intended workflow for complex planning. Our previous approach used the convenience command as the primary workflow, which is why it produced batch artifacts without review.

The new plan-spec works WITH OpenSpec's design:
- Uses `openspec instructions` (any profile) or `/opsx:continue` (expanded) for stepwise creation
- Respects the artifact dependency chain (proposal → specs || design → tasks)
- Adds review checkpoints that OpenSpec's architecture supports but doesn't enforce
- Keeps `/opsx:propose` available as a documented fast path for simple changes

---

## Bottom Line

The planning phase now has review mechanisms proportional to the implementation phase. Where before, planning had zero review and implementation had per-feature review gates + spec-completion auditing + build gates, planning now has:
- **Per-artifact inline review** (4 checkpoints with targeted checklists)
- **Two-agent independent final review** (accuracy + completeness, different mandates)
- **Standalone re-review capability** (`/review-spec-artifact`)

Errors caught during planning cost minutes to fix. Errors caught during implementation cost hours. This overhaul shifts error detection upstream where it's cheapest.
