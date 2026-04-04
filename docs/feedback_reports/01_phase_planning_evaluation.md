# SDD-Workflow Planning Phase Evaluation

**Date:** 2026-04-03
**Context:** Real-world session using `/plan-spec` + `/opsx:propose` on XTrkCAD-Modern Phase 2.1 (core types, error handling, public header skeleton for a C++ library)
**Evaluator:** Claude Opus 4.6, prompted by project maintainer

---

## Executive Summary

The `/plan-spec` skill bypasses OpenSpec's built-in iterative artifact creation, producing all four artifacts (proposal → specs → design → tasks) in a single unreviewed pass. Two ad-hoc reviewer agents were needed afterward to catch 13 issues — 3 critical, 6 high-priority — that should have been caught during planning. The root cause is that `/plan-spec` treats `/opsx:propose` as a "generate everything" endpoint rather than leveraging OpenSpec's artifact dependency chain as natural review checkpoints.

**Key recommendation:** Replace the monolithic `/opsx:propose` invocation with a stepped artifact workflow that creates each artifact individually, with review/validation between each step.

---

## 1. What Happened in This Session

### Timeline

| Step | What happened | Time cost |
|------|--------------|-----------|
| 1 | `/plan-spec` gathered context (roadmap, 07a spec, existing scaffold, beads) | Efficient |
| 2 | `/plan-spec` asked 5 scoping questions | Good — caught header path conflict, static/shared ambiguity |
| 3 | User answered questions, decisions made | Good interaction |
| 4 | `/plan-spec` compiled context and invoked `/opsx:propose` | **Problem starts here** |
| 5 | `/opsx:propose` created all 4 artifacts in one pass, no review between them | **All artifacts written without pause** |
| 6 | User asked for 2 reviewer sub-agents | **Ad-hoc quality gate** |
| 7 | Reviewers found 13 issues (3 critical, 6 high, 4 low) | Expensive — full re-read of all artifacts + authoritative docs |
| 8 | Applied fixes to 6 files | Rework |

### What the Reviewers Caught

**Critical issues (would have caused build failures or spec violations):**
1. `xtrk_legacy` target doesn't exist — actual CMake target is `xtrkcad-lib`
2. `LogLevel::Warning` should be `LogLevel::Warn` (per 04_core-api-specification.md)
3. Simulation module scope question (07a says Milestone 5, not 2.1)

**High-priority issues (would have caused implementation problems):**
4. Pimpl destructor/move rules not explicit in tasks
5. Forward declarations needed for cross-module header references
6. GTest version pinning vague
7. `cmake/testing.cmake` creation not explicit
8. Task ordering misleading (can't build until all groups done)
9. Transform `then()` composition semantics undefined

**None of these required information that wasn't available during planning.** Every issue could have been caught by comparing spec artifacts against the authoritative source docs — which is exactly what the reviewers did.

---

## 2. Root Cause Analysis

### 2.1 `/plan-spec` duplicates OpenSpec's phased artifact creation

OpenSpec's `spec-driven` schema defines a **dependency chain**:

```
proposal (requires: [])
    ↓
specs (requires: [proposal])
design (requires: [proposal])
    ↓
tasks (requires: [specs, design])
```

Each artifact has its own `openspec instructions <artifact>` command that returns:
- `template` — the structure to fill
- `instruction` — what to write
- `dependencies` — completed artifacts to read for context
- `unlocks` — what becomes available after this artifact

This chain is **designed for iterative creation with review between steps.** The `status` command shows what's `ready`, `blocked`, or `done`. The workflow should be:

1. Create proposal → **review proposal** → confirm
2. Create specs → **review specs against proposal and source docs** → confirm
3. Create design → **review design against specs** → confirm
4. Create tasks → **review tasks against design and specs** → confirm

**What `/plan-spec` does instead:** It compiles a planning context during the interactive conversation, then fires `/opsx:propose` which creates all 4 artifacts sequentially in one pass with no review checkpoints. The dependency chain becomes a formality — artifacts are created in order but never reviewed individually.

### 2.2 `/opsx:propose` is a "batch generate" skill, not an iterative workflow

Looking at the `/opsx:propose` prompt (loaded into this session), its Step 4 says:

> Loop through artifacts in dependency order... Continue until all `applyRequires` artifacts are complete

It's designed to generate all artifacts needed for `apply` in one invocation. There is no "pause and review" step. There is no validation step. The skill creates the artifact, checks status, and moves to the next one.

### 2.3 The interactive planning conversation is good but insufficient

`/plan-spec` Step 3 (Interactive Planning Conversation) is well-designed:
- 3a: Establish scope
- 3b: Research phase
- 3c: Design alignment

This is where the 5 scoping questions came from, and it worked well — it caught the header path conflict and the static/shared ambiguity before any artifacts were generated.

**But the conversation operates at a high level.** It doesn't cross-reference every type name against the authoritative spec doc. It doesn't verify CMake target names against the actual build system. It doesn't check enum values against source-of-truth documents. Those are **artifact-level concerns** that should be caught during artifact review, not during the planning conversation.

### 2.4 What OpenSpec already provides but we didn't use

| OpenSpec capability | Available? | Used? | Why not? |
|--------------------|-----------|-------|----------|
| `openspec instructions <artifact>` — per-artifact guidance | Yes | Yes, but all at once | `/opsx:propose` loops through them |
| `openspec status` — see what's ready/blocked/done | Yes | Only at start and end | Not used between artifacts |
| `openspec validate` — structural validation | Yes | Not during creation | Only structural, not semantic |
| Per-artifact review checkpoint | **Not built in** | N/A | **This is the gap** |
| Cross-reference validation against source docs | **Not built in** | N/A | **This is the gap** |

---

## 3. What Would Have Caught These Issues Without Ad-Hoc Reviewers?

### 3.1 A proposal review step

After creating `proposal.md`, a review step should verify:
- Capabilities listed match what's actually in the roadmap phase
- No scope creep (simulation module question would surface here)
- Terminology matches the project's conventions

**Would have caught:** Issue #3 (simulation scope)

### 3.2 A specs review step (against authoritative source docs)

After creating `specs/**/*.md`, a review step should:
- Cross-reference every type, method, and enum value against the authoritative spec doc
- Verify naming conventions match
- Check that every scenario is testable

**Would have caught:** Issues #2 (LogLevel), #9 (Transform semantics), and #10-11 (version format, constexpr-ness)

### 3.3 A design review step (against the actual codebase)

After creating `design.md`, a review step should:
- Verify every CMake target name exists (grep for `add_library`)
- Verify every file path referenced exists or is correctly planned
- Check that dependency names match reality

**Would have caught:** Issues #1 (xtrk_legacy target name), #6 (GTest version), #7 (cmake/testing.cmake)

### 3.4 A tasks review step (against design + specs)

After creating `tasks.md`, a review step should:
- Verify every spec requirement has at least one task
- Check task ordering makes sense (dependencies satisfied)
- Verify implementation-critical details are explicit (pimpl rules, forward declarations)

**Would have caught:** Issues #4 (pimpl), #5 (forward declarations), #8 (task ordering)

### 3.5 Summary: built-in review would have caught 12 of 13 issues

Only issue #12 (build-time legacy header check) and #13 (documenting PUBLIC cxx_std_23) were enhancement suggestions rather than error corrections. Every factual error would have been caught by systematic artifact-level review.

---

## 4. Proposed Improvements

### 4.1 Replace `/opsx:propose` with stepped artifact creation in `/plan-spec`

**Current flow:**
```
/plan-spec conversation → compile context → /opsx:propose (creates all 4 artifacts) → done
```

**Proposed flow:**
```
/plan-spec conversation → compile context →
  create proposal → review proposal → confirm →
  create specs → review specs (cross-ref source docs) → confirm →
  create design → review design (verify against codebase) → confirm →
  create tasks → review tasks (cross-ref specs + design) → confirm →
  done
```

Each review step uses a lightweight sub-agent with a specific review mandate (like the two ad-hoc reviewers in this session, but targeted to one artifact at a time).

**Implementation:** `/plan-spec` should NOT invoke `/opsx:propose`. Instead, it should use `openspec instructions <artifact>` directly for each artifact, with a review checkpoint between each.

### 4.2 Define artifact-level review checklists

Each artifact type should have a specific review checklist. These can be added to the OpenSpec schema or to the sdd-workflow planning template.

**Proposal review checklist:**
- [ ] Every capability maps to a roadmap deliverable or user requirement
- [ ] No scope creep (capabilities not in the phase/epic are flagged)
- [ ] Terminology matches project conventions (CLAUDE.md terminology table)

**Specs review checklist:**
- [ ] Every type/method/enum value cross-referenced against authoritative spec doc
- [ ] Every scenario is concrete and testable (specific inputs → specific outputs)
- [ ] Naming conventions match project standards
- [ ] No requirements contradict each other

**Design review checklist:**
- [ ] Every referenced target/file/path verified against actual codebase
- [ ] Every dependency verified as available (CMake target exists, library installable)
- [ ] Forward declarations and include DAG verified for feasibility
- [ ] Pimpl and lifetime management rules explicit for relevant classes
- [ ] Build system changes verified against current build configuration

**Tasks review checklist:**
- [ ] Every spec requirement has ≥1 task
- [ ] Every task has ≥1 spec requirement it traces to
- [ ] Task ordering respects build dependencies
- [ ] Implementation-critical patterns (pimpl, forward decl, etc.) are explicit in task descriptions
- [ ] Build/test verification tasks are present

### 4.3 Add a `/review-spec-artifact` skill

A lightweight skill that:
1. Takes a change name and artifact ID
2. Loads the artifact and its dependencies
3. Loads relevant source-of-truth documents (detected from project template)
4. Runs a targeted review using the appropriate checklist
5. Reports findings as a structured list

This could be invoked automatically between artifacts in `/plan-spec`, or manually by the user after any artifact edit.

### 4.4 Add semantic validation to `openspec validate`

Currently `openspec validate` only does structural validation (does the YAML parse? do files exist?). It could be extended with:
- **Cross-reference validation:** Do spec requirements reference real source-of-truth sections?
- **Naming validation:** Do type/method names match naming conventions?
- **Coverage validation:** Does every capability in the proposal have specs? Do specs have tasks?

This would complement the review step with automated checks.

### 4.5 Redesign `/plan-spec` as a coordinator, not a monolithic workflow

Currently `/plan-spec` is a single skill with 4 steps:
1. Detect project context
2. Gather external context
3. Interactive planning conversation
4. Compile and invoke `/opsx:propose`

**Proposed redesign:**

```
/plan-spec (coordinator)
  Step 1: Detect project context (unchanged)
  Step 2: Gather external context (unchanged)
  Step 3: Interactive planning conversation (unchanged)
  Step 4: Create proposal artifact
  Step 5: Review proposal (sub-agent or inline)
  Step 6: Create specs artifacts
  Step 7: Review specs (sub-agent with source-doc cross-ref mandate)
  Step 8: Create design artifact
  Step 9: Review design (sub-agent with codebase verification mandate)
  Step 10: Create tasks artifact
  Step 11: Review tasks (sub-agent with coverage/ordering mandate)
  Step 12: Final status report
```

Steps 5, 7, 9, 11 are the new review checkpoints. Each can be:
- **Inline** (same agent reviews its own work — fast but lower quality)
- **Sub-agent** (fresh context, specific mandate — higher quality, higher cost)
- **User** (pause and ask — highest quality, highest latency)

The skill should support a `--review-mode` flag:
- `--review-mode=inline` (default, fast)
- `--review-mode=agent` (sub-agents review each artifact)
- `--review-mode=interactive` (pause for user review after each artifact)

---

## 5. Broader Evaluation: SDD-Workflow Planning Phase

### What works well

1. **The interactive conversation IS valuable.** The 5 scoping questions in this session caught real issues (header path conflict, static vs shared) that would have cascaded through all artifacts. This should not be automated away.

2. **The project-specific planning template** (`.claude/sdd-workflow/spec-planning-template.md`) is excellent. It pre-populates domain context, constraints, naming conventions, and quality requirements. Every planning session starts with accurate project context.

3. **`openspec instructions`** provides per-artifact guidance with context-aware templates. The `dependencies` field correctly sequences artifact creation.

4. **The back-and-forth catches misunderstandings early.** This is correctly emphasized in the README ("The back-and-forth conversation IS the product").

### What needs improvement

1. **No review between artifacts.** This is the central finding. The planning conversation is high-level; artifact-level review needs to happen at artifact granularity.

2. **`/opsx:propose` encourages batch creation.** Its prompt explicitly says "loop through artifacts... continue until all `applyRequires` artifacts are complete." This fights against the iterative review that would catch errors.

3. **No source-of-truth cross-referencing.** The planning template lists authoritative docs, but nothing systematically compares generated artifacts against them. This is where most errors come from.

4. **No codebase verification during design.** Design decisions reference CMake targets, file paths, and dependencies that may not exist. A `grep`/`glob` verification step would catch these instantly.

5. **Review is entirely absent from the SDD-Workflow lifecycle diagram.** The README's mermaid flowchart shows: `/plan-spec` → `/opsx:propose` → OpenSpec Artifacts → `/generate-spec-beads`. There is no review step between artifact creation and bead generation. Review only appears during implementation (review agents in the impl/test/review triad).

### Comparison: planning review vs implementation review

The SDD-Workflow has **excellent implementation-phase review:**
- Per-feature review agents
- Test-authoring agents independent of implementation
- Gap bead filing for review findings
- Source-level verification in spec-completion-auditor

But **no planning-phase review:**
- No per-artifact review
- No source-doc cross-referencing
- No codebase verification
- No coverage checking

This is backwards. Errors caught during planning cost minutes to fix. Errors caught during implementation cost hours (rewrite code, re-run tests, re-review). Errors caught during audit cost even more (may require reopening closed beads).

---

## 6. Recommended Actions

### Priority 1: Fix `/plan-spec` to stop invoking `/opsx:propose`

**Effort:** Medium (modify SKILL.md)
**Impact:** High — prevents the batch-generation problem

Instead of Step 4 ("Compile and invoke `/opsx:propose`"), `/plan-spec` should create artifacts one at a time using `openspec instructions`, with a review checkpoint after each.

### Priority 2: Create `/review-spec-artifact` skill

**Effort:** Medium (new SKILL.md)
**Impact:** High — provides the missing review capability

A skill that takes a change name + artifact ID, loads the artifact and its source-of-truth docs, and runs a targeted review. Can be invoked by `/plan-spec` between artifacts or manually by users.

### Priority 3: Add review checklists to the planning template

**Effort:** Low (edit `spec-planning-template.md`)
**Impact:** Medium — gives review steps structure

Add per-artifact review checklists to `.claude/sdd-workflow/spec-planning-template.md` so they're automatically loaded into planning sessions.

### Priority 4: Update the README lifecycle diagram

**Effort:** Low (edit README.md)
**Impact:** Low-medium — communicates the correct workflow

Add review steps to the mermaid flowchart between artifact creation and bead generation.

### Priority 5: Consider `openspec validate` enhancements

**Effort:** High (OpenSpec CLI changes)
**Impact:** Medium — automates some review checks

Semantic validation (cross-referencing, naming, coverage) would complement review agents. This is a longer-term improvement for the OpenSpec project.

---

## 7. Session Metrics

| Metric | Value |
|--------|-------|
| Planning conversation rounds | 3 (context gather → questions → answers) |
| Artifacts created | 8 (proposal, design, 4 specs, tasks, + fixes) |
| Issues found by reviewers | 13 (3 critical, 6 high, 4 low) |
| Issues that were preventable with per-artifact review | 12 of 13 |
| Token cost of ad-hoc review | ~60K tokens (2 exploration agents reading everything) |
| Estimated token cost of inline per-artifact review | ~20K tokens (4 smaller focused checks) |
| Fix application time | ~15 edits across 6 files |

---

## 8. Critical Finding: OpenSpec Already Supports Stepwise Creation

The investigation revealed that **OpenSpec already provides the full stepwise infrastructure** — `/opsx:propose` is a convenience wrapper that collapses it. The fix is to use the primitives directly.

### Available primitives

| Command | Purpose |
|---------|---------|
| `openspec new change <name>` | Creates change directory, initializes artifact tracking |
| `openspec status --change <name> --json` | Returns per-artifact status: `ready`, `blocked`, `done` |
| `openspec instructions <artifact-id> --change <name> --json` | Returns template, instruction, dependencies for ONE artifact |
| `openspec validate <name>` | Structural validation of completed artifacts |

### Built-in gating

OpenSpec **automatically blocks** downstream artifacts until dependencies are written to disk:

```
# Fresh change — only proposal is ready
proposal     status=ready     missingDeps=none
design       status=blocked   missingDeps=['proposal']
specs        status=blocked   missingDeps=['proposal']
tasks        status=blocked   missingDeps=['design', 'specs']
```

After `proposal.md` is written, `status` automatically unblocks `design` and `specs`. After both are written, `tasks` unblocks. This is the natural review checkpoint — the skill just needs to pause between steps instead of looping.

### What `/opsx:propose` does wrong

It takes this gating infrastructure and collapses it into a tight generate loop:
```
for each ready artifact:
    get instructions → write file → check status → next
```
No review. No pause. No validation between artifacts. The dependency chain becomes a generation order, not a quality gate.

### The fix is simple

`/plan-spec` should call OpenSpec primitives directly instead of delegating to `/opsx:propose`:

```
openspec new change "<name>"

# Each cycle: get instructions → create artifact → review → next
openspec instructions proposal → write → ★ review ★
openspec instructions specs    → write → ★ review ★
openspec instructions design   → write → ★ review ★
openspec instructions tasks    → write → ★ review ★
```

**This is not a missing capability — it's a misuse of an existing one.** The tooling supports stepped creation with dependency gating. The skill just needs to use it.

---

## Appendix: OpenSpec Artifact Dependency Chain (Reference)

From `/home/appuser/.npm-global/lib/node_modules/@fission-ai/openspec/schemas/spec-driven/schema.yaml`:

```yaml
artifacts:
  - id: proposal    # requires: []           → unlocks: specs, design
  - id: specs       # requires: [proposal]   → unlocks: tasks
  - id: design      # requires: [proposal]   → unlocks: tasks
  - id: tasks       # requires: [specs, design]
apply:
  requires: [tasks]
```

Each artifact has `openspec instructions <id>` which returns template, instruction, dependencies, and unlocks. This chain is designed for stepped creation — the tooling supports it, but `/plan-spec` bypasses it.
