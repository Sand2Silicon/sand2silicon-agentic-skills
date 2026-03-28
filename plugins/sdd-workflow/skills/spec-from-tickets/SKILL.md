---
name: spec-from-tickets
description: Fast path from JIRA tickets to OpenSpec artifacts and Beads. Use when JIRA tickets are well-defined with clear acceptance criteria and the full interactive planning session of /plan-spec would be unnecessary overhead. Fetches tickets via JIRA MCP, evaluates quality, and generates specs or creates beads directly.
user-invocable: true
---

# Spec From Tickets

Convert well-defined JIRA tickets directly into OpenSpec artifacts and optionally into a Beads dependency graph, bypassing the interactive planning conversation.

**Input**: `/spec-from-tickets PROJ-123 [PROJ-456 ...] [--direct]`

- `PROJ-123 ...`: One or more JIRA ticket IDs (required)
- `--direct`: Skip OpenSpec and create Beads directly from tickets (only when tickets are exceptionally well-defined)

**Prerequisites:**
- JIRA MCP server must be configured and accessible
- For `--direct` mode: Beads (`bd`) must be installed with Dolt server running

---

## Step 1: Fetch and assess tickets

Fetch all referenced tickets via JIRA MCP. For each ticket, extract:

- Ticket ID, summary, and full description
- Acceptance criteria (look for "Acceptance Criteria" heading, "AC:", numbered criteria)
- Priority, status, story points
- Linked tickets (blocks/blocked-by, epic link, subtasks)

### Assess ticket quality

Rate each ticket on readiness for direct spec generation:

| Rating | Criteria | Action |
|--------|----------|--------|
| **High** | 3+ specific, testable acceptance criteria; bounded scope; no major unknowns | Proceed to spec generation |
| **Medium** | Some criteria but vague or incomplete; scope mostly clear | Warn user; suggest enriching or using `/plan-spec` |
| **Low** | No acceptance criteria; scope unclear; mostly a title and stub | Stop; recommend `/plan-spec` instead |

Present the assessment:

```
## Ticket Assessment

### PROJ-123: <summary> — High quality
Acceptance criteria: 4 (all testable)
Scope: bounded (single module)
Unknowns: none identified

### PROJ-456: <summary> — Medium quality
Acceptance criteria: 2 (1 vague: "should be fast")
Scope: mostly clear but integration points undefined
Recommendation: Clarify performance targets, or use /plan-spec

### PROJ-789: <summary> — Low quality
Acceptance criteria: none
Scope: "Improve the dashboard"
Recommendation: Use /plan-spec for interactive refinement
```

**If any ticket is Low quality:** Ask the user whether to proceed with High/Medium tickets only, or switch to `/plan-spec` for the full set. Do NOT generate specs from Low-quality tickets — the risk of building the wrong thing is too high.

**If JIRA MCP is not available:** Report the error and suggest `/plan-spec` instead, which can work without JIRA.

---

## Step 2: Group tickets into a change

Propose a change structure based on ticket relationships:

```
## Proposed change: <change-name>

Tickets included: PROJ-123, PROJ-456 (High quality)
Tickets excluded: PROJ-789 (Low quality — needs /plan-spec)

### Task mapping
1. PROJ-123: <summary>
   1.1 <AC 1 — implementation task>
   1.2 <AC 2 — implementation task>
2. PROJ-456: <summary>
   2.1 <AC 1 — implementation task>
   2.2 <AC 2 — implementation task>
```

**Derive the change name** from the ticket summaries (kebab-case, descriptive). Ask the user to confirm the change name and task mapping before proceeding.

**If tickets span multiple unrelated features**, suggest splitting into separate changes — one change per cohesive unit of work.

---

## Step 3: Read the codebase for context

Before generating artifacts, read the relevant source code:

- Identify modules, files, and functions that the tickets reference or affect
- Verify that APIs, classes, and patterns mentioned in tickets actually exist
- Note any discrepancies between ticket descriptions and actual code
- Check test infrastructure (test framework, existing test patterns, test directory)

This prevents generating specs that describe aspirational architecture instead of reality.

---

## Step 4: Generate OpenSpec artifacts (default path)

If `--direct` was NOT specified, generate minimal but complete OpenSpec artifacts:

### 4a: Create the change

```bash
openspec create <change-name>
```

### 4b: Generate proposal.md

A lightweight proposal — the JIRA tickets already justify the work:

```markdown
# <change-name>

## Summary
<1-2 sentences synthesizing what the tickets accomplish together>

## Motivation
JIRA tickets: PROJ-123, PROJ-456
<Why this work is needed — from ticket descriptions and linked epics>

## Scope
**In scope:** <what the tickets cover>
**Out of scope:** <what's explicitly excluded or deferred>
```

### 4c: Generate specs with acceptance scenarios

For each ticket, create a spec with scenarios derived from JIRA acceptance criteria:

```markdown
# <ticket-summary>

Source: PROJ-123

## Scenarios

### S1: <acceptance criterion 1 as a scenario title>
**Given** <precondition from context>
**When** <action implied by the criterion>
**Then** <expected outcome — verbatim from JIRA criterion>

Accept: <verbatim JIRA acceptance criterion>

### S2: <acceptance criterion 2 as a scenario title>
...
```

**JIRA acceptance criteria are verbatim in `Accept:` fields.** Do not paraphrase or "improve" them.

### 4d: Generate tasks.md

Map acceptance criteria to ordered, dependency-aware tasks:

```markdown
# Tasks

## 1. <Feature area from PROJ-123>
- [ ] 1.1 <implementation task> — PROJ-123 AC 1
- [ ] 1.2 <implementation task> — PROJ-123 AC 2

## 2. <Feature area from PROJ-456>
- [ ] 2.1 <implementation task> — PROJ-456 AC 1
- [ ] 2.2 <implementation task> — PROJ-456 AC 2
```

Order tasks by dependency — foundational work first, integration tasks after their prerequisites.

### 4e: Generate design.md (only when needed)

Only generate `design.md` if:
- Tickets reference architectural decisions that need documentation
- Multiple implementation approaches exist and the choice isn't obvious
- Integration between tickets requires design coordination

Otherwise omit it — the JIRA tickets already made the design decisions.

---

## Step 5: Present results and next steps

```
## OpenSpec artifacts generated

Location: openspec/changes/<change-name>/
- proposal.md — lightweight, JIRA-sourced
- specs/<spec-name>/spec.md — acceptance scenarios from JIRA AC
- tasks.md — N tasks mapped from M tickets
<- design.md — if generated>

### Ticket traceability
PROJ-123 -> specs/<name>/spec.md -> tasks 1.1, 1.2
PROJ-456 -> specs/<name>/spec.md -> tasks 2.1, 2.2

### Next steps
- Review artifacts: openspec/changes/<change-name>/
- Generate beads: /generate-spec-beads <change-name>
- Or refine interactively: /plan-spec <change-name> PROJ-123 PROJ-456
```

---

## Step 5-alt: Direct bead creation (--direct flag)

When `--direct` is specified AND all tickets are High quality:

1. Skip OpenSpec artifact generation entirely
2. Create a Beads epic for the ticket group
3. Create beads directly from ticket acceptance criteria, using the per-feature triad pattern (impl + test + review per task)
4. Wire dependencies based on task ordering
5. Use JIRA ticket numbers as bead title prefixes (e.g., `PROJ-123: 1.1 <task>`)

This path is a shortcut for well-defined, low-risk work. **If any ambiguity surfaces during bead creation, stop and recommend `/plan-spec` instead.**

**Limitation:** `--direct` mode bypasses OpenSpec entirely, so the `/spec-completion-auditor` will have no `tasks.md` to cross-check against. Verification must rely on JIRA ticket acceptance criteria and bead state alone.

Follow the same structural patterns as `/generate-spec-beads`: `--parent` for epic hierarchy, `--deps` for predecessors, `Agent:` field for dispatch routing, `Accept:` field with verbatim JIRA criteria.

---

## Guardrails

- **JIRA acceptance criteria are verbatim.** Do not paraphrase, soften, or "improve" them. They are the authoritative source of truth.
- **Never generate specs from Low-quality tickets.** Recommend `/plan-spec` instead.
- **Always show the mapping before creating artifacts.** The ticket-to-task mapping is a design decision the user must confirm.
- **Preserve ticket traceability.** Every spec, task, and bead must trace back to its source JIRA ticket ID.
- **Read the codebase first.** Verify that ticket descriptions match reality before generating specs.
- **`--direct` is a shortcut, not a bypass.** Quality assessment still runs. Low-quality tickets are still rejected.
- **When in doubt, recommend `/plan-spec`.** This skill is a fast path. If tickets need interpretation, design decisions, or research, the interactive planning conversation is the right tool.

ARGUMENTS: $ARGUMENTS
