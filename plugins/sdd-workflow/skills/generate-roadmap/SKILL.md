---
name: generate-roadmap
description: Research a project's actual state vs documented state and generate a phased roadmap of epics. Reads all docs, code, and completed-work logs to find gaps, broken assumptions, and missing capabilities — then synthesizes them into high-level milestones for OpenSpec planning.
user-invocable: true
---

# Generate Roadmap

Examine a project's documentation, code, and completed-work logs to produce a phased roadmap of epics — high-level milestones that will later become OpenSpec specs and Beads issues.

**Input**: Optional arguments after the slash command:
- A phase label (e.g., "Phase 2", "MVP") — defaults to "Phase 1"
- A goal statement (e.g., "get real-time predictions running") — if omitted, ask
- A target output path (e.g., `docs/Roadmap-Phase2.md`) — defaults to `docs/Roadmap-Phase1.md`

---

## Steps

### 1. Gather project context (autonomous)

Read ALL of the following without asking the user — this is the research phase:

- `README.md` and `CLAUDE.md` — project goals, architecture, constraints
- All files in `docs/` — plans, analysis, completed-work logs
- All source files in `src/` (or the main source directory) — actual implementation
- `requirements.txt` / `package.json` / equivalent — declared dependencies
- `openspec/specs/` — any existing canonical specs (these represent "done" capabilities)
- `openspec/changes/` — any in-flight changes (these represent "planned" work)

**Do not skip the code.** The documentation may be optimistic or stale. The code is the truth.

### 2. Gap analysis (autonomous — this is the core value)

For each capability the docs claim is complete or working:

1. **Read the actual code** that implements it
2. **Verify the API usage is correct** — are libraries being called with the right interface? (e.g., a model loaded via the wrong class, an API called with wrong parameters)
3. **Check if the output is usable** — does it return structured data or just print/log?
4. **Check if inputs are real** — is it using hardcoded test data or actual external sources?

Produce a mental ledger:
- **Actually working**: code runs, uses correct APIs, produces real output
- **Broken/wrong**: code exists but uses wrong API, produces garbage, or can't run
- **Stub/placeholder**: code exists but with hardcoded inputs or no real logic
- **Missing entirely**: documented as needed but no code exists

### 3. Determine scope (may require user input)

If the user provided a goal statement, use it. Otherwise, use the **AskUserQuestion tool** (open-ended):

> "I've reviewed the project. Here's what I found:
> - [1-2 sentence summary of actual state vs documented state]
> - [biggest gap or broken assumption]
>
> What's the goal for this roadmap phase? What does 'done' look like?"

The user's answer defines the phase boundary — what's in scope vs. out of scope.

### 4. Synthesize epics (autonomous)

Group the gaps into 3-7 epics. Each epic should be:

- **A coherent capability** — not a grab-bag of tasks
- **Dependency-ordered** — earlier epics unblock later ones
- **Sized for one OpenSpec change** — if an epic would need 3+ spec files with unrelated concerns, split it

For each epic, write:
- **Title** — what capability it delivers
- **1-2 sentence description** — what changes and why
- **Key deliverables** — bullet list of concrete outputs (not tasks, but what exists when it's done)

### 5. Generate the roadmap document

Write to the target path (default `docs/Roadmap-Phase1.md`) with this structure:

```markdown
# Phase N Roadmap — [goal statement]

**Goal:** [1-2 sentences from the user's goal or derived from analysis]

---

## Current State

[Honest assessment: what actually works, what's broken, what's missing.
Reference specific files and the nature of the gap.]

---

## Epics

### Epic 1 — [Title]
[Description]
- [Deliverable 1]
- [Deliverable 2]

---

[...repeat for each epic...]

---

## Out of Scope for Phase N
- [Capabilities explicitly deferred to a later phase]
```

### 6. Present for review

After writing, summarize:
- What you found (the biggest surprise or gap)
- The epic structure and ordering rationale
- Any ambiguities or questions you have for the user
- Suggest: "Review this, then we'll `/opsx:propose` each epic in order."

---

## Guidelines

- **Trust code over docs.** If `04_completed.md` says "working pipeline" but the code uses the wrong model API, the pipeline is broken. Say so clearly.
- **Be honest about what's broken.** The roadmap's value is in surfacing reality, not preserving optimism. If something claimed as done is actually wrong, that becomes Epic 1.
- **Keep epics at concept level.** Each epic is 1-3 sentences + deliverables. Implementation details belong in the OpenSpec specs that come later.
- **Order by dependency.** If Epic 3 can't start until Epic 1 is done, say so. The first epic should always be the one that unblocks everything else.
- **Include "Out of Scope".** This prevents scope creep and sets expectations for what Phase N does NOT cover.
- **Don't over-scope a phase.** 3-7 epics is the sweet spot. If you have 10+, you're trying to do too much in one phase. Split into Phase 1a/1b or Phase 1/Phase 2.

## Anti-patterns to avoid

- **Trusting completed-task lists without reading code** — the whole point of this skill is to verify
- **Making epics too granular** — "add a config field" is a task, not an epic
- **Making epics too vague** — "improve the system" is not actionable
- **Skipping the gap analysis** — if you just restate the docs' TODO list, you've added no value
- **Forgetting to ask about scope** — without a goal, the roadmap has no boundary

ARGUMENTS: $ARGUMENTS
