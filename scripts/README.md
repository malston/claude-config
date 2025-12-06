# Claude Code Plugin Management Scripts

This directory contains scripts for managing Claude Code installations, marketplaces, and plugins.

## Table of Contents

- [Quick Reference](#quick-reference)
- [Script Details](#script-details)
  - [auto-upgrade-claude.sh](#auto-upgrade-claudesh)
  - [check-updates.sh](#check-updatessh)
  - [refresh-marketplaces.sh](#refresh-marketplacessh)
  - [refresh-plugins.sh](#refresh-pluginssh)
  - [cleanup-stale-plugins.sh](#cleanup-stale-pluginssh)
  - [fix-plugin-paths.sh](#fix-plugin-pathssh)
  - [toggle-plugin.sh](#toggle-pluginsh)
- [Common Workflows](#common-workflows)
- [Troubleshooting](#troubleshooting)

## Quick Reference

| Task | Command |
|------|---------|
| Check for updates to marketplaces and plugins | `./scripts/check-updates.sh` |
| Update marketplaces and plugins if available | `./scripts/check-updates.sh` (then answer Y) |
| Reinstall all marketplaces | `./scripts/refresh-marketplaces.sh` |
| Reinstall all plugins | `./scripts/refresh-plugins.sh` |
| Choose which marketplaces to reinstall | `./scripts/refresh-marketplaces.sh --interactive` |
| Choose which plugins to reinstall | `./scripts/refresh-plugins.sh --interactive` |
| Clean up stale plugin entries | `./scripts/cleanup-stale-plugins.sh --reinstall` |
| Fix broken plugin paths | `./scripts/fix-plugin-paths.sh` |
| List all installed plugins | `./scripts/toggle-plugin.sh --list` |
| Toggle a plugin on/off | `./scripts/toggle-plugin.sh <plugin-name>` |
| Reduce MCP context usage | Disable heavy plugins (see [Managing MCP Context](#managing-mcp-context-usage)) |
| Upgrade Claude Code itself | `./scripts/auto-upgrade-claude.sh` |

## Script Details

### auto-upgrade-claude.sh

**Purpose:** Automatically upgrades Claude Code via Homebrew and displays changelog.

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
3. Detects version changes and displays changelog
4. Records check date to avoid duplicate runs

**When to use:**

- Automatically called by `.envrc` when entering the directory
- Manually run with `--force` to check for updates immediately

---

### check-updates.sh

**Purpose:** Checks if marketplaces or plugins are out of date and prompts to upgrade them.

**Usage:**

```bash
# Check for updates and prompt to install
./scripts/check-updates.sh

# Only check, don't prompt for installation
./scripts/check-updates.sh --check-only
```

**What it does:**

1. **Checks marketplaces:** Uses git to compare local HEAD with remote origin
2. **Checks plugins:** Compares installed `gitCommitSha` with current marketplace commit
3. **Prompts for updates:** Shows what's outdated and asks if you want to update
4. **Updates marketplaces:** Runs `claude plugin marketplace update` for selected items
5. **Reinstalls plugins:** Uninstalls and reinstalls outdated plugins

**When to use:**

- Run periodically to keep plugins and marketplaces current
- Use `--check-only` to see what's available without making changes
- Run after updating marketplaces to check if plugins need reinstalling

**Example output:**

```
━━━ Checking Marketplaces ━━━
Checking superpowers-marketplace...
  ✓ Up to date
Checking claude-code-plugins...
  ⚠ Update available

━━━ Checking Plugins ━━━
Checking superpowers@superpowers-marketplace...
  ✓ Up to date
Checking hookify@claude-code-plugins...
  ⚠ Update available

━━━ Marketplace Updates Available ━━━
  • claude-code-plugins

Update these marketplaces? [Y/n]
```

---

### refresh-marketplaces.sh

**Purpose:** Reinstall marketplaces by uninstalling and adding them back.

**Usage:**

```bash
# Reinstall all marketplaces
./scripts/refresh-marketplaces.sh

# Choose which marketplaces to reinstall
./scripts/refresh-marketplaces.sh --interactive
```

**What it does:**

1. Reads marketplace list from `known_marketplaces.json`
2. For each marketplace (or selected ones in interactive mode):
   - Uninstalls: `claude plugin marketplace remove <marketplace>`
   - Reinstalls: `claude plugin marketplace add <source>`
3. Reports success/failure for each marketplace

**When to use:**

- When a marketplace is corrupted or in an inconsistent state
- To get a clean slate for marketplace installations
- When marketplace structure has changed significantly

**Interactive mode:**

```
Select marketplaces to reinstall:
Enter numbers separated by spaces (e.g., 1 3 5), 'all' for all items, or 'none' to skip:

  1) superpowers-marketplace
  2) claude-code-plugins
  3) every-marketplace

Selection: 1 3
```

---

### refresh-plugins.sh

**Purpose:** Update marketplaces and/or reinstall plugins.

**Usage:**

```bash
# Update all marketplaces and reinstall all plugins
./scripts/refresh-plugins.sh

# Only update marketplaces
./scripts/refresh-plugins.sh --update-only

# Only reinstall plugins
./scripts/refresh-plugins.sh --reinstall-only

# Interactive mode - choose what to update/reinstall
./scripts/refresh-plugins.sh --interactive

# Combine flags
./scripts/refresh-plugins.sh --update-only --interactive
```

**What it does:**

1. **Updates marketplaces:** Runs `claude plugin marketplace update` for all (or selected) marketplaces
2. **Reinstalls plugins:** Uninstalls then reinstalls all (or selected) plugins
3. **Interactive mode:** Lets you select which items to process

**When to use:**

- Regular maintenance to keep everything current
- After marketplace updates to ensure plugins are compatible
- When plugins are behaving unexpectedly (reinstall to reset)

**Options:**

- `--update-only` - Only update marketplaces, skip plugin reinstall
- `--reinstall-only` - Only reinstall plugins, skip marketplace update
- `--interactive` / `-i` - Choose which items to process
- `--help` / `-h` - Show usage information

---

### cleanup-stale-plugins.sh

**Purpose:** Identify and remove plugin entries where the installation path no longer exists.

**Usage:**

```bash
# List stale plugins without making changes
./scripts/cleanup-stale-plugins.sh --list-only

# Remove stale entries
./scripts/cleanup-stale-plugins.sh

# Remove stale entries and offer to reinstall
./scripts/cleanup-stale-plugins.sh --reinstall
```

**What it does:**

1. Scans `installed_plugins.json` for entries where `installPath` doesn't exist
2. Shows list of stale entries with their paths
3. Prompts to remove stale entries (cleans up the JSON)
4. Optionally offers to reinstall the plugins

**When to use:**

- After marketplace structure changes
- When `check-updates.sh` shows "Plugin path not found" errors
- To clean up orphaned plugin entries
- After manually deleting plugin directories

**What makes a plugin "stale":**
A plugin is stale if:

- It exists in `installed_plugins.json`
- BUT the directory at its `installPath` doesn't exist

**Example:**

```
━━━ Found 18 Stale Plugin Entries ━━━
  • pr-review-toolkit@claude-code-plugins
    Path: /Users/you/.claude/plugins/marketplaces/claude-code-plugins/pr-review-toolkit
  • hookify@claude-code-plugins
    Path: /Users/you/.claude/plugins/marketplaces/claude-code-plugins/hookify

Remove these stale entries from installed_plugins.json? [Y/n]
```

---

### fix-plugin-paths.sh

**Purpose:** Workaround for Claude CLI bug where plugins are installed with incorrect paths.

**Usage:**

```bash
./scripts/fix-plugin-paths.sh
```

**What it does:**

1. **Backs up** `installed_plugins.json` to `installed_plugins.json.backup`
2. **Fixes paths** for plugins with `isLocal: true` by adding missing subdirectories:
   - `claude-code-plugins` → adds `/plugins/` subdirectory
   - `claude-code-templates` → adds `/plugins/` subdirectory
   - `anthropic-agent-skills` → adds `/skills/` subdirectory
   - `every-marketplace` → adds `/plugins/` subdirectory
   - `awesome-claude-code-plugins` → adds `/plugins/` subdirectory
   - `tanzu-cf-architect` → removes duplicate directory name
3. **Shows changes** made to the JSON

**When to use:**

- After running `cleanup-stale-plugins.sh --reinstall` if plugins are immediately stale again
- When `check-updates.sh` shows many "Plugin path not found" errors
- After `claude plugin install` creates plugins with wrong paths

**Known Issue:**
There's a bug in `claude plugin install` where it creates plugins with `isLocal: true` but doesn't account for marketplace subdirectories. This script is a workaround until the bug is fixed in the Claude CLI.

**Example output:**

```
✓ Backed up to: /Users/you/.claude/plugins/installed_plugins.json.backup
✓ Fixed plugin paths in installed_plugins.json

Changes made:
  • pr-review-toolkit@claude-code-plugins
    /Users/you/.claude/plugins/marketplaces/claude-code-plugins/plugins/pr-review-toolkit
  • hookify@claude-code-plugins
    /Users/you/.claude/plugins/marketplaces/claude-code-plugins/plugins/hookify
```

---

### toggle-plugin.sh

**Purpose:** Toggle any Claude Code plugin on/off to manage MCP context usage and functionality.

**Usage:**

```bash
# List all installed plugins
./scripts/toggle-plugin.sh --list

# Toggle a plugin (disable if enabled, enable if disabled)
./scripts/toggle-plugin.sh compound-engineering

# Can use short name or full name@marketplace
./scripts/toggle-plugin.sh superpowers@superpowers-marketplace

# Show help
./scripts/toggle-plugin.sh --help
```

**What it does:**

1. **Lists plugins** - Shows all installed plugins from `installed_plugins.json`
2. **Toggles state** - Disables enabled plugins, enables disabled plugins
3. **Handles names** - Works with both short names and full `name@marketplace` format
4. **Shows feedback** - Confirms the action and explains what changed

**When to use:**

- To reduce MCP context usage by disabling plugins you're not currently using
- To temporarily disable plugins with many MCP servers (like Playwright)
- To manage which plugin features are available in your session
- To troubleshoot plugin conflicts

**Examples:**

```bash
# See what's installed
$ ./scripts/toggle-plugin.sh --list

=== Installed Plugins ===

  • compound-engineering@every-marketplace
  • superpowers@superpowers-marketplace
  • hookify@claude-code-plugins
  ...

Total: 27 plugins

# Disable a heavy plugin
$ ./scripts/toggle-plugin.sh compound-engineering
✓ Disabled compound-engineering@every-marketplace

Plugin commands, agents, skills, and MCP servers are now unavailable
Run again to re-enable

# Re-enable it later
$ ./scripts/toggle-plugin.sh compound-engineering
✓ Enabled compound-engineering@every-marketplace

Plugin commands, agents, skills, and MCP servers are now available
Run again to disable
```

**Benefits:**

- **Reduces context usage** - Disabling plugins removes their MCP servers from your context
- **Improves performance** - Fewer tools to process means faster responses
- **Selective features** - Only enable what you need for current work
- **Easy toggling** - Run the same command to enable/disable

**Use cases:**

1. **Managing MCP context:**

   ```bash
   # Disable heavy plugins when doing simple coding
   ./scripts/toggle-plugin.sh compound-engineering
   ./scripts/toggle-plugin.sh testing-suite

   # Enable when you need browser automation or design work
   ./scripts/toggle-plugin.sh compound-engineering
   ```

2. **Troubleshooting:**

   ```bash
   # Disable plugins to isolate issues
   ./scripts/toggle-plugin.sh hookify
   # Test if issue persists
   # Re-enable
   ./scripts/toggle-plugin.sh hookify
   ```

3. **Context budgeting:**

   ```bash
   # Check what's installed
   ./scripts/toggle-plugin.sh --list

   # Disable plugins you're not using today
   ./scripts/toggle-plugin.sh plugin1
   ./scripts/toggle-plugin.sh plugin2
   ```

**Note:** The script determines the current state by attempting to disable the plugin. If already disabled, it enables it instead.

---

## Common Workflows

### Weekly Maintenance

**Goal:** Keep everything up to date

```bash
# 1. Check for updates
./scripts/check-updates.sh

# 2. If updates are available, install them (answer Y to prompts)
#    The script will update marketplaces and reinstall plugins as needed

# 3. If you see "Plugin path not found" errors after reinstall:
./scripts/fix-plugin-paths.sh

# 4. Verify everything is clean
./scripts/check-updates.sh --check-only
```

### After Marketplace Structure Changes

**Goal:** Fix paths when marketplace reorganizes plugins

```bash
# 1. Identify stale plugins
./scripts/cleanup-stale-plugins.sh --list-only

# 2. Clean up and reinstall
./scripts/cleanup-stale-plugins.sh --reinstall

# 3. Fix paths if CLI creates them incorrectly
./scripts/fix-plugin-paths.sh

# 4. Verify all plugins are working
./scripts/check-updates.sh --check-only
```

### Selective Plugin Refresh

**Goal:** Only reinstall specific plugins

```bash
# 1. Run in interactive mode
./scripts/refresh-plugins.sh --reinstall-only --interactive

# 2. Select which plugins to reinstall
#    Enter numbers: 1 5 7 12

# 3. Fix paths if needed
./scripts/fix-plugin-paths.sh
```

### Clean Slate

**Goal:** Completely refresh all marketplaces and plugins

```bash
# 1. Reinstall all marketplaces
./scripts/refresh-marketplaces.sh

# 2. Reinstall all plugins
./scripts/refresh-plugins.sh --reinstall-only

# 3. Fix any path issues
./scripts/fix-plugin-paths.sh

# 4. Verify everything works
./scripts/check-updates.sh --check-only
```

### Managing MCP Context Usage

**Goal:** Reduce MCP context usage by selectively enabling/disabling plugins

```bash
# 1. Check current MCP context usage
#    Run /doctor in Claude Code to see context usage

# 2. List all installed plugins
./scripts/toggle-plugin.sh --list

# 3. Disable heavy plugins you're not currently using
#    (Plugins with MCP servers like Playwright, context7)
./scripts/toggle-plugin.sh compound-engineering
./scripts/toggle-plugin.sh testing-suite

# 4. Restart Claude Code to reload MCP configuration

# 5. Run /doctor again to verify reduced context usage

# 6. Re-enable when needed
./scripts/toggle-plugin.sh compound-engineering
```

**Common MCP-heavy plugins:**
- `compound-engineering` - ~16,313 tokens (Playwright + context7)
- `testing-suite` - ~14,501 tokens (Playwright)
- Any plugin with browser automation or documentation servers

**Recommended workflow:**
1. **Default state:** Keep heavy plugins disabled for general coding
2. **Enable when needed:** Turn on for code review, design work, browser testing
3. **Disable when done:** Return to lean context for regular development

**Benefits:**
- ✅ Reduces context usage from ~36k to ~20k tokens
- ✅ Faster response times
- ✅ Lower costs
- ✅ More context available for your actual code

---

### Troubleshooting "Plugin path not found" Errors

**Goal:** Fix stale plugin entries

```bash
# Option 1: Fix paths in place (faster)
./scripts/fix-plugin-paths.sh
./scripts/check-updates.sh --check-only

# Option 2: Clean up and reinstall (more thorough)
./scripts/cleanup-stale-plugins.sh --reinstall
./scripts/fix-plugin-paths.sh
./scripts/check-updates.sh --check-only

# Option 3: Remove truly orphaned plugins
# (plugins that don't exist in any marketplace)
claude plugin uninstall <plugin-name>
```

---

## Troubleshooting

### Q: Why do plugins become "stale" after reinstalling?

**A:** There's a bug in `claude plugin install` where plugins with `isLocal: true` are created with incorrect paths. The CLI doesn't account for subdirectories like `/plugins/` or `/skills/` in marketplace structures.

**Solution:** Run `./scripts/fix-plugin-paths.sh` after reinstalling plugins.

### Q: A plugin shows "Plugin path not found" but I just installed it

**A:** The CLI likely created it with the wrong path structure.

**Solution:**

```bash
./scripts/fix-plugin-paths.sh
```

### Q: How do I know if a plugin is truly orphaned vs. just has a wrong path?

**A:** Check if the plugin exists in the marketplace:

```bash
# List plugins in a marketplace
ls ~/.claude/plugins/marketplaces/claude-code-plugins/plugins/

# If the plugin is there but showing as stale, it's a path issue (fixable)
# If the plugin isn't there at all, it's orphaned (should be uninstalled)
```

### Q: What's the difference between `isLocal: true` and `isLocal: false`?

**A:**

- `isLocal: false` - Plugin is copied to `~/.claude/plugins/cache/` (working correctly)
- `isLocal: true` - Plugin references marketplace directory directly (prone to path bugs)

The CLI decides this automatically. Most plugins should be cached (`isLocal: false`).

### Q: Can I run these scripts automatically?

**A:** Yes, but be careful:

- `auto-upgrade-claude.sh` is already automated via `.envrc`
- `check-updates.sh --check-only` is safe to run in cron jobs
- Other scripts require user input (Y/n prompts)

For automation, you'd need to modify the scripts to accept a `--yes` flag.

### Q: What if I accidentally delete a plugin I need?

**A:** Just reinstall it:

```bash
claude plugin install <plugin-name>@<marketplace-name>

# Then fix the path if needed
./scripts/fix-plugin-paths.sh
```

### Q: How do I report the `isLocal: true` path bug to Anthropic?

**A:** Create an issue at <https://github.com/anthropics/claude-code/issues> with:

- Title: "Plugin install creates incorrect paths for isLocal: true plugins"
- Description: "`claude plugin install` creates entries with `isLocal: true` but doesn't account for `/plugins/` subdirectories in marketplaces, resulting in stale paths immediately after installation"
- Steps to reproduce:
  1. Install a plugin from claude-code-plugins marketplace
  2. Check `installed_plugins.json` - path will be missing `/plugins/` subdirectory
  3. Run `check-updates.sh` - plugin shows as "path not found"

---

## Script Locations

All scripts are located in: `~/.claude/scripts/`

Supporting files:

- `~/.claude/plugins/known_marketplaces.json` - List of installed marketplaces
- `~/.claude/plugins/installed_plugins.json` - List of installed plugins
- `~/.claude/plugins/installed_plugins.json.backup` - Backup created by fix-plugin-paths.sh

---

## Safety Features

All scripts include:

- ✅ Backup creation (where applicable)
- ✅ Dry-run options (`--list-only`, `--check-only`)
- ✅ Interactive mode for selective operations
- ✅ User confirmation prompts before making changes
- ✅ Detailed status output with color coding
- ✅ Error handling and status reporting
