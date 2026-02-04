# Claude Code Configuration

> **Looking for a simpler starting point?** This is my personal setup with opinionated defaults and tooling that may not work for everyone. For a cleaner, general-purpose Claude Code sandbox, see **[claudeup/claude-config-dir](https://github.com/claudeup/claude-config-dir)** - it includes auto-updates via claudeup and works great in devcontainers.

Portable configuration for Claude Code CLI.

## Contents

| Directory/File   | Purpose                                                                 |
| ---------------- | ----------------------------------------------------------------------- |
| `CLAUDE.md`      | Primary user instructions and coding standards                          |
| `settings.json`  | Permissions, hooks, status line, plugin settings                        |
| `enabled.json`   | Enable/disable state for skills, commands, agents, rules, output-styles |
| `.library/`      | Canonical storage for all manageable items                              |
| `commands/`      | Symlinks to enabled commands in `.library/commands/`                    |
| `skills/`        | Symlinks to enabled skills in `.library/skills/`                        |
| `agents/`        | Symlinks to enabled agents in `.library/agents/`                        |
| `rules/`         | Symlinks to enabled rules in `.library/rules/`                          |
| `output-styles/` | Symlinks to enabled output styles in `.library/output-styles/`          |
| `hooks/`         | Hook scripts (e.g., markdown formatter)                                 |
| `plugins/`       | Plugin cache and CLI-managed marketplace data                           |
| `config/`        | MCP servers, profiles, and environment templates                        |
| `scripts/`       | Utility scripts for upgrades and diagnostics                            |
| `setup.sh`       | Post-clone setup script                                                 |
| `Dockerfile`     | Docker configuration for containerized environments                     |
| `docs/DOCKER.md` | Docker setup and usage guide                                            |

## Quick Start

Get started in 2 minutes:

```bash
git clone https://github.com/malston/claude-config.git ~/.claude
cd ~/.claude
./setup.sh
```

The setup script will:

1. Install Claude CLI and claudeup
2. Install marketplaces and plugins from `config/my-profile.json`
3. Configure MCP servers from `config/mcp-servers.json`

## Custom Profile

Fork this repo and edit `config/my-profile.json` to define your own marketplaces and plugins:

```json
{
  "name": "local",
  "description": "My development environment",
  "marketplaces": [
    { "source": "github", "repo": "anthropics/claude-plugins-official" }
  ],
  "plugins": [
    "superpowers@superpowers-marketplace",
    "commit-commands@claude-plugins-official"
  ]
}
```

## Docker Setup

Run Claude Code in a containerized environment with pre-configured settings:

```bash
# Build the image
docker-compose build

# Run Claude (setup runs automatically on first start)
docker-compose run --rm claude
```

Setup runs automatically on first container start, installing all configured marketplaces and plugins. For complete Docker documentation, build options, and usage examples, see [docs/DOCKER.md](docs/DOCKER.md).

## Managing Context Usage

With all plugins installed, MCP tools can use ~53k tokens (26% of context window) before you even start a conversation. The heavy plugins are Playwright and Chrome DevTools servers that are browser automation tools.

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

## Managing Skills, Commands, Agents, Rules, and Output Styles

This config uses a library-based enable/disable system. All items live in `.library/` and symlinks in discovery directories control what Claude Code sees.

Use `claudeup local` to manage local extensions:

**List all items and their status:**

```bash
claudeup local list
claudeup local list agents    # specific category
claudeup local list --enabled # only enabled items
```

**Disable/enable items:**

```bash
claudeup local disable agents business-product
claudeup local enable agents business-product
claudeup local disable agents '*'    # disable all agents
claudeup local enable skills '*'     # enable all skills
claudeup local enable agents gsd-*   # wildcard matching
```

**Sync after manual edits to `enabled.json`:**

```bash
claudeup local sync
```

**Install items from external paths:**

```bash
claudeup local install skills ~/path/to/my-skill
claudeup local install hooks ~/Downloads/format-on-save.sh
```

**View item contents:**

```bash
claudeup local view skills bash
claudeup local view agents gsd-planner
```

Categories: `skills`, `commands`, `agents`, `hooks`, `rules`, `output-styles`

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

# Or with claudeup
claudeup doctor
```

## Customization

### Adding Private Marketplaces

Edit `config/my-profile.json` to add your private marketplaces and plugins:

```json
{
  "marketplaces": [
    { "source": "github", "repo": "anthropics/claude-plugins-official" },
    { "source": "github", "repo": "your-org/your-private-marketplace" }
  ],
  "plugins": ["your-plugin@your-private-marketplace"]
}
```

If you fork this repo, your profile file will be in version control. For truly private config, add entries to `.gitignore` or use a separate private fork.

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

### Environment Variables: config/.env

Copy `config/env.example` to `config/.env` and fill in your values:

```bash
cp config/env.example config/.env
```

Supported variables:

| Variable           | Description                                     |
| ------------------ | ----------------------------------------------- |
| `GIT_USER_NAME`    | Git commit author name                          |
| `GIT_USER_EMAIL`   | Git commit author email                         |
| `GITHUB_TOKEN`     | GitHub token for private repos and pushing code |
| `CONTEXT7_API_KEY` | Context7 API key for documentation MCP server   |
| `DOTFILES_REPO`    | Dotfiles repo to clone (Docker only)            |
| `DOTFILES_BRANCH`  | Dotfiles branch, defaults to `linux` (Docker)   |
| `WORKSPACE`        | Workspace directory to mount (Docker only)      |

The `.env` file is gitignored so secrets won't be committed.

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
