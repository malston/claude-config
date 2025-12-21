# Claude Code Configuration

Portable configuration for Claude Code CLI.

## Contents

| Directory/File | Purpose |
|----------------|---------|
| `CLAUDE.md` | Primary user instructions and coding standards |
| `settings.json` | Permissions, hooks, status line, plugin settings |
| `commands/` | Custom slash commands |
| `skills/` | Custom skills |
| `agents/` | Custom agent definitions (active in root, disabled in `disabled/`) |
| `hooks/` | Hook scripts (e.g., markdown formatter) |
| `output-styles/` | Custom output style definitions |
| `plugins/` | Plugin configuration and marketplace list |

## Quick Start

```bash
git clone https://github.com/malston/claude-config.git --branch claudeup ~/.claude
```
