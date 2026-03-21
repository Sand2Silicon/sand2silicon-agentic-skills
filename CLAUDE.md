# CLAUDE.md

## What This Is

A Claude Code plugin marketplace repo.
Plugin Marketplaces https://code.claude.com/docs/en/plugin-marketplaces
Follow the reference documentation for plugins at: https://code.claude.com/docs/en/plugins-reference
Convert simple skills to plugins with  https://code.claude.com/docs/en/plugins
Agent Skills Specification: https://agentskills.io/specification

## Structure

```
.claude-plugin/marketplace.json  # registry of all plugins in this repo
plugins/<plugin-name>/
```

A complete plugin follows this structure (plugins contain only required portions and the parts they need):
```
enterprise-plugin/
├── .claude-plugin/           # Metadata directory (optional)
│   └── plugin.json             # plugin manifest
├── commands/                 # Default command location
│   ├── status.md
│   └── logs.md
├── agents/                   # Default agent location
│   ├── security-reviewer.md
│   ├── performance-tester.md
│   └── compliance-checker.md
├── skills/                   # Agent Skills
│   ├── code-reviewer/
│   │   └── SKILL.md
│   └── pdf-processor/
│       ├── SKILL.md
│       └── scripts/
├── hooks/                    # Hook configurations
│   ├── hooks.json           # Main hook config
│   └── security-hooks.json  # Additional hooks
├── settings.json            # Default settings for the plugin
├── .mcp.json                # MCP server definitions
├── .lsp.json                # LSP server configurations
├── scripts/                 # Hook and utility scripts
│   ├── security-scan.sh
│   ├── format-code.py
│   └── deploy.js
├── LICENSE                  # License file
└── CHANGELOG.md             # Version history
```


## SKILL.md Format

Each skill starts with YAML frontmatter:
```yaml
---
name: skill-name
description: when/why Claude triggers this (be specific and comprehensive)
---
```

Then numbered steps (`## Step N —`) with complete code snippets. Include troubleshooting tables and common pitfalls. Check existing SKILL.md files for style.

## Adding a New Plugin

1. Create `plugins/<plugin-name>/.claude-plugin/plugin.json` with name, version, description, author, category, and keywords.
2. Create `plugins/<plugin-name>/skills/<skill-name>/SKILL.md` with the skill instructions.
3. Add an entry to `.claude-plugin/marketplace.json` with name, source, description, version, and category.

## Development

```bash
git add plugins/ .claude-plugin/
git commit -m "Add <plugin-name>"
git push origin add-skills
```
