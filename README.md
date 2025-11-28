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
| `setup.sh` | Post-clone setup script |

## Setup on a New Machine

```bash
git clone https://github.com/malston/claude-config.git ~/.claude
cd ~/.claude
./setup.sh
```

The setup script installs:
- User-scoped MCP servers (chrome-devtools)
- Plugin marketplaces

After running the script, install plugins via Claude Code - the `known_marketplaces.json` file preserves your marketplace sources.

## What's Not Tracked

Session-specific data is gitignored:
- Debug logs, conversation history, shell snapshots
- Project session data, todos, plans
- Installed plugins (machine-specific)
- IDE lock files, analytics cache
- MCP servers (user-scoped, installed via setup.sh)
