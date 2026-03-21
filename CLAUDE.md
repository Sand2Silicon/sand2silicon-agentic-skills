# CLAUDE.md

## What This Is

A **Claude Code plugin marketplace** — a git repo that hosts plugins installable via the Claude Code plugin system. Users add this repo as a marketplace source and install individual plugins from it.

Reference docs:
- [Plugin Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces)
- [Plugins Reference](https://code.claude.com/docs/en/plugins-reference)
- [Creating Plugins](https://code.claude.com/docs/en/plugins)
- [Agent Skills Specification](https://agentskills.io/specification)

## Concepts

**Plugin** — a self-contained directory that extends Claude Code. A plugin can contain skills, agents, commands, hooks, MCP servers, and LSP servers. Registered in `.claude-plugin/marketplace.json` so users can install it.

**Skill** — a model-invoked capability with a `SKILL.md` file. Claude triggers skills automatically based on context, or users invoke them as `/plugin-name:skill-name`. A single plugin can contain multiple skills under `skills/`.

## Plugin Structure

Only include the parts a plugin needs. The manifest and `skills/` are the minimum for a skills-only plugin.

```
plugins/<plugin-name>/
├── .claude-plugin/
│   └── plugin.json          # manifest: name, version, description, author, keywords
├── skills/
│   └── <skill-name>/
│       └── SKILL.md         # frontmatter + instructions
├── agents/                  # optional: subagent definitions
├── commands/                # optional: slash commands (legacy; prefer skills/)
├── hooks/
│   └── hooks.json           # optional: event hooks
├── .mcp.json                # optional: MCP server definitions
└── settings.json            # optional: default plugin settings
```

`plugin.json` goes inside `.claude-plugin/`. All other directories (`skills/`, `agents/`, `hooks/`, etc.) go at the **plugin root**, not inside `.claude-plugin/`.

## SKILL.md Format

```yaml
---
name: skill-name
description: when/why Claude triggers this — be specific and comprehensive
---
```

Body: numbered steps (`## Step N —`), complete code snippets, troubleshooting tables, common pitfalls. Check existing SKILL.md files for style.

## Adding a Plugin or Skill

**New plugin with one or more skills:**
1. Create `plugins/<plugin-name>/.claude-plugin/plugin.json`
2. Create `plugins/<plugin-name>/skills/<skill-name>/SKILL.md` (repeat for each skill)
3. Add one entry to `.claude-plugin/marketplace.json` pointing at the plugin directory

**Adding a skill to an existing plugin:**
1. Create `plugins/<plugin-name>/skills/<new-skill-name>/SKILL.md`
2. Bump the version in `plugin.json` and the `marketplace.json` entry

**Converting a standalone skill to a plugin:**
1. Create the plugin directory structure above
2. `git mv` the existing `SKILL.md` into `skills/<skill-name>/SKILL.md`
3. Add the marketplace entry; remove any old standalone entry

**`marketplace.json` entry shape:**
```json
{
  "name": "plugin-name",
  "source": "./plugins/plugin-name",
  "description": "One-line description",
  "version": "1.0.0",
  "category": "development | workflow | ..."
}
```

## Development

```bash
git add plugins/ .claude-plugin/
git commit -m "add: <plugin-name>"
git push origin add-skills
```
