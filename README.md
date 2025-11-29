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
| `config/` | MCP server definitions and environment templates |
| `setup.sh` | Post-clone setup script |

## Setup on a New Machine

```bash
git clone https://github.com/malston/claude-config.git ~/.claude
cd ~/.claude

# Optional: configure secrets for MCP servers that need them
cp config/env.example config/.env
# Edit config/.env with your API keys

./setup.sh
```

The setup script:
- Reads `config/mcp-servers.json` and installs each MCP server (user-scoped)
- Reads `plugins/known_marketplaces.json` and adds each marketplace
- Warns about any missing environment variables

## Configuration Files

### config/mcp-servers.json

Defines user-scoped MCP servers (available in all projects):
```json
{
  "servers": [
    {
      "name": "server-name",
      "command": "npx",
      "args": ["-y", "package-name", "--api-key", "$API_KEY"],
      "secrets": {
        "API_KEY": "op://Private/SERVICE_API_KEY/credential"
      }
    }
  ]
}
```

Secrets are fetched from 1Password CLI (`op read`) during setup. Install with:
```bash
brew install 1password-cli
op signin
```

### Fallback: config/.env

If not using 1Password, set secrets via environment or `config/.env`:
```bash
CONTEXT7_API_KEY=your-key-here
```

## What's Not Tracked

Session-specific data is gitignored:
- Debug logs, conversation history, shell snapshots
- Project session data, todos, plans
- Installed plugins (machine-specific)
- IDE lock files, analytics cache
- Secrets (`config/.env`)
