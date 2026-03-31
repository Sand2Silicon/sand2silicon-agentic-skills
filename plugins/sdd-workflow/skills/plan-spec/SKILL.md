---
name: plan-spec
description: Automated context gathering (JIRA tickets, roadmap phases, project patterns) that feeds OpenSpec's planning workflow. Gathers context, assesses complexity, then routes to /opsx:explore (interactive research) or /opsx:propose (direct artifact generation). Use when starting a new body of work.
user-invocable: true
---

# Plan Spec

Automated context gathering that feeds OpenSpec's planning workflow. Gathers project context, assesses complexity, and routes to the right OpenSpec command — `/opsx:explore` for complex/ambiguous work, `/opsx:propose` for well-defined work.

**Input**: `/plan-spec <change-name> [PROJ-123 PROJ-456 ...] [--epic N] [--explore] [--no-explore]`

- `<change-name>`: kebab-case name for the OpenSpec change (required)
- `PROJ-123 ...`: JIRA ticket IDs (optional — triggers JIRA context gathering)
- `--epic N`: Roadmap epic number for phase context (optional)
- `--explore`: Force routing to `/opsx:explore` before `/opsx:propose`
- `--no-explore`: Skip explore, go directly to `/opsx:propose` with gathered context

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

## Step 3: Review context and assess complexity

Present a brief summary of gathered context and assess whether this work needs interactive exploration or can go directly to artifact generation.

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

If `--explore` or `--no-explore` was specified, respect the flag. Otherwise, assess and recommend:

**Signals that favor `/opsx:explore` first:**
- No JIRA tickets or vague/missing acceptance criteria
- Multiple unknowns or open research questions
- Cross-cutting change touching 3+ modules or introducing a new pattern
- User's description is exploratory ("figure out how to...", "investigate...", "not sure about...")
- Novel architecture not seen in the codebase

**Signals that favor direct `/opsx:propose`:**
- Clear JIRA tickets with concrete, testable acceptance criteria
- Well-understood pattern (extending existing module in an established way)
- Small/focused scope within a single module
- User stated specific design preferences or constraints upfront

Present the recommendation:

```
### Recommended path

**→ explore first** (or **→ direct to propose**)
Reasoning: <1-2 sentences citing specific signals from the gathered context>

Confirm, or override with `explore` / `no-explore`.
```

**Wait for user confirmation.** Then proceed to Step 4a or 4b accordingly.

---

## Step 4a: Explore path — invoke /opsx:explore

When the explore path is chosen, compile the gathered context and hand off to OpenSpec's interactive exploration. The back-and-forth conversation happens inside `/opsx:explore`, not here.

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

After `/opsx:explore` concludes and the user is satisfied with the direction, proceed:

```
Exploration complete. Ready to generate artifacts.

→ Invoking /opsx:propose <change-name> with the explored context.
```

Then invoke `/opsx:propose <change-name>`. The conversation context from explore carries forward — no need to re-compile. `/opsx:propose` will generate the artifacts informed by the exploration.

---

## Step 4b: Direct path — invoke /opsx:propose

When going directly to propose, compile the gathered context with process instructions that tell propose to drive any remaining interactive planning as part of artifact generation.

**Present the compiled context to the user for review before invoking.**

```
/opsx:propose <change-name>

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

### Acceptance criteria (from JIRA)
<Verbatim JIRA acceptance criteria — these are authoritative>

### Process instructions
This should be a back-and-forth conversation, not a one-shot generation:
1. **Research first** — investigate unknowns before proposing anything. Read the actual codebase, check APIs, verify assumptions.
2. **Come back with questions** — present options, trade-offs, and ask for input on design decisions before generating artifacts.
3. **Challenge your own defaults** — if the "textbook" answer seems too simple, dig deeper. The user will push back if something feels off.
4. **Review your own work** — after generating artifacts, objectively audit for completeness, coherence, circular dependencies, and gaps.
5. **Generate all artifacts** — proposal, design, specs (with acceptance scenarios), tasks (with acceptance criteria), and test tasks.
```

After the user confirms the context, invoke `/opsx:propose <change-name>` with the compiled context.

**After `/opsx:propose` completes:**

```
Planning complete. Artifacts at: openspec/changes/<change-name>/

Next step: /generate-spec-beads <change-name>
```

---

## Guardrails

- **Plan-spec gathers context; OpenSpec drives conversation.** Don't duplicate the interactive planning that `/opsx:explore` or the process instructions in `/opsx:propose` will handle. Your job is to automate the context gathering and route to the right workflow.
- **JIRA is authoritative when active.** If the user's description conflicts with JIRA acceptance criteria, flag the conflict explicitly — don't silently prefer one.
- **Don't auto-submit.** Present the compiled context for review before invoking explore or propose.
- **Flag vague acceptance criteria.** If a JIRA criterion is untestable ("should be fast", "must be user-friendly"), ask for specific targets before proceeding.
- **Don't over-gather.** If JIRA MCP isn't available, that's fine — proceed without it. If there's no roadmap, skip that section. Adapt to what exists.
- **The template is a guide, not a script.** Skip sections that don't apply. Expand sections that need depth.

ARGUMENTS: $ARGUMENTS
