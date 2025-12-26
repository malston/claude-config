# Claude Code Auto-Update Scripts

Automated scripts for keeping Claude Code and its plugins up to date.

## Scripts

### auto-upgrade-claude.sh

Automatically upgrades Claude Code and claudeup, then displays the changelog.

**Usage:**

```bash
# Normal upgrade (once per day)
./scripts/auto-upgrade-claude.sh

# Force upgrade even if already checked today
./scripts/auto-upgrade-claude.sh --force
```

**What it does:**

1. Checks if already run today (skips unless `--force`)
2. Upgrades Claude Code via `brew upgrade --cask claude-code`
3. Detects version changes and displays changelog from GitHub
4. Upgrades claudeup to the latest release
5. Records check date to avoid duplicate runs

**When to use:**

- Automatically called by `.envrc` when entering the directory (if configured)
- Manually run with `--force` to check for updates immediately

**Example output:**

```bash
Checking for Claude Code updates...

✨ Claude Code upgraded: 2.0.59 → 2.0.60

Fetching changelog...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## 2.0.60

### Features
- Add support for custom output styles
- Improve hook system performance

### Bug Fixes
- Fix issue with MCP server initialization
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Checking for claudeup updates...
Upgrading claudeup: 0.5.0 → 0.6.0
✓ claudeup upgraded
```

---

### auto-update-plugins.sh

Checks for plugin and marketplace updates using claudeup.

**Usage:**

```bash
# Normal update check (once per day)
./scripts/auto-update-plugins.sh

# Force check even if already ran today
./scripts/auto-update-plugins.sh --force
```

**What it does:**

1. Checks if already run today (skips unless `--force`)
2. Runs `claudeup update` to check and prompt for updates
3. Records check date to avoid duplicate runs

**When to use:**

- Automatically called by `.envrc` when entering the directory (if configured)
- Manually run with `--force` to check for plugin updates immediately

**What claudeup update does:**

- Checks all installed marketplaces for updates
- Checks all installed plugins for updates
- Prompts to update outdated items
- Handles the update process automatically

---

## Setup for Auto-Updates

To enable automatic updates when entering the directory, create `.envrc` (gitignored):

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Run updates in background to avoid blocking shell
"$SCRIPT_DIR/scripts/auto-upgrade-claude.sh" &
"$SCRIPT_DIR/scripts/auto-update-plugins.sh" &
```

Then allow direnv:

```bash
direnv allow
```

**Requirements:**

- `direnv` installed: `brew install direnv` (macOS) or `sudo apt-get install direnv` (Ubuntu/Debian)
- Shell integration: Add `eval "$(direnv hook zsh)"` to `~/.zshrc` (or bash equivalent)

---

### find-mcp-servers.sh

Discovers and displays all MCP server configuration sources across different scopes.

**Usage:**

```bash
# Run the discovery script
~/.claude/scripts/find-mcp-servers.sh
```

**What it does:**

1. Checks user-scoped configuration (`~/.claude.json`)
2. Checks project-scoped configuration (`.mcp.json` in current directory)
3. Checks local-scoped configuration (project-specific in `~/.claude.json`)
4. Checks enterprise managed configuration (system-wide)
5. Scans installed plugins for bundled MCP servers

**When to use:**

- Troubleshooting: "Why am I seeing these MCP servers?"
- Documentation: Understanding your MCP server setup
- Auditing: Verifying which plugins provide which MCP servers

**What it shows:**

For each scope, the script displays:
- Whether configuration exists
- Server names and types (stdio, http, sse)
- Commands or URLs for each server
- Plugin-bundled servers (inline or in `.mcp.json`)

**Example output:**

```bash
=== MCP Server Configuration Discovery ===

[1] User Scope (Global)
    File: ~/.claude.json
  File exists but no mcpServers configured

[2] Project Scope (Current Project)
    File: /path/to/project/.mcp.json
  Not found

[3] Local Scope (Project-Specific in User Config)
    Path: Project-specific entries in ~/.claude.json
  No local-scoped servers for this project

[4] Enterprise Managed (System-Wide)
    File: /Library/Application Support/ClaudeCode/managed-mcp.json
  Not configured

[5] Installed Plugins
    Checking: /Users/you/.claude/plugins

  Plugin: my-plugin
    Inline MCP servers in plugin.json:
      - server-name-1
      - server-name-2
```

---

## Manual Plugin Management

For manual plugin management, use `claudeup` directly:

```bash
# Check for updates
claudeup update

# List installed plugins
claudeup list

# Update a specific marketplace
claude plugin marketplace update <marketplace-name>

# Reinstall a plugin
claude plugin uninstall <plugin-name>@<marketplace>
claude plugin install <plugin-name>@<marketplace>
```

For more information, run `claudeup --help` or visit:
https://github.com/malston/claudeup

---

## Files Created

- `~/.claude/.last_brew_check` - Tracks last Claude Code upgrade check
- `~/.claude/.last_plugin_check` - Tracks last plugin update check

These files prevent the scripts from running multiple times per day.
