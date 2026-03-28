---
name: discover
description: Research and evaluate an open-source project for technical due diligence. Produces a two-document discovery report (executive brief + technical analysis) covering project health, architecture, competitive landscape, and investment viability, then guides the user into a focused deep-dive based on their intent. Trigger on phrases like "research [project]", "evaluate [project]", "should I fork / build on / contribute to [project]", "tell me about [project] codebase", "is [project] a good starting point", "discover [project]".
license: MIT
metadata:
  author: Steven Peterson
  version: "1.0"
user_invocable: true
---

Perform technical due diligence on an open-source project and produce a structured discovery report.

**Input**: The argument after `/project-discovery:discover` should be a project name, URL, or description.
If not provided, ask: *"What project are you evaluating? Give a name, URL, or brief description."*

---

## Output Structure

Create a `discovery-<project-slug>/` folder in the **current working directory** (wherever the user invoked the skill from):

```
discovery-<project-slug>/
├── README.md                    # one-paragraph verdict + links to both reports
├── discovery-brief.md           # executive-facing (1–2 pages)
├── discovery-technical.md       # engineer-facing (2–4 pages)
├── diagrams/
│   ├── architecture.mmd         # Mermaid source: component/layer diagram
│   └── ecosystem.mmd            # Mermaid source: project + forks + community + competitors
└── deep-dive/                   # populated only if user requests in Step 4
    └── <goal>-analysis.md
```

Diagrams are embedded as Mermaid code blocks in the reports AND written as standalone `.mmd` files for external rendering.

---

## Step 1 — Reconnaissance (autonomous)

Use WebSearch and WebFetch in parallel to gather data across all dimensions. Use the Agent tool with a research subagent for breadth. Do not ask the user for help finding sources — figure it out.

**Identity & Provenance**
- Primary repository and homepage; confirm whether this is the original project or a fork
- Origin story: who created it, when, why; what the name history (e.g., "fork" in the name) means
- Active competing forks: are any substantively different? more active? better maintained?
- Current maintainer(s): individual, organization, or foundation; governance model
- License (SPDX) and what it permits for modification and redistribution

**Vitality Signals** *(treat absence of data as a risk signal)*
- Commit cadence: weekly/monthly average over the past 12 months
- Release cadence and date of most recent release
- Contributor count total and active (past 12 months)
- Bus factor indicators: what fraction of commits come from 1–3 people?
- Issue and PR response time; PR acceptance rate

**Technology Stack**
- Primary language(s) and rough ratios
- Build system and toolchain
- Key libraries/frameworks for: UI, graphics/rendering, data persistence, and any domain-specific subsystems
- Age of tech choices relative to current alternatives
- Test framework presence; CI/CD configuration

**User Pain Points**
- GitHub issues labeled "enhancement", "UX", "usability", "pain", "wish"
- Reddit, HN, Stack Overflow, and domain-specific forums: what do users complain about?
- Any user surveys, community roadmap discussions, or "what I wish this had" threads

**Competitive Landscape**
- Direct OSS alternatives that are feature-comparable and actively maintained
- Top 2–3 commercial/paid alternatives: pricing tier, licensing model, notable differentiators
- Projects that were "inspired by" or "built on top of" this one — and whether they surpassed it

**Community & Ecosystem**
- Community platforms: Discord, forum, mailing list, Reddit, IRC, Slack, dedicated site
- Third-party plugins, extensions, or integrations
- Documentation site quality: is it current, complete, beginner-friendly?

---

## Step 2 — Generate Reports

### Report 1: `discovery-brief.md` (executive-facing)

```markdown
# [Project Name] — Discovery Brief

> [ONE-PARAGRAPH VERDICT: what this project is, its current health, and the bottom-line recommendation. This is the most-read part of the report — make it count.]

## Project Vitals

| Field | Value |
|-------|-------|
| Repository | |
| Homepage | |
| License | |
| Primary language(s) | |
| First release | |
| Latest release | |
| Commit cadence | |
| Active contributors (12 mo) | |
| Community platforms | |

## Health Scorecard

| Dimension | Signal | Rating | Key Risk |
|-----------|--------|--------|----------|
| Community | [1-line evidence] | 🟢/🟡/🔴 | |
| Code | [1-line evidence] | 🟢/🟡/🔴 | |
| Ecosystem | [1-line evidence] | 🟢/🟡/🔴 | |
| Governance | [1-line evidence] | 🟢/🟡/🔴 | |

Ratings: 🟢 healthy  🟡 caution  🔴 risk

## Top User Pain Points

1. [Most-cited complaint, with source evidence]
2. ...
(list up to 8; note which are chronic vs. recently addressed)

## Competitive Position

[2–3 sentences: where this project sits in the landscape — dominant, niche, declining, underserved market?]

| Feature Area | [This Project] | [Competitor A] | [Competitor B] |
|--------------|:--------------:|:--------------:|:--------------:|
| [Key axis 1] | ✅/⚠️/❌ | | |
| [Key axis 2] | | | |
| [Key axis 3] | | | |
| [Key axis 4] | | | |
| Active development | | | |
| Community size | | | |

## Architecture Overview

[Brief prose: what kind of system is this — monolith, plugin-based, library+app, etc.]

```mermaid
[Component/layer diagram showing major subsystems and their relationships]
```
*(also saved to `diagrams/architecture.mmd`)*

## Disposition Recommendation

**Verdict:** [Contribute | Extend | Fork | Modernize | Replace | Avoid]
**Confidence:** [High | Medium | Low]

[2–3 sentences of reasoning. State the single most important factor driving the verdict, and what evidence would change it.]

**Key Risks:**
- ...
- ...
```

---

### Report 2: `discovery-technical.md` (engineer-facing)

```markdown
# [Project Name] — Technical Analysis

## Stack Inventory

| Component | Technology | Age / Version | Health | Modern Alternative |
|-----------|-----------|---------------|--------|-------------------|
| UI | | | 🟢/🟡/🔴 | |
| Graphics/Rendering | | | | |
| Build system | | | | |
| Data/persistence | | | | |
| Test framework | | | | |
| CI/CD | | | | |

## Architecture

[More detailed component diagram — show internal module boundaries, not just subsystems]

```mermaid
[Detailed component diagram]
```
*(also saved to `diagrams/architecture.mmd` — replaces the overview version)*

### Key Modules

For each of the 2–3 most architecturally significant modules:

**[Module Name]**
- *Purpose:* what it owns
- *Patterns:* design patterns in use; how it's structured internally
- *Coupling:* what it depends on; what depends on it
- *Notable:* anything surprising, clever, or concerning

## Extension Points

Where can a developer hook in or build on top of the project without forking it?
- Plugin or extension systems
- Well-defined internal APIs or interfaces
- Configuration hooks or scripting support
- Areas of the codebase with low coupling (easy to replace)
- Areas with high coupling (risky to touch)

## Code Quality Signals

- **Organization:** is the codebase logically laid out? is the directory structure discoverable?
- **Documentation:** inline comments, API docs, architecture docs — presence and quality
- **Tests:** presence, framework, rough coverage estimate, test style (unit/integration/e2e)
- **Technical debt indicators:** known hacks, deprecated patterns, TODO density, dependency age
- **Build health:** can it be built from a clean clone? known gotchas?

## Modernization Effort Estimate

| Area | Effort | Notes |
|------|--------|-------|
| UI framework | Low / Medium / High / Very High | |
| Build system | | |
| Core architecture | | |
| Dependency updates | | |
| Test coverage | | |
| Overall | | |

Note any prior modernization attempts — what was tried, what stalled, and why.

## Competitive Feature Matrix

[Detailed feature table: rows = specific capabilities, columns = this project + top 2–3 alternatives.
Use ✅ (full), ⚠️ (partial/limited), ❌ (absent) with brief notes where useful.]

## Ecosystem Map

```mermaid
[Graph showing: original project lineage → active forks → community platforms → notable integrations → top competitors. Makes the "landscape" visible at a glance.]
```
*(also saved to `diagrams/ecosystem.mmd`)*

---

## Step 3 — Present Summary and Elicit Goals

After writing the reports, output a concise terminal summary:
- Project name, one-line disposition verdict and confidence
- Path to output folder
- Any significant finding that should be flagged before the user reads the report

Then ask using the AskUserQuestion tool:

> **What's your intent with this project?**
>
> A. Fix or contribute a specific bug or feature
> B. Extend it with new capabilities
> C. Modernize or overhaul the codebase
> D. Fork it for a new product or direction
> E. Evaluate it for adoption as a dependency or platform
> F. Competitive intelligence or market research
> G. Assess a business opportunity
> H. Something else — describe it
>
> *(Or type "done" to stop here.)*

---

## Step 4 — Focused Deep-Dive (if requested)

Based on the user's goal, ask one targeted follow-up to scope the analysis (e.g., for **B**: "What capability do you want to add?"; for **C**: "What's driving the modernization — specific pain point, new capability, or maintenance burden?"). Then ask:

> **How deep?**
> - **Brief** (1–4 pages) — focused assessment with direct recommendations
> - **Extended** (up to 10 pages) — comprehensive analysis with supporting detail

Generate `deep-dive/<goal>-analysis.md` according to the goal:

| Goal | Deep-Dive Focus |
|------|----------------|
| **A — Bug/Feature** | Relevant code paths, where to make the change, test approach, PR norms and acceptance patterns |
| **B — Extend** | Extension points, API stability, integration patterns, step-by-step effort estimate |
| **C — Modernize** | Phased modernization plan: what to do in what order, risk at each phase, prior attempts and why they stalled, recommended approach given community posture |
| **D — Fork** | Fork decision rationale, what to diverge on vs. inherit, divergence maintenance burden over time, license strategy, naming/positioning |
| **E — Adopt as dependency** | API surface stability, embedding complexity, upgrade path, license compatibility with your stack |
| **F — Competitive intel** | Market segmentation, user acquisition dynamics, moat analysis, trajectory (growing/stable/declining) |
| **G — Business opportunity** | Addressable market, monetization paths, competitive moat, build-vs-buy-vs-fork economics |

---

## Guidelines

- **Synthesize, don't transcribe.** The report should contain judgments ("this project has a high bus-factor risk") not just facts ("the project has 3 contributors"). The health scorecard and disposition recommendation ARE the deliverable.
- **Absence of data is data.** If you can't find community size, release notes, or contributor stats, say so and rate it as a risk signal. Projects that are hard to research are usually not well-maintained.
- **Surface surprises prominently.** If the "original" project is dead and this fork is the de-facto successor, or if a better-maintained competitor exists, or if the license doesn't permit what the user likely wants — put it in the one-paragraph verdict.
- **Diagrams over prose for structure.** Component diagrams, comparison tables, and scorecards communicate faster than paragraphs. Use prose to explain the diagram, not to repeat it.
- **The ecosystem map is not optional.** It often reveals the most actionable insight — that a fork or competitor has already solved the problem, or that the community has migrated elsewhere.
- **For modernization assessment specifically:** look for evidence of past attempts (long-lived branches, abandoned PRs, blog posts about rewrites). They reveal what's hard and what the community will resist.
