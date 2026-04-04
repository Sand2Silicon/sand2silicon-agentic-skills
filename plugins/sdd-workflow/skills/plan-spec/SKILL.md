---
name: plan-spec
description: Interactive planning that gathers project context (JIRA, roadmap, patterns), creates OpenSpec artifacts stepwise with per-artifact review checkpoints, and runs two independent reviewer sub-agents for final quality validation. Catches errors during planning (minutes to fix) rather than implementation (hours). Use when starting a new body of work.
user-invocable: true
---

# Plan Spec

Interactive context gathering and stepwise artifact creation for OpenSpec changes. Gathers project context, assesses complexity, creates artifacts one at a time with review checkpoints after each, and runs two independent final reviewers before downstream work begins.

**Input**: `/plan-spec <change-name> [PROJ-123 PROJ-456 ...] [--epic N] [--explore] [--fast]`

- `<change-name>`: kebab-case name for the OpenSpec change (required)
- `PROJ-123 ...`: JIRA ticket IDs (optional — triggers JIRA context gathering)
- `--epic N`: Roadmap epic number for phase context (optional)
- `--explore`: Force interactive exploration (`/opsx:explore`) before artifact creation
- `--fast`: Batch-generate via `/opsx:propose` instead of stepwise (still gets mandatory final review)

---

## Step 1: Detect project context

Run these checks in parallel to understand what's available:

```bash
# Project-specific planning template?
cat .claude/sdd-workflow/spec-planning-template.md 2>/dev/null && echo "---PROJECT_TEMPLATE_FOUND---"

# Roadmap files?
ls docs/Roadmap*.md roadmap.md docs/roadmap.md 2>/dev/null

# Existing OpenSpec changes?
ls openspec/changes/ 2>/dev/null

# Project identity
head -60 CLAUDE.md 2>/dev/null
head -60 README.md 2>/dev/null
```

Check if JIRA MCP server is available by attempting a lightweight query. Note result.

**Load the planning template:**
- If `.claude/sdd-workflow/spec-planning-template.md` exists: use it (project-specific, created by `/sdd-workflow-init`)
- Otherwise: use the base template from `templates/spec-planning-template.md` in this plugin
- The template structures the conversation — treat it as a guide, not a form to auto-fill

**If no project template exists**, mention it:
> No project-specific template found. Run `/sdd-workflow-init` to create one with your project's domain context, toolchain, and conventions pre-filled.

---

## Step 2: Gather external context

Based on what's available, gather context in parallel:

### If JIRA tickets were provided

Fetch each ticket via JIRA MCP. For each ticket, extract:
- Summary and full description
- Acceptance criteria (look for "Acceptance Criteria" heading, "AC:", or numbered criteria)
- Priority, status, linked tickets (blocks/blocked-by, epic link)

Present the JIRA context to the user:

```
## JIRA Context

### PROJ-123: <summary>
**Acceptance criteria:**
1. <criterion 1>
2. <criterion 2>
**Priority:** <priority> | **Links:** blocks PROJ-124, epic PROJ-100

### PROJ-456: <summary>
...
```

**JIRA acceptance criteria are authoritative.** If any criterion is vague or untestable, flag it now — the user should clarify or update the ticket before planning proceeds.

### If a roadmap epic was referenced (--epic N)

```bash
cat docs/Roadmap*.md roadmap.md docs/roadmap.md 2>/dev/null
```

Extract the referenced epic's title, description, and key deliverables. Note dependency relationships with other epics and phase context (what comes before/after).

The roadmap provides organizational context — it groups work into phases but is not itself a requirements source. OpenSpec and JIRA carry the actual requirements.

### If existing OpenSpec changes exist

```bash
ls openspec/changes/*/tasks.md 2>/dev/null
```

List active changes and their completion status (count of `[x]`, `[~]`, `[ ]` tasks). Note any that might overlap with or depend on the proposed work.

---

## Step 3: Assess complexity and choose path

Present a brief summary of gathered context and recommend a creation path.

### 3a: Context summary

```
## Planning: <change-name>

### What I found
- <JIRA: N tickets with X acceptance criteria>
- <Roadmap: Epic N — "<title>">
- <Project: <language>, <framework>, <key patterns>>
- <Active changes: N (relevant: ...)>

### Scope
<Synthesize a clear statement of what this change will accomplish, drawing from JIRA tickets, roadmap context, and user input>
```

### 3b: Route decision

If `--explore` or `--fast` was specified, respect the flag. Otherwise, assess and recommend:

**→ Explore first** when:
- No JIRA tickets or vague/missing acceptance criteria
- Multiple unknowns or open research questions
- Cross-cutting change touching 3+ modules or introducing a new pattern
- User's description is exploratory ("figure out how to...", "investigate...", "not sure about...")

**→ Stepwise** (default for most work):
- Clear requirements (JIRA tickets, roadmap, or user-stated)
- Moderate complexity — enough substance that artifacts benefit from individual review
- Any work where errors caught later would be expensive

**→ Fast (`--fast`)** when user explicitly requests speed:
- Tiny scope (single file, obvious change, trivial extension)
- Extending an existing pattern with no ambiguity
- Still gets mandatory final review — the only skip is per-artifact checkpoints

Present the recommendation:

```
### Recommended path

**→ explore first** / **→ stepwise** / **→ fast**
Reasoning: <1-2 sentences citing specific signals>

Confirm, or override with `explore` / `fast`.
```

**Wait for user confirmation before proceeding.**

---

## Step 4a: Explore path

Compile gathered context and hand off to `/opsx:explore` for interactive research. The back-and-forth conversation happens inside explore, not here.

```
/opsx:explore <change-name>

## Context gathered by plan-spec

### What to build
<Scope statement from Step 3a>

### Source references
<JIRA tickets (with verbatim acceptance criteria), roadmap epics, linked specs — with IDs>

### Known constraints
<From user input, project template, and discovery>

### Domain context
<From project-specific planning template, if available>

### Quality requirements
- [ ] All tasks must have concrete acceptance criteria (verifiable pass/fail)
- [ ] Include test-creation tasks for every module (unit + integration)
- [ ] Tests must reference specific spec scenarios they validate
<Project-specific quality gates from template>

### What to investigate
<Open questions, unknowns, research areas identified during context gathering>
```

After `/opsx:explore` concludes and the user is satisfied with the direction:

```
Exploration complete. Proceeding to stepwise artifact creation.
```

**Continue to Step 4b** — carry the exploration findings forward as additional planning context. The explore transcript and conclusions inform artifact creation without re-researching the same questions.

---

## Step 4b: Stepwise artifact creation (default)

Create artifacts one at a time with a review checkpoint after each. This prevents errors from cascading through the artifact chain — an incorrect name in the proposal propagates to specs, design, and tasks if never reviewed.

### Compile and present planning context

```
## Planning context for: <change-name>

### What to build
<Scope statement from Step 3a>

### Source references
<JIRA tickets (with verbatim acceptance criteria), roadmap epics, linked specs>

### Known constraints
<From user input, project template, and discovery>

### Domain context
<From project-specific planning template>

### Quality requirements
- [ ] All tasks must have concrete acceptance criteria (verifiable pass/fail)
- [ ] Include test-creation tasks for every module (unit + integration)
- [ ] Tests must reference specific spec scenarios they validate
<Project-specific quality gates from template>
```

**Wait for user to confirm the context is correct before creating artifacts.**

### Create each artifact with inline review

Use `openspec instructions <artifact> --change <change-name>` to get the template and context for each artifact. Create the artifact, then run its review checklist before proceeding.

If `/opsx:continue` is available (OpenSpec expanded profile), prefer it — it handles file creation and status tracking. Otherwise, create artifacts manually using the `openspec instructions` output.

**4b-i: Proposal → review → confirm**

Create `proposal.md` using the planning context.

**Inline review checklist — verify before proceeding:**

| Check | What to verify |
|-------|----------------|
| Scope alignment | Every capability maps to a roadmap deliverable or JIRA ticket |
| No scope creep | No capabilities beyond the target phase/epic — flag any with evidence |
| Terminology | Names match project conventions (CLAUDE.md, existing specs, style guides) |
| Feasibility | Approach is achievable given known constraints and current codebase |

Present a brief review summary. **Ask the user to confirm or request changes.**

**4b-ii: Specs → review → confirm**

Create spec files reading `proposal.md` for context.

**Inline review checklist — this is the highest-error-rate artifact:**

| Check | What to verify |
|-------|----------------|
| Source-of-truth cross-reference | Every type, method, enum value, API, constant cross-referenced against authoritative docs or existing code |
| Naming accuracy | All names verified against the actual codebase (`grep`, `find`) — not assumed |
| Testable scenarios | Every scenario has specific inputs → specific expected outputs (Given/When/Then) |
| No contradictions | Requirements don't conflict with each other or existing specs |
| JIRA coverage | Every JIRA acceptance criterion reflected in a spec scenario (when active) |

**Do not skip source-of-truth verification.** Read the actual spec docs, grep the actual codebase. This is where most critical errors originate.

Present review summary. **Confirm before proceeding.**

**4b-iii: Design → review → confirm**

Create `design.md` reading `proposal.md` for context.

**Inline review checklist:**

| Check | What to verify |
|-------|----------------|
| Codebase verification | Every file path, module name, build target grep/glob-verified against the actual codebase |
| Dependency verification | Every external dependency is available and version-pinned with correct API |
| Build system feasibility | Build changes verified against current CMake/make/cargo/npm configuration |
| Pattern consistency | Architecture follows established project patterns (check existing modules) |
| Lifetime and ownership | Memory management, threading, ownership rules explicit where relevant |

Present review summary. **Confirm before proceeding.**

**4b-iv: Tasks → review → confirm**

Create `tasks.md` reading specs and design for context.

**Inline review checklist:**

| Check | What to verify |
|-------|----------------|
| Requirement coverage | Every spec requirement has ≥1 task |
| Task traceability | Every task traces to ≥1 spec requirement |
| Ordering validity | Task dependencies respect build order (can't test what isn't compiled) |
| Acceptance criteria | Every task has specific, verifiable acceptance criteria |
| Implementation patterns | Critical patterns explicit in task descriptions (pimpl, forward decl, error handling, thread safety) |
| Test task pairing | Every implementation task has a corresponding test task |

Present review summary. **Confirm before proceeding.**

After all four artifacts are reviewed and confirmed, proceed to **Step 5**.

---

## Step 4c: Fast path (`--fast` only)

For small, well-defined changes where per-artifact review would be overhead. **Note:** This skips per-artifact review checkpoints, relying solely on the final two-agent review (Step 5) to catch errors. Expect more review findings than the stepwise path — errors cascade through artifacts when not caught early.

Compile the full planning context and invoke:

```
/opsx:propose <change-name>

<compiled planning context from Step 4b header>

### Process instructions
This should be a back-and-forth conversation, not a one-shot generation:
1. **Research first** — investigate unknowns before proposing anything. Read the actual codebase.
2. **Come back with questions** — present options and trade-offs. Ask for input on design decisions.
3. **Challenge your own defaults** — if the textbook answer seems too simple, dig deeper.
4. **Review your own work** — after generating, audit for completeness, coherence, and accuracy.
```

After `/opsx:propose` completes, proceed to **Step 5** — final review is mandatory even on the fast path.

---

## Step 5: Two-agent independent review (MANDATORY — all paths)

After all artifacts exist, launch **two independent reviewer sub-agents** with different mandates. They work independently — neither sees the other's findings. This prevents anchoring bias and ensures different error classes are caught.

### 5a: Launch accuracy reviewer

Launch a sub-agent with the **spec-accuracy-reviewer** mandate (see `agents/spec-accuracy-reviewer/AGENT.md`):

```
Review the OpenSpec artifacts at openspec/changes/<change-name>/ for factual accuracy.

Your mandate — verify every factual claim against reality:

1. SOURCE-OF-TRUTH CROSS-REFERENCE: For every type, method, enum value, API, and constant
   in the specs — find the authoritative source doc or existing code and verify the name,
   signature, and semantics are correct.

2. CODEBASE VERIFICATION: For every file path, build target, module name, and dependency
   in the design — grep/glob the actual codebase to confirm they exist and match.

3. DEPENDENCY VERIFICATION: For every external library or tool — verify the version exists
   and the API matches what's described.

4. NAMING CONVENTION AUDIT: Cross-reference all new names against the project's naming
   conventions (from CLAUDE.md, existing code, style guides).

5. SEMANTIC ACCURACY: For every behavioral claim ("X returns Y", "Z throws on invalid
   input") — verify against source docs or existing tests.

Report each finding as: severity (CRITICAL/HIGH/LOW), artifact, finding, evidence, suggested fix.
```

### 5b: Launch completeness reviewer (in parallel)

Launch a second independent sub-agent with the **spec-completeness-reviewer** mandate (see `agents/spec-completeness-reviewer/AGENT.md`):

```
Review the OpenSpec artifacts at openspec/changes/<change-name>/ for completeness and coherence.

Context: JIRA tickets: <IDs if active>. Roadmap epic: <ref if active>.

Your mandate — verify nothing is missing, misaligned, or structurally unsound:

1. REQUIREMENTS COVERAGE: Every JIRA acceptance criterion (when active) has a corresponding
   spec scenario. Every spec requirement has ≥1 task. Every task traces to ≥1 requirement.

2. SCOPE ALIGNMENT: No capabilities beyond the target phase/epic. Flag scope creep with
   evidence from the roadmap. No features that belong to future phases.

3. TASK ORDERING: Tasks can be executed in the specified order. Build dependencies are
   satisfied. Cross-module dependencies are explicit. No circular dependencies.

4. IMPLEMENTATION COMPLETENESS: Critical patterns explicit in task descriptions (pimpl,
   forward declarations, error handling, thread safety). Build system changes covered.
   CI/CD updates included if needed.

5. COHERENCE: Proposal → specs → design → tasks tell a consistent story. Design decisions
   reflected in tasks. Spec scenarios reflected in test tasks. No contradictions.

Report each finding as: severity (CRITICAL/HIGH/LOW), artifact, finding, evidence, suggested fix.
```

### 5c: Collect and present findings

After both reviewers complete, merge and deduplicate their findings:

```
## Planning Review: <change-name>

### Accuracy Review (N findings)
| # | Severity | Artifact | Finding | Suggested Fix |
|---|----------|----------|---------|---------------|

### Completeness Review (N findings)
| # | Severity | Artifact | Finding | Suggested Fix |
|---|----------|----------|---------|---------------|

### Summary
- Critical: N (must fix before proceeding)
- High: N (should fix before proceeding)
- Low: N (optional improvements)
```

**If any CRITICAL findings:** Apply fixes to the artifacts. Re-run the relevant inline checklist (from Step 4b) on fixed artifacts to confirm the fix doesn't introduce new issues.

**If only HIGH/LOW:** Present to user. Apply agreed fixes.

**Wait for user confirmation** that review findings are addressed before proceeding.

---

## Step 6: Wrap up

After review findings are resolved:

```
Planning complete. Artifacts at: openspec/changes/<change-name>/

Review results: N findings addressed, M deferred.

Next step: /generate-spec-beads <change-name>
```

---

## Guardrails

- **Plan-spec owns the full planning lifecycle.** Context gathering, artifact creation with review, and final validation — all happen here, not delegated blindly to a batch generator.
- **Stepwise is the default; fast is the exception.** Batch artifact generation via `--fast` is only for tiny, obvious changes. When in doubt, use stepwise.
- **JIRA is authoritative when active.** If the user's description conflicts with JIRA acceptance criteria, flag the conflict explicitly.
- **Don't auto-submit.** Present compiled context for review before creating artifacts. Present each artifact for review before proceeding to the next.
- **Flag vague acceptance criteria.** If a JIRA criterion is untestable ("should be fast", "must be user-friendly"), ask for specific targets before proceeding.
- **Don't over-gather.** If JIRA MCP isn't available, proceed without it. If there's no roadmap, skip that section. Adapt to what exists.
- **Final review is not optional.** Every path — explore, stepwise, fast — ends with the two-agent independent review. The cost of catching errors during planning is minutes; during implementation, hours.
- **Reviewers must be independent.** Launch both sub-agents before reading either's output. Neither should see the other's findings — this prevents anchoring bias and ensures they catch different error classes.
- **The template is a guide, not a script.** Skip sections that don't apply. Expand sections that need depth.

ARGUMENTS: $ARGUMENTS
