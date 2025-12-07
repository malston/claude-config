# Claude Code Auto-Update Scripts

Automated scripts for keeping Claude Code and its plugins up to date.

## Scripts

### auto-upgrade-claude.sh

Automatically upgrades Claude Code and claude-pm, then displays the changelog.

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
4. Upgrades claude-pm to the latest release
5. Records check date to avoid duplicate runs

**When to use:**

- Automatically called by `.envrc` when entering the directory (if configured)
- Manually run with `--force` to check for updates immediately

**Example output:**

```
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

Checking for claude-pm updates...
Upgrading claude-pm: 0.5.0 → 0.6.0
✓ claude-pm upgraded
```

---

### auto-update-plugins.sh

Checks for plugin and marketplace updates using claude-pm.

**Usage:**

```bash
# Normal update check (once per day)
./scripts/auto-update-plugins.sh

# Force check even if already ran today
./scripts/auto-update-plugins.sh --force
```

**What it does:**

1. Checks if already run today (skips unless `--force`)
2. Runs `claude-pm update` to check and prompt for updates
3. Records check date to avoid duplicate runs

**When to use:**

- Automatically called by `.envrc` when entering the directory (if configured)
- Manually run with `--force` to check for plugin updates immediately

**What claude-pm update does:**

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

## Manual Plugin Management

For manual plugin management, use `claude-pm` directly:

```bash
# Check for updates
claude-pm update

# List installed plugins
claude-pm list

# Update a specific marketplace
claude plugin marketplace update <marketplace-name>

# Reinstall a plugin
claude plugin uninstall <plugin-name>@<marketplace>
claude plugin install <plugin-name>@<marketplace>
```

For more information, run `claude-pm --help` or visit:
https://github.com/malston/claude-pm

---

## Files Created

- `~/.claude/.last_brew_check` - Tracks last Claude Code upgrade check
- `~/.claude/.last_plugin_check` - Tracks last plugin update check

These files prevent the scripts from running multiple times per day.
