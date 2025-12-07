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
| `Dockerfile` | Docker configuration for containerized environments |
| `docs/DOCKER.md` | Docker setup and usage guide |

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

## Docker Setup

Run Claude Code in a containerized environment with pre-configured settings:

```bash
# Build the image
docker build -t claude-code:latest .

# Run interactively
docker run -it --rm -v $(pwd)/workspace:/home/claude/workspace claude-code:latest /bin/bash
```

For complete Docker documentation, build options, and usage examples, see [docs/DOCKER.md](docs/DOCKER.md).

## Managing Context Usage

With all plugins installed, MCP tools can use ~53k tokens (26% of context window) before you even start a conversation. The heavy plugins are Playwright servers from browser automation tools.

**Recommended: Disable heavy plugins immediately after setup** to free up ~45k tokens:

```bash
# Disable Playwright-heavy plugins (saves ~29k tokens)
claude plugin disable testing-suite
claude plugin disable compound-engineering
```

**Optionally disable heavy MCP servers** (saves ~18k tokens):

```bash
# Remove chrome-devtools MCP server (not a plugin)
claude mcp remove chrome-devtools --scope user
```

After disabling, your MCP context drops from ~53k to ~5k tokens (90% reduction).

**Re-enable when needed:**

```bash
# Re-enable plugins
claude plugin enable compound-engineering  # for design/browser work
claude plugin enable testing-suite         # for testing

# Re-add MCP server (requires reinstalling)
# See config/mcp-servers.json for configuration
```

**Check current usage:**

```bash
# Inside Claude
/context

# Or with claude-pm
claude-pm doctor
```

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

This file stays private even in your fork.

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

## Credits

This configuration and workflow system draws inspiration from:

- **[Jesse Vincent](https://blog.fsck.com/about/)** (Massively Parallel Procrastination)
  - Superpowers marketplace and skills
  - CLAUDE.md workflow patterns and coding standards
  - TDD and systematic debugging approaches

- **Anthropic** - Official Claude Code plugins and agent patterns

- **The Claude Code Community** - Setup patterns, hooks, and plugin development practices

Special thanks to the [Every](https://every.to) team for the Compound Engineering toolkit.
