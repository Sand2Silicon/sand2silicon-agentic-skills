# SDD-Workflow: Spec-Driven Development for AI Agents

A Claude Code plugin that orchestrates the full lifecycle of spec-driven development — from requirements gathering through implementation, review, and verification — using AI agents coordinated by a dependency-aware task graph.

## Table of Contents

- [The Core Idea](#the-core-idea)
- [AI-Driven / Spec-Driven-Development workflow](#ai-driven--spec-driven-development-workflow)
- [Workflow Stages](#workflow-stages)
  - [Stage 0: Project Setup (`/sdd-workflow-init`)](#stage-0-project-setup-sdd-workflow-init)
  - [Stage 1: Planning](#stage-1-planning)
  - [Stage 2: Bead Generation (`/generate-spec-beads`)](#stage-2-bead-generation-generate-spec-beads)
  - [Stage 3: Implementation (`/implement-beads`)](#stage-3-implementation-implement-beads)
  - [Stage 4: Verification (`/spec-completion-auditor`)](#stage-4-verification-spec-completion-auditor)
- [Quick Reference](#quick-reference)
  - [Installation](#installation)
  - [Skill Commands](#skill-commands)
  - [Typical Session](#typical-session)
- [Template Architecture](#template-architecture)
- [Context Source Flows](#context-source-flows)
- [Key Tools](#key-tools)
  - [Why Beads?](#why-beads)
- [Task State Convention](#task-state-convention)
- [Addendum: Evaluation & Improvement Opportunities](#addendum-evaluation--improvement-opportunities)


## The Core Idea

Instead of giving an AI agent a vague prompt and hoping for the best, this workflow:

1. **Plans rigorously** — requirements, design decisions, acceptance criteria
2. **Decomposes into a dependency graph** — each unit of work is a tracked "bead" with clear inputs, outputs, and dependencies
3. **Executes with parallel agents** — an orchestrator dispatches specialized agents (implementation, test-authoring, review) that work concurrently
4. **Gates quality at every stage** — per-feature review agents verify work before downstream tasks begin

The result: auditable, parallelized, spec-compliant implementation with full traceability from requirements to code.

## AI-Driven / Spec-Driven-Development workflow:

`JIRA → OpenSpec plan → /generate-spec-beads → /implement-beads → Review / Pull Request`
- JIRA is the system of record for epics and stories.
- OpenSpec captures what and why — the planning artifact.
- Beads captures how, in what order, with what validation — the execution artifact.
- Claude Code with subagents executes implementation in parallel where possible.
- Claude Skills help glue the phases together with automated, predictable, repeatable processes.


_Graph: SDD-Workflow Plugin - the big picture_
```mermaid
flowchart TD
    classDef context fill:#b5e6e2,stroke:#5ecfc5,color:#1a1a2e
    classDef setup fill:#a5e4cc,stroke:#32b898,color:#1a1a2e
    classDef planning fill:#6aa8f0,stroke:#4a8bd4,color:#fff
    classDef artifact fill:#9cbef5,stroke:#6aa8f0,color:#1a1a2e
    classDef execution fill:#7a54d9,stroke:#5e3dbf,color:#fff
    classDef support fill:#efbdca,stroke:#d96585,color:#1a1a2e
    classDef success fill:#36bca0,stroke:#289478,color:#fff

    subgraph CTX [" Context Sources "]
        JIRA["JIRA Tickets<br/><i>ultimate authority when active</i>"]:::context
        RM["Roadmap.md<br/><i>phases/batching</i>"]:::context
    end

    subgraph SET [" Setup · once per project "]
        INIT["/sdd-workflow-init<br/>Detect project context"]:::setup
        PTPL["Project Template<br/>.claude/sdd-workflow/<br/>spec-planning-template.md"]:::setup
    end

    subgraph PLN [" Planning Phase · every change "]
        PS["/plan-spec<br/>Stepwise artifact creation<br/>with per-artifact review"]:::planning
        SFT["/spec-from-tickets<br/>JIRA fast path"]:::planning
        RSA["/review-spec-artifact<br/>Two-agent quality review"]:::planning
        OS["OpenSpec Artifacts<br/>proposal + design + specs + tasks"]:::artifact
    end

    subgraph EXE [" Execution Phase · every change "]
        GSB["/generate-spec-beads<br/>Create dependency graph"]:::execution
        IB["/implement-beads<br/>Orchestrate parallel agents"]:::execution
        SCA["/spec-completion-auditor<br/>Verify completeness"]:::execution
    end

    subgraph SUP [" Support "]
        GR["/generate-roadmap<br/>Gap analysis + epic synthesis"]:::support
        DW["/distill-workflow<br/>Extract reusable patterns"]:::support
    end

    SYNC["sync-openspec-tasks.py<br/>Auto-sync bead state to tasks.md"]:::support

    INIT --> PTPL
    JIRA -->|"tickets"| PS
    JIRA -->|"tickets"| SFT
    RM -->|"phases"| PS
    PTPL -->|"project context"| PS
    PS -->|"artifacts + review"| RSA
    RSA --> OS
    SFT -->|"well-defined tickets"| OS
    SFT -->|"--direct"| GSB
    OS --> GSB
    GSB -->|"wired bead graph"| IB
    IB -->|"all beads closed"| SCA
    SCA -->|"gaps?"| IB
    SCA -->|"all verified"| ARCHIVE["Archive Change"]:::success

    GR -->|"feeds into"| PS
    IB -.->|"triggers on bd close"| SYNC
    SYNC -.->|"updates"| OS
```

> **Color key:** <span style="color:#6aa8f0">Blue</span> = daily planning | <span style="color:#7a54d9">Purple</span> = daily execution | <span style="color:#36bca0">Green</span> = one-time setup / success | <span style="color:#d96585">Pink</span> = support tools | <span style="color:#5ecfc5">Teal</span> = context sources

## Workflow Stages

### Stage 0: Project Setup (`/sdd-workflow-init`)

Run once per project. Scans the codebase — README, CLAUDE.md, dependency files, test infrastructure, CI config — and creates a **project-specific planning template** at `.claude/sdd-workflow/spec-planning-template.md`. This template pre-populates domain context, toolchain commands, quality requirements, and architectural patterns so every planning session starts with accurate project context.

### Stage 1: Planning

Three paths into planning, depending on how well-defined the work is:

| Path | Skill | When to use |
|------|-------|-------------|
| **Interactive** | `/plan-spec <change-name> [PROJ-123 ...]` | Default. Gathers context, fetches JIRA tickets, researches the codebase, then creates OpenSpec artifacts **stepwise** with review checkpoints after each artifact, followed by a mandatory two-agent final review. |
| **Fast path** | `/spec-from-tickets PROJ-123 PROJ-456` | JIRA tickets are well-defined with clear acceptance criteria. Assesses ticket quality, generates minimal OpenSpec artifacts (or `--direct` to beads). |
| **Standalone review** | `/review-spec-artifact <change-name>` | After any artifact edit. Runs two independent reviewer sub-agents (accuracy + completeness) against existing artifacts. |

All paths produce **OpenSpec artifacts** (proposal, design, specs with acceptance scenarios, ordered tasks) that feed into bead generation.

Initial input will come from one-or-more Jira tickets, a pre-planning roadmap document that describes phases/epics, or user-written description.

_Graph: Planning Phase:_
```mermaid
flowchart LR
    classDef planning fill:#6aa8f0,stroke:#4a8bd4,color:#fff
    classDef context fill:#b5e6e2,stroke:#5ecfc5,color:#1a1a2e
    classDef dialog fill:#7a54d9,stroke:#5e3dbf,color:#fff
    classDef review fill:#efbdca,stroke:#d96585,color:#1a1a2e
    classDef success fill:#36bca0,stroke:#289478,color:#fff

    PS["/plan-spec"]:::planning -->|"asks"| Q1["What to build?<br/>(tickets, roadmap, description)"]:::planning
    Q1 -->|"JIRA tickets"| FETCH["Fetch via JIRA MCP<br/>extract acceptance criteria"]:::context
    Q1 -->|"roadmap epic"| READ["Read roadmap<br/>extract phase context"]:::context
    Q1 -->|"free description"| MANUAL["User describes work"]:::context
    FETCH --> DIALOG["Back-and-forth<br/>conversation"]:::dialog
    READ --> DIALOG
    MANUAL --> DIALOG
    DIALOG --> STEPWISE["Stepwise artifact creation<br/>proposal → specs → design → tasks<br/>review checklist after each"]:::planning
    STEPWISE --> REVIEW["Two-agent final review<br/>spec-accuracy-reviewer<br/>spec-completeness-reviewer"]:::review
    REVIEW --> ARTIFACTS["Reviewed OpenSpec artifacts"]:::success
```

**The back-and-forth conversation IS the product.** The interactive planning dialog catches misunderstandings that would otherwise become expensive bugs during implementation. `/plan-spec` structures this conversation, not replaces it. This is KEY to front-loading human-in-the-loop involvement, to remove interaction during the implementation phase.

**Two-agent final review catches what conversations miss.** After artifacts are created, two independent reviewer sub-agents examine them through different lenses — one for factual accuracy (are names, APIs, targets real?), one for completeness and coherence (is anything missing, misaligned, or contradictory?). This catches the class of errors (wrong enum values, nonexistent CMake targets, missing task coverage) that conversational planning routinely misses.

### Stage 2: Bead Generation (`/generate-spec-beads`)

Converts the planned tasks into a **dependency-wired Beads graph** — the execution plan.

_Graph: Beads execution graph (3 features, 2 waves):_
```mermaid
%%{init: {"flowchart": {"subGraphTitleMargin": {"top": 8, "bottom": 20}}}}%%
flowchart TD
    classDef impl fill:#6aa8f0,stroke:#4a8bd4,color:#fff
    classDef testauth fill:#b5e6e2,stroke:#5ecfc5,color:#1a1a2e
    classDef review fill:#efbdca,stroke:#d96585,color:#1a1a2e
    classDef gap fill:#f5e4b5,stroke:#c49028,color:#1a1a2e
    classDef join fill:#a5e4cc,stroke:#32b898,color:#1a1a2e
    classDef gate fill:#36bca0,stroke:#289478,color:#fff

    subgraph W1["Wave 1 — two features dispatched in parallel"]
        I1["1.1 cache layer<br/>impl"]:::impl
        TS1["1.1 cache layer<br/>test-authoring"]:::testauth
        I2["1.2 API module<br/>impl"]:::impl
        TS2["1.2 API module<br/>test-authoring"]:::testauth
    end

    I1 & TS1 --> R1
    I2 & TS2 --> R2

    subgraph W1R["Wave 1 Reviews — in parallel once Wave 1 closes"]
        R1["1.1 review<br/>code + feature tests"]:::review
        R2["1.2 review<br/>code + feature tests"]:::review
    end

    R1 -.->|"gap found"| G1["gap bead<br/>routed back to impl or test-authoring agent"]:::gap
    G1 -.->|"gap resolved — re-verify"| R1

    R1 & R2 --> W2U(["Wave 1 reviews passed<br/>Wave 2 unblocked"]):::join

    subgraph W2["Wave 2 — unblocked after Wave 1 reviews pass"]
        I3["2.1 integration<br/>impl"]:::impl
        TS3["2.1 integration<br/>test-authoring"]:::testauth
    end

    W2U --> I3 & TS3

    I3 & TS3 --> R3

    subgraph W2R["Wave 2 Review"]
        R3["2.1 review<br/>code + feature tests"]:::review
    end

    R3 -.->|"gap found"| G3["gap bead<br/>routed back to impl or test-authoring agent"]:::gap
    G3 -.->|"gap resolved — re-verify"| R3

    R3 & W2U --> ALLPASS(["all per-feature reviews passed"]):::join

    ALLPASS --> BG["Build Gate<br/>full test suite + coverage + lint + type check"]:::gate
```

**Key structural pattern — the per-feature triad:**
- **Impl bead** + **Test-authoring bead** are independent (no dependency between them)
- **Review bead** depends on both completing; the review agent runs the feature's authored tests against the implementation and verifies acceptance criteria
- Downstream work depends on the **review bead**, not the impl bead directly

This structure enables maximum parallelism while ensuring nothing proceeds without review.

### Stage 3: Implementation (`/implement-beads`)

The orchestrator agent reads the bead graph and executes it in parallel waves:

```mermaid
sequenceDiagram
    box rgb(88, 130, 200) Orchestration
        participant O as Orchestrator
    end
    box rgb(60, 115, 185) Implementation
        participant IA as Impl Agents
    end
    box rgb(55, 148, 138) Test-Authoring
        participant TA as Test-Authoring Agents
    end
    box rgb(180, 90, 118) Review
        participant RA as Review Agents
    end

    O->>O: bd ready (find unblocked beads)
    O->>O: Group into Wave 1

    par Wave 1 impl and test-authoring run concurrently
        O->>IA: implement bead A
        O->>TA: author tests for bead A (from spec, not impl)
        O->>IA: implement bead B
        O->>TA: author tests for bead B (from spec, not impl)
    end

    IA-->>O: bead A impl closed
    TA-->>O: bead A test-authoring closed
    IA-->>O: bead B impl closed
    TA-->>O: bead B test-authoring closed

    O->>O: bd ready (reviews now unblocked)

    par Wave 1 reviews run concurrently
        O->>RA: review bead A (code review + run feature tests, file gaps)
        O->>RA: review bead B (code review + run feature tests, file gaps)
    end

    alt When review agent finds gaps
        RA-->>O: gap beads filed
        O->>IA: fix gap bead
        IA-->>O: gap closed
        O->>RA: re-verify
    end

    RA-->>O: all reviews passed

    O->>O: bd ready (Wave 2 now unblocked)
    Note over O,RA: Repeat until all waves complete

    O->>O: Build/smoke gate (final integration check)
    O->>O: Pre-commit verification
```

**Three agent roles:**

| Role | What it does | Key constraint |
|------|-------------|----------------|
| **implementation-agent** | Writes production code for one bead | Follows design decisions; flags deviations |
| **test-writer-agent** | Authors tests from spec/acceptance criteria | Never reads implementation code; tests define the contract |
| **review-agent** | Runs the feature's authored tests against the implementation; verifies all acceptance scenarios are satisfied; reviews code against spec and design decisions | Files gap beads for issues; never fixes them directly |

### Stage 4: Verification (`/spec-completion-auditor`)

After all beads are closed, the auditor cross-checks:
- Every closed bead has a corresponding completed spec task
- Every completed spec task has a closed bead backing it
- The actual source code implements what the bead claims

Produces a structured report with auto-synced tasks, gaps, and archive readiness.

## Quick Reference

### Installation

```bash
# In Claude Code
/plugin marketplace add SPetersonNICE/stevens-agentic-skills
/plugin install sdd-workflow --scope project
```

### Skill Commands

| Skill | Invocation | When to use |
|-------|-----------|-------------|
| `sdd-workflow-init` | `/sdd-workflow-init` | Once per project; creates project-specific planning template |
| `plan-spec` | `/plan-spec <change-name> [tickets...] [--epic N]` | Starting new work; stepwise artifact creation with review checkpoints |
| `review-spec-artifact` | `/review-spec-artifact <change-name>` | After any artifact edit; runs two independent reviewer sub-agents |
| `spec-from-tickets` | `/spec-from-tickets PROJ-123 [...]  [--direct]` | JIRA tickets are well-defined; fast path to specs or beads |
| `generate-spec-beads` | `/generate-spec-beads <change-name>` | After planning; creates the bead dependency graph |
| `implement-beads` | `/implement-beads <change-name or epic-id>` | After beads exist; drives parallel implementation |
| `spec-completion-auditor` | Invoked automatically at end of `/implement-beads`, or manually | After implementation; verifies completeness |
| `generate-roadmap` | `/generate-roadmap` | Before planning; analyzes project state and generates phased epics |
| `distill-workflow` | `/distill-workflow` | After a productive session; extracts reusable patterns |

### Typical Session

```bash
# 0. One-time project setup
/sdd-workflow-init

# 1. Plan interactively (or /spec-from-tickets for well-defined JIRA tickets)
/plan-spec add-auth-middleware PROJ-123 PROJ-456

... Have planning conversation, answer tightly defined questions from the AI ...

# 2. Generate beads from the completed OpenSpec change
/generate-spec-beads add-auth-middleware

# 3. Implement (will ask: worktree or current branch?)
/implement-beads add-auth-middleware

# 4. If auditor reports all clear, archive
/openspec-archive-change add-auth-middleware
```

## Template Architecture

The planning template follows a three-tier pattern:

```
Base template (in plugin)
  templates/spec-planning-template.md
  Generic structure, reusable process instructions
      │
      ▼
Project template (per project, generated by /sdd-workflow-init)
  .claude/sdd-workflow/spec-planning-template.md
  Pre-filled domain context, toolchain, conventions
      │
      ▼
Per-change copy (optional, via new-plan.sh)
  <change-name>-plan.md
  Filled in for a specific body of work
```

- `/plan-spec` reads the project template automatically (falls back to base)
- `scripts/new-plan.sh <change-name>` copies the template for offline editing for a new feature/task, (optional step).
- Edit the project template freely — it's yours to customize

## Context Source Flows

The workflow adapts based on which context sources are available:

```mermaid
flowchart TD
    classDef decision fill:#6aa8f0,stroke:#4a8bd4,color:#fff
    classDef full fill:#7a54d9,stroke:#5e3dbf,color:#fff
    classDef road fill:#b5e6e2,stroke:#5ecfc5,color:#1a1a2e
    classDef spec fill:#9cbef5,stroke:#6aa8f0,color:#1a1a2e
    classDef lean fill:#a5e4cc,stroke:#32b898,color:#1a1a2e
    classDef exec fill:#7a54d9,stroke:#5e3dbf,color:#fff

    START{What context<br/>sources exist?}:::decision

    START -->|"JIRA + OpenSpec"| FULL["Full Flow<br/>JIRA = requirements authority<br/>OpenSpec = design + task detail<br/>Beads = execution tracking"]:::full
    START -->|"Roadmap + OpenSpec<br/>(no JIRA)"| ROAD["Roadmap Flow<br/>Roadmap = phase grouping<br/>OpenSpec = full requirements + design<br/>Beads = execution tracking"]:::road
    START -->|"OpenSpec only"| SPEC["Spec-Only Flow<br/>OpenSpec = everything<br/>Beads = execution tracking"]:::spec
    START -->|"Beads only"| LEAN["Lean Flow<br/>Bead descriptions = work context<br/>No spec cross-referencing"]:::lean

    FULL -->|"Ticket prefix on beads/commits"| EXEC["generate-spec-beads<br/>then implement-beads"]:::exec
    ROAD -->|"Epic prefix on beads/commits"| EXEC
    SPEC -->|"Change name prefix"| EXEC
    LEAN -->|"No prefix"| EXEC
```

**JIRA is always the ultimate authority when active.** If a spec and JIRA acceptance criteria conflict, JIRA wins. OpenSpec expands on JIRA with design detail and task decomposition. A roadmap, when present alongside JIRA, is just an organizational bridge for batching tickets into planning phases — track to JIRA ticket numbers, not roadmap phases.

## Key Tools

### Why Beads?

Most AI agent workflows pass results between agents as free-form prose — a review agent's findings become a paragraph in the next agent's prompt, which that agent must interpret, prioritize, and act on without any guarantee of completeness. This works for simple tasks but breaks down quickly: findings get condensed, ambiguous, or lost; there's no record of what was acted on versus silently deferred; and the orchestrator must hold state between waves to reason about what's still outstanding.

Beads replaces descriptive context passing with a **structured, dependency-aware issue graph**. Every unit of work — implementation, test-authoring, review, gap resolution — is a first-class record with explicit state (`open`, `in_progress`, `closed`), typed dependency edges, and a persistent audit trail. Three concrete implications:

**Enforced quality gates.** The per-feature triad (impl + test-authoring → review) isn't a suggested sequence — it's wired as hard edges in the dependency graph. A review bead cannot even be claimed until both the impl and test-authoring beads are closed. Features that depend on a review bead can't be dispatched until that review closes. The orchestrator doesn't need to track or remember this ordering; the graph enforces it structurally. The same applies to the final build gate: it cannot unblock until every preceding bead is closed.

**Structured feedback loops.** When a review agent identifies a gap — a missing acceptance criterion, a test that fails against the implementation, a design deviation — it files a new bead with a precise title, explicit `Accept:` criteria, and an `Agent:` routing field directing it to the right agent type. That gap bead becomes a blocking prerequisite on the review bead itself: the review stays open, the orchestrator dispatches the gap in the next wave, and the review re-verifies before closing. Findings aren't communicated as suggestions in a summary paragraph; they're tracked work items with definitions of done that must be verifiably resolved.

**Parallelism without coordination overhead.** Because dependencies are encoded in the graph rather than reasoned about per-prompt, the orchestrator calls `bd ready` after any wave and gets a precise, authoritative list of what's currently unblocked. No per-agent state to reconstruct, no risk of dispatching work that's still blocked, and reliable resume behavior if a session ends mid-implementation — the graph state persists independently of the orchestrator's context.

| Tool | Purpose |
|------|---------|
| **Beads** (`bd` CLI) | Distributed, graph-based issue tracker backed by embedded Dolt database. Tracks every unit of work with typed dependencies, explicit state transitions, and full audit history. |
| **OpenSpec** (`openspec` CLI) | Spec-driven planning tool. Produces proposal, design, specs, and tasks artifacts. |
| **JIRA MCP** | When configured, provides access to JIRA tickets for requirements and acceptance criteria. |
| **sync-openspec-tasks.py** | Runs automatically on `bd close` via PostToolUse hook. Marks completed spec tasks `[x]`. If there’s a delta between closed beads and closed tasks, validate work fulfills acceptance criteria and nothing was missed. |
| **new-plan.sh** | Copies the planning template for a new change. Usage: `scripts/new-plan.sh <change-name>` |

## Task State Convention

Tasks in OpenSpec `tasks.md` use three states:

| Marker | Meaning | Set by |
|--------|---------|--------|
| `[ ]` | Open — not yet started | Default |
| `[~]` | In progress — beads created, work underway | `generate-spec-beads` or `implement-beads` |
| `[x]` | Complete — bead closed and verified | `sync-openspec-tasks.py` |

---

## Addendum: Evaluation & Improvement Opportunities

### What This Workflow Does Well

**Spec-first decomposition.** The requirement that every bead traces back to a spec scenario with acceptance criteria is the single most impactful practice. Research consistently shows that AI agents produce dramatically better code when given precise, testable requirements rather than vague descriptions. This workflow enforces that discipline structurally.

**Separation of concerns via agent roles.** The impl/test/review triad with hard isolation (test agents cannot read implementation; review agents cannot fix issues) mirrors established software engineering practices:
- **Test-driven development**: Tests written from specs, not from implementation, catch specification bugs rather than just validating what was written
- **Independent code review**: Reviewers who didn't write the code catch different classes of bugs than self-review

**Dependency-graph-driven parallelism.** Using Beads as a DAG scheduler rather than a flat task list means the orchestrator can automatically identify parallelizable work. This is significantly more efficient than sequential execution — a body of work with 20 beads might complete in 4-5 waves rather than 20 sequential steps.

**Quality gates at every level.** Per-feature review gates (not just a final review) catch issues before they propagate to downstream work. The cost of fixing a bug discovered in Wave 1 is far lower than discovering it after Wave 4 has built on top of it.

**Auditable traceability.** The chain from JIRA ticket → OpenSpec spec → Beads issue → code change → review → verification is fully traceable. Every decision and its rationale is recorded in an artifact.

**Automated planning entry points.** The `/plan-spec` and `/spec-from-tickets` skills automate context gathering (JIRA ticket fetching, roadmap reading, project detection) while preserving the interactive conversation that makes planning valuable. The `/sdd-workflow-init` step ensures every planning session starts with accurate project context rather than generic defaults.

### Where It Falls Short / Improvement Opportunities

#### 1. No Feedback Loop From Implementation to Planning

When implementation reveals that a spec was wrong or incomplete (design assumption didn't hold, API doesn't work as expected), the current workflow handles this at the bead level (review agent files gap beads). But the spec artifacts themselves don't get updated — creating drift between specs and reality.

**Improvement:** When a review agent files a gap bead that contradicts a design decision, the orchestrator should flag it for spec update (not just implementation fix). A lightweight `/update-spec` flow could patch the OpenSpec artifacts so they remain accurate for future reference.

#### 2. Session Boundary Problem

The orchestrator loses context between Claude sessions. A large body of work (30+ beads across 5+ waves) may not complete in a single session. The workflow handles resume (check `bd list --status=in_progress`), but the orchestrator loses its wave plan, detected project context, and JIRA cache.

**Improvement:** Persist session state (detected toolchain, JIRA cache, wave plan) to a `.beads/session.json` or similar file that the orchestrator reads on resume. This is partially handled by Beads itself (bead state persists), but the orchestration metadata doesn't.

#### 3. No Metrics or Learning

The workflow produces a lot of structured data (beads opened/closed, gaps filed, review iterations) but doesn't aggregate it. Over time, patterns emerge: certain types of specs produce more gaps, certain agent roles need more iterations, certain phases are bottlenecks.

**Improvement:** A `/workflow-metrics` skill that analyzes closed epics and produces insights: average gaps per feature, review iteration counts, time-to-close distributions, common gap categories. This would inform planning quality improvement over time.

#### 4. No Human-in-the-Loop Wave Checkpoints

Some teams require human approval before dispatching the next wave — a lightweight "are we still on track?" check. The current workflow runs autonomously once started, which is efficient but can mean many waves of work proceed before the user notices a systemic issue (e.g., a misunderstood design decision affecting every feature).

**Improvement:** An optional `--confirm-waves` flag on `/implement-beads` that pauses after each wave for user approval before dispatching the next. Default to autonomous for experienced users, confirmations for high-risk changes.

#### 5. No Cost/Token Budget Controls

Long orchestration sessions with many parallel agents can consume significant resources. There's no mechanism to set a budget, track cumulative cost, or pause when spending exceeds expectations.

**Improvement:** Track cumulative token usage across subagent dispatches. Surface running totals in wave completion summaries. Support an optional `--budget` flag that pauses when the estimate is exceeded.

### Comparison to Emerging Practices

| Practice | This Workflow | Industry Trend |
|----------|--------------|----------------|
| Spec-first AI development | Strong (enforced structurally) | Increasingly recognized as essential; most teams still prompt ad-hoc |
| Dependency-graph task tracking | Strong (Beads DAG) | Most teams use flat task lists; graph-based is more sophisticated |
| TDD with AI agents | Strong (test-authoring agents work from specs independently; review agents execute the suite) | Growing adoption; many teams still write tests after implementation |
| Multi-agent orchestration | Strong (impl/test/review separation) | Emerging pattern; most teams use single-agent flows |
| Quality gates | Strong (per-feature + final) | Best practice but rarely automated this granularly |
| Source verification at audit | Strong (reads code, not just bead status) | Beyond most teams — typically trust issue closure |
| Anti-pattern documentation | Strong (hard-won operational knowledge) | Rarely documented; usually tribal knowledge |
| Planning automation | Strong (`/plan-spec` + `/spec-from-tickets` + `/sdd-workflow-init`) | Teams moving toward automated requirements extraction; this plugin is ahead |
| JIRA integration | Strong (MCP fetch, quality triage, ticket-to-spec-to-bead traceability) | Deep integration becoming standard; bi-directional sync expected |
| Human-in-the-loop checkpoints | Absent (fully autonomous once started) | Some teams gate each wave; optional is ideal |
| Cost/token tracking | Absent | Emerging concern; few tooling solutions yet |
| Cross-session persistence | Weak (Beads state only) | Emerging challenge; few good solutions exist yet |
| Feedback to planning | Weak (gap beads but no spec updates) | Recognized gap industry-wide |

### Bottom Line

This workflow is ahead of the curve on both planning discipline and execution rigor. The planning phase — interactive conversation with automated context gathering, JIRA quality triage, and project-specific templates — ensures AI agents start with precise, testable requirements. The execution phase — spec-tracing, parallel agents, review gates, dependency graphs, and source-level verification — ensures the work is done correctly.

The remaining gaps are at the boundaries: the exit from implementation doesn't feed back into planning, cross-session orchestration state is lost, and there are no cost controls or optional human checkpoints. These represent the next wave of improvement opportunities.
