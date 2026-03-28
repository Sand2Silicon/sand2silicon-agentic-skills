---
name: distill-workflow
description: Analyze a past interaction or prompt and extract a reusable template prompt, skill, or agent definition. Use when you had a productive conversation and want to capture the workflow pattern for reuse. Also use when you have an existing prompt that could be improved based on what you learned works.
license: MIT
metadata:
  author: user
  version: "1.0"
user-invocable: true
---

Analyze a conversation or prompt and extract a reusable artifact from it.

**Input**: The argument after `/distill-workflow` can be:
- Nothing (analyze the current conversation)
- A file path to a prompt or template to refine (e.g., `@docs/templates/my-prompt.md`)
- A description of what to extract (e.g., "the spec planning process we just did")

**Steps**

1. **Identify the source material**

   If no input provided, analyze the current conversation. If a file is referenced, read it. If a description is given, locate the relevant conversation segments.

2. **Extract the interaction pattern**

   Analyze the source and identify:

   a. **Information taxonomy** — What categories of information were needed? (e.g., constraints, preferences, domain context, research questions). For each category, note:
      - Was it provided upfront or discovered mid-conversation?
      - Was it provided by the user or discovered by Claude?
      - How much did it influence the outcome?

   b. **Decision points** — Where did the conversation branch or require user input? What questions were asked? Which answers significantly changed the direction?

   c. **Quality gates** — What quality requirements were stated or implied? What was added late that should have been upfront?

   d. **Process phases** — What was the natural sequence? (e.g., research → discuss → design → generate → review → refine)

   e. **What worked** — What about the interaction produced a good outcome? What would be lost if automated?

   f. **What was missing** — What information arrived too late? What assumptions were made that shouldn't have been?

3. **Determine the right artifact type**

   Based on the analysis, recommend one of:

   | Type | When to use | Characteristics |
   |------|------------|-----------------|
   | **Template prompt** | Workflow requires human judgment at multiple points; value is in structuring the initial request | A markdown file the user fills in and pastes. Cheapest to create, easiest to evolve. |
   | **Skill** | Workflow has a repeatable structure with clear phases; some steps can be automated but human input is still needed at key points | A SKILL.md that orchestrates tool calls with user interaction points. |
   | **Agent** | Workflow is mostly autonomous; the valuable parts don't require human judgment; output is well-defined | An agent prompt that runs independently and returns a result. |

   Present the recommendation with reasoning. If the user's input specified a type, use that — but flag if a different type would be better.

4. **Generate the artifact**

   Based on the chosen type:

   **If template prompt:**
   - Write to `docs/templates/<name>.md`
   - Structure: fillable sections with examples and guidance comments
   - Include a "Process instructions" section capturing the interaction pattern
   - Include a "Notes" section explaining when/how to use it and how to evolve it

   **If skill:**
   - Write to project-local `.claude/skills/<name>/SKILL.md`
   - Include frontmatter (name, description, user-invocable: true)
   - look for a /create-skill skill to assist or research the format: https://agentskills.io/specification
   - Structure the skill as phases with clear handoff points
   - Use AskUserQuestion at decision points identified in step 2
   - Automate the parts that don't need human judgment

   **If agent:**
   - Write the agent prompt and store project-local (can be used with the Agent tool)
   - Define clear inputs, outputs, and autonomy boundaries
   - Note what the agent should NOT decide on its own

5. **Present the result**

   Show the user:
   - What was extracted (brief summary of the pattern)
   - What artifact was created and where
   - How to use it
   - What to watch for / evolve over time

**Guidelines**

- **Prefer the lightest artifact that captures the value.** Don't build a skill when a template prompt suffices. Don't build an agent when human judgment is the valuable part.
- **The back-and-forth IS the product** in many cases. If the value of an interaction was the discussion itself, a template that structures that discussion is better than a skill that tries to skip it.
- **Include escape hatches.** Templates should have "modify as needed" notes. Skills should have "ask the user" steps. Agents should have clear boundaries.
- **Name artifacts descriptively.** `spec-planning-prompt.md` not `template-1.md`. `distill-workflow` not `meta-tool`.
- **Capture the WHY, not just the WHAT.** Include comments explaining why each section exists, so the user can make informed decisions about what to keep or change.

ARGUMENTS: $ARGUMENTS
