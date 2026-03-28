---
name: plan-spec
description: Interactive spec planning that automates context gathering (JIRA tickets, roadmap phases, project patterns) and drives a structured back-and-forth conversation leading to /opsx:propose. Use when starting a new body of work — replaces manually editing a spec planning template. Detects available context sources and adapts the flow accordingly.
user-invocable: true
---

# Plan Spec

Interactive planning that gathers context automatically, drives a structured conversation, and produces high-quality OpenSpec artifacts via `/opsx:propose`.

**Input**: `/plan-spec <change-name> [PROJ-123 PROJ-456 ...] [--epic N]`

- `<change-name>`: kebab-case name for the OpenSpec change (required)
- `PROJ-123 ...`: JIRA ticket IDs (optional — triggers JIRA context gathering)
- `--epic N`: Roadmap epic number for phase context (optional)

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

## Step 3: Interactive planning conversation

**The back-and-forth dialog IS the product.** Do not rush through this to "be efficient." The conversation catches misunderstandings that would otherwise become expensive bugs during implementation.

### 3a: Establish scope

Present what you've gathered and ask the user to fill gaps:

```
## Planning: <change-name>

### What I found
- <JIRA: N tickets with X acceptance criteria>
- <Roadmap: Epic N — "<title>">
- <Project: <language>, <framework>, <key patterns>>
- <Active changes: N (relevant: ...)>

### Scope
<Synthesize a clear statement of what this change will accomplish, drawing from JIRA tickets, roadmap context, and user input>

### Questions before we proceed
1. Does this scope match what you have in mind? Anything to add or exclude?
2. Are there constraints I should know about? (performance, compatibility, budget)
3. Any design preferences? (patterns to follow, modules to avoid touching)
4. What don't you know yet? (research questions, unknowns to investigate)
```

**Wait for the user's response.** Their answers shape everything downstream.

### 3b: Research phase

Based on scope and user answers, investigate unknowns:

- **Read relevant source code** to understand current architecture, patterns, and integration points
- **Check APIs, libraries, or dependencies** mentioned in the scope
- **Verify assumptions** about existing code (function signatures, module boundaries, configuration)
- **Identify technical risks** or unknowns that could affect the design

Present findings and ask follow-up questions:

```
### Research findings
1. <Finding — e.g., "The auth module uses middleware chain pattern, new feature should follow same">
2. <Finding — e.g., "Library X doesn't support feature Y — alternative Z does, with trade-off...">
3. <Risk — e.g., "Module A assumes single-tenant; this change introduces multi-tenant, needs refactor">

### Design questions
1. <Should we extend existing module or create a new one? Trade-offs: ...>
2. <Approach A (simpler, less flexible) vs Approach B (more work, extensible) — preference?>
```

**Wait for the user's response.** Multiple rounds are normal and valuable. Iterate until both sides are confident in the direction.

### 3c: Design alignment

Once scope and research are settled, propose the high-level design:

```
### Proposed approach
- **Module structure:** <where new code lives, how it integrates>
- **Key interfaces:** <API shape, data flow>
- **Testing strategy:** <what gets unit tests, integration tests, smoke tests>
- **Integration points:** <where this touches existing code>

### Task decomposition (rough)
1. <Task group 1: description — N subtasks>
2. <Task group 2: description — M subtasks>
3. <Testing: unit + integration tasks>

### Acceptance criteria summary
<Consolidated list from JIRA (verbatim) + user-specified criteria>

Does this match your mental model? Anything to adjust before generating the full spec?
```

**Wait for confirmation or adjustments.** This is the last checkpoint before artifact generation.

---

## Step 4: Compile and invoke /opsx:propose

Once alignment is reached, compile the full planning context. **Present it to the user for review before invoking** — they should see exactly what goes into the planning prompt.

```
## Compiled planning context for /opsx:propose

### What to build
<Refined description incorporating all discussion>

### Source references
<JIRA tickets, roadmap epics, linked specs — with IDs>

### Research findings
<Key findings that should inform spec design>

### Known constraints
<From user input, project template, and discovery>

### Design decisions
<Agreed-upon approach from Step 3c>

### Quality requirements
- [ ] All tasks must have concrete acceptance criteria
- [ ] Include test tasks for every module
- [ ] Tests must reference specific spec scenarios
<Project-specific quality gates from template>

### Acceptance criteria (from JIRA)
<Verbatim JIRA acceptance criteria — these are authoritative>

### Process instructions
Research first. Come back with questions. Challenge defaults. Review your work. Generate all artifacts.
```

After the user confirms, invoke `/opsx:propose <change-name>` with the compiled context.

**After `/opsx:propose` completes:**

```
Planning complete. Artifacts at: openspec/changes/<change-name>/

Next step: /generate-spec-beads <change-name>
```

---

## Guardrails

- **The conversation is the value.** Don't collapse the interactive steps into a single prompt. The back-and-forth catches misunderstandings early.
- **JIRA is authoritative when active.** If the user's description conflicts with JIRA acceptance criteria, flag the conflict explicitly — don't silently prefer one.
- **Don't auto-submit to /opsx:propose.** Present the compiled context for review first.
- **Research the actual codebase.** Don't assume APIs, module structure, or patterns — read the code. This prevents specs that describe aspirational architecture instead of reality.
- **The template is a guide, not a script.** Skip sections that don't apply. Expand sections that need depth. Follow the conversation wherever it goes.
- **Flag vague acceptance criteria.** If a JIRA criterion is untestable ("should be fast", "must be user-friendly"), ask for specific targets before proceeding.
- **Don't over-gather.** If JIRA MCP isn't available, that's fine — proceed without it. If there's no roadmap, skip that section. Adapt to what exists.

ARGUMENTS: $ARGUMENTS
