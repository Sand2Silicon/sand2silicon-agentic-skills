# CLAUDE.md

## What This Is

A Claude Code plugin marketplace repo.

## Structure

```
.claude-plugin/marketplace.json  # registry of all plugins in this repo
plugins/<plugin-name>/
├── plugin.json          # metadata (name, version, description, keywords, author)
├── skills/SKILL.md      # step-by-step instructions Claude follows
└── scripts/             # optional supporting scripts referenced by the skill
```

## SKILL.md Format

Each skill starts with YAML frontmatter:
```yaml
---
name: skill-name
description: when/why Claude triggers this (be specific and comprehensive)
tools: Read, Edit, Write, Bash
---
```

Then numbered steps (`## Step N —`) with complete code snippets. Include troubleshooting tables and common pitfalls. Check existing SKILL.md files for style.

## Adding a New Plugin

1. Create `plugins/<plugin-name>/plugin.json` with name, version, description, author, category, and keywords.
2. Create `plugins/<plugin-name>/skills/SKILL.md` with the skill instructions.
3. Add an entry to `.claude-plugin/marketplace.json` with name, source, description, version, and category.

## Plugin Catalog

### Development

| Plugin | Description |
|--------|-------------|
| `integrate-claudecode` | Integrate Claude Code into a Docker/VSCode Devcontainer project |
| `create-devcontainer-project` | Scaffold a new project with a fully configured VS Code devcontainer |
| `add-claudecode-to-project` | Integrate Claude Code CLI + VS Code extension into an existing devcontainer |
| `add-beads-to-project` | Add the beads (`bd`) graph-based issue tracker to a devcontainer |
| `add-openspec-to-project` | Add the `@fission-ai/openspec` CLI to a devcontainer |

### Workflow

| Plugin | Description |
|--------|-------------|
| `wf-distill-workflow` | Extract a reusable template prompt, skill, or agent from a past interaction |
| `wf-generate-roadmap` | Research project state and generate a phased epic roadmap |
| `wf-generate-spec-beads` | Convert an OpenSpec change into a wired Beads task graph |
| `wf-implement-beads` | Drive implementation of a Beads-tracked body of work |
| `wf-spec-completion-auditor` | Audit drift between closed Beads issues and open OpenSpec tasks |

## Development

```bash
git add plugins/ .claude-plugin/
git commit -m "Add <plugin-name>"
git push origin add-skills
```
