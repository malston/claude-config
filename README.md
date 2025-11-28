# Claude Code Configuration

Portable configuration for Claude Code CLI.

## Contents

| Directory/File | Purpose |
|----------------|---------|
| `CLAUDE.md` | Primary user instructions and coding standards |
| `CLAUDE.*.md` | Context-specific instruction variants |
| `settings.json` | Permissions, hooks, status line, plugin settings |
| `commands/` | Custom slash commands |
| `skills/` | Custom skills |
| `agents/` | Custom agent definitions |
| `hooks/` | Hook scripts (e.g., markdown formatter) |
| `mcp/` | MCP server configurations |
| `output-styles/` | Custom output style definitions |
| `plugins/` | Plugin configuration and marketplace list |

## Setup on a New Machine

```bash
git clone https://github.com/malston/claude-config.git ~/.claude
```

After cloning, install your plugins via Claude Code - the `known_marketplaces.json` file preserves your marketplace sources.

## What's Not Tracked

Session-specific data is gitignored:
- Debug logs, conversation history, shell snapshots
- Project session data, todos, plans
- Installed plugins (machine-specific)
- IDE lock files, analytics cache
