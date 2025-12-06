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

## Quick Start (Newcomers)

New to Claude Code? Get started in 2 minutes:

```bash
git clone https://github.com/malston/claude-config.git ~/.claude
cd ~/.claude
./setup.sh
```

The interactive setup will:
1. Install essential marketplaces (Anthropic official + Superpowers)
2. Offer optional additional marketplaces
3. Configure MCP servers

## Power User Setup

Already have your own fork with private config? Install everything:

```bash
git clone YOUR_FORK ~/.claude
cd ~/.claude
SETUP_MODE=auto ./setup.sh
```

This installs your complete configuration including:
- All public marketplaces from `plugins/setup-marketplaces.json`
- Your private marketplaces from `plugins/setup-marketplaces.local.json`
- All plugins from `plugins/setup-plugins.json`

## Customization

### Adding Private Marketplaces

Create `plugins/setup-marketplaces.local.json` (gitignored):

```json
{
  "marketplaces": {
    "your-private-marketplace": {
      "source": "github",
      "repo": "you/your-private-repo",
      "description": "Your private tools"
    }
  }
}
```

See `plugins/setup-marketplaces.local.json.example` for the full format.

### Adding Private Plugins

Create `plugins/setup-plugins.local.json` (gitignored):

```json
{
  "plugins": [
    "your-plugin@your-marketplace",
    "another-plugin@another-marketplace"
  ]
}
```

These files stay private even in your fork.

## Auto-Upgrade

The `scripts/auto-upgrade-claude.sh` script automatically checks for and installs Claude Code updates when you enter this directory (via direnv).

**Features:**
- Runs once per day to avoid slowness
- Displays changelog from GitHub when an upgrade occurs
- Runs in background to avoid blocking your shell

**Setup:**
1. Install direnv: `brew install direnv`
2. Add to your `~/.zshrc`: `eval "$(direnv hook zsh)"`
3. Create `.envrc` in this directory (gitignored):
   ```bash
   #!/bin/bash
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   "$SCRIPT_DIR/scripts/auto-upgrade-claude.sh" &
   ```
4. Allow direnv: `direnv allow`

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
