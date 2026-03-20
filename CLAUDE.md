# CLAUDE.md

## What This Is

A Claude Code plugin marketplace repo. 

## Structure

```
plugins/<plugin-name>/
├── plugin.json          # metadata (name, version, description, keywords, author)
└── skills/SKILL.md      # step-by-step instructions Claude follows
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


## Development

```bash
git add plugins/
git commit -m "Update <plugin-name>"
git push origin add-skills
```

