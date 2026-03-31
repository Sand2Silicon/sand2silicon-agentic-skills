# Spec Planning Template

A structured starting point for planning a new change with OpenSpec. Fill in the sections relevant to your work, then use this as the prompt for `/opsx:propose` (or `/opsx:explore` first for complex/ambiguous work).

> **Tip:** The `/plan-spec` skill automates context gathering and routes to the right OpenSpec command. Use this template directly when you prefer manual control or want to prepare offline.
>
> **When to explore first:** If you have multiple unknowns, cross-cutting changes, or aren't sure about the approach, start with `/opsx:explore <change-name>` using this context. Explore drives a free-form interactive investigation, then transition to `/opsx:propose` when direction is clear.

---

```
/opsx:propose <change-name>

## What to build
<1-3 sentences describing the feature or change. Be specific about the desired outcome, not the implementation approach.>

### Source references (fill in what applies)
- **JIRA tickets:** <PROJ-123, PROJ-456 — acceptance criteria in these tickets are authoritative>
- **Roadmap epic:** <Epic N from docs/Roadmap-PhaseN.md — for phase context, not requirements>
- **Existing spec:** <openspec/changes/<name>/ — if extending or revising prior work>

## Why now
<What is this blocking? What depends on it? Why is this the next priority?>

## Research needed
<What do you need to investigate before designing? External APIs, libraries, best practices, prior art? Be specific about what you DON'T know yet.>

Example: "Research rate-limiting strategies for the API gateway — compare token bucket vs sliding window. I don't know which fits our traffic pattern."

## Known constraints
<Hard requirements, non-negotiables, performance targets, compatibility requirements.>

Examples:
- Must work with existing auth middleware
- Cannot add more than N new dependencies
- Must handle N concurrent connections
- Must integrate with existing <module>

## Design preferences
<Architectural opinions you already have. Module boundaries, patterns to follow, extensibility requirements.>

Examples:
- Should follow the provider pattern used in existing modules
- Separate module with clear API boundary, not bolted onto existing files
- Must be pluggable so implementations can be swapped at runtime

## Quality requirements
- [ ] All tasks must have concrete acceptance criteria (verifiable pass/fail)
- [ ] Include test-creation tasks for every module (unit + integration)
- [ ] Tests must reference specific spec scenarios they validate
- [ ] Include manual smoke test tasks for end-to-end validation
<Add domain-specific quality gates as needed.>

## Domain context
<Relevant domain knowledge that should inform the design. What does someone new to this codebase need to know?>

> If you've run `/sdd-workflow-init`, your project-specific template already has this filled in.

## Process instructions
This should be a back-and-forth conversation:
1. **Research first** — investigate unknowns before proposing anything. Read the actual codebase, check APIs, verify assumptions.
2. **Come back with questions** — present options, trade-offs, and ask for input on design decisions before generating artifacts.
3. **Challenge your own defaults** — if the "textbook" answer seems too simple, dig deeper. The user will push back if something feels off.
4. **Review your own work** — after generating artifacts, objectively audit for completeness, coherence, circular dependencies, and gaps.
5. **Generate all artifacts** — proposal, design, specs (with acceptance scenarios), tasks (with acceptance criteria), and test tasks.
```

---

## Notes

**Fill in what you know, leave blank what you don't.** The "Research needed" section is the most important — it tells the planning agent what to investigate before designing, which prevents premature decisions.

**The "Process instructions" section is the key to interactive planning.** These instructions tell `/opsx:propose` to research, ask questions, and have a back-and-forth conversation instead of generating artifacts in one shot. Modify only if you want a different interaction style (e.g., "just generate everything, no questions" for small/obvious changes).

**Two paths for complex work:**
- **`/opsx:explore` → `/opsx:propose`**: Use explore for free-form investigation when you have many unknowns. Explore drives the interactive conversation, then propose generates artifacts informed by the exploration.
- **`/opsx:propose` with process instructions**: The process instructions tell propose to research and ask questions as part of artifact generation. Works well when the scope is clear but you want the agent to verify assumptions before committing to a design.

**Quality requirements are non-negotiable defaults.** Every spec should include acceptance criteria and test tasks. Add domain-specific quality gates as needed (e.g., "must handle N requests/sec", "must pass security audit").

**Source references drive automation.** When JIRA tickets are listed, `/plan-spec` can auto-fetch their acceptance criteria. When a roadmap epic is referenced, it can pull the phase context. The more you fill in, the more the tooling can do for you.
