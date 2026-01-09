# Setup System Redesign

**Date:** 2025-12-06
**Status:** Approved Design
**Goal:** Make setup.sh user-friendly for newcomers while supporting power users with private configurations

## Problem Statement

Current `setup.sh` installs all marketplaces and plugins from Mark's personal config, including private repositories that newcomers can't access. This creates a poor first-run experience and doesn't support users maintaining their own forks with private additions.

## Requirements

1. **Newcomers**: Interactive setup that's not overwhelming, installs essentials quickly
2. **Power users**: Non-interactive mode that installs complete config on new machines
3. **Private repos**: Support private marketplaces/plugins without committing them
4. **Maintainability**: Easy to keep personal forks updated with upstream changes

## Architecture

### File Structure

```
.claude/
├── plugins/
│   ├── setup-marketplaces.json          # Public marketplaces (committed)
│   ├── setup-marketplaces.local.json    # Private marketplaces (gitignored)
│   ├── setup-plugins.json               # Public plugins to install (committed)
│   ├── setup-plugins.local.json         # Private plugins (gitignored)
│   ├── known_marketplaces.json          # CLI state (gitignored)
│   └── installed_plugins.json           # CLI state (gitignored)
├── config/
│   ├── mcp-servers.json                 # MCP server config (committed)
│   └── .env                              # Secrets (gitignored)
├── setup.sh                              # Main setup script
└── README.md                             # Documentation
```

### Key Principles

1. **Separation of concerns**: `setup-*.json` files are "desired state" (source of truth), while `known_marketplaces.json` and `installed_plugins.json` are CLI-managed state

2. **Public/Private split**: `.local.json` files let users maintain private marketplaces/plugins without committing them

3. **Mode selection**: `SETUP_MODE=auto ./setup.sh` for power users, default interactive for newcomers

4. **Progressive disclosure**: Interactive mode has two phases - essentials first, then optional exploration

## Interactive Mode Flow

### Phase 1: Essential Setup (Auto-runs)

```bash
./setup.sh  # or SETUP_MODE=interactive ./setup.sh

→ Installing essentials...
  ✓ claude-code-plugins (Anthropic official)
  ✓ superpowers-marketplace (Jesse Vincent's productivity toolkit)

→ Installing MCP servers from config/mcp-servers.json...
  ✓ context7 (or skipped if secrets missing)

→ Essentials installed! You have a working Claude Code setup.
```

**Rationale**: Get users productive immediately with official Anthropic plugins and community-loved superpowers toolkit.

### Phase 2: Marketplace Discovery (Optional)

```bash
Want to explore more marketplaces? [Y/n]: y

Popular marketplaces:
  [ ] awesome-claude-code-plugins - Community plugins
  [ ] every-marketplace - Compound Engineering tools
  [ ] anthropic-agent-skills - Example agent patterns

Select marketplaces (space to toggle, enter to continue):
→ awesome-claude-code-plugins
→ every-marketplace

Installing selected marketplaces...
✓ Done! Use 'claude plugin list <marketplace>' to browse plugins.
```

**Phase 2 is skippable**: If user says 'n', setup completes immediately. They can always run `claude plugin marketplace add <repo>` later.

**Rationale**: Show curated options without overwhelming. Focus on marketplaces (stable) rather than plugins (change frequently). Users can explore plugins afterward with CLI commands.

## Auto Mode (Power Users)

### Usage

```bash
SETUP_MODE=auto ./setup.sh
```

### Behavior

1. **No prompts** - runs completely unattended
2. **Reads config**: Merges `setup-marketplaces.json` + `.local.json`
3. **Installs everything**: All marketplaces and plugins from merged config
4. **Graceful failures**:
   - Private repos that fail? Log warning, continue
   - Missing MCP secrets? Log warning, skip that server
   - Plugin already installed? Skip silently
5. **Exit codes**: 0 = success, 1 = critical failure (e.g., Claude CLI not found)

### Example Output

```bash
SETUP_MODE=auto ./setup.sh

→ Auto mode: Installing from config...
  ✓ claude-code-plugins
  ✓ superpowers-marketplace
  ✓ awesome-claude-code-plugins
  ⚠ tanzu-cf-architect (private, skipped: access denied)
  ✓ every-marketplace

→ Installing plugins...
  ✓ superpowers@superpowers-marketplace
  ✓ compound-engineering@every-marketplace
  [... 20 more plugins ...]

✓ Setup complete! 22/23 plugins installed (1 skipped)
```

**Use case**: Clone config repo on new machine, run `SETUP_MODE=auto ./setup.sh`, productive in 2 minutes.

## Configuration File Format

### setup-marketplaces.json (committed, public)

```json
{
  "marketplaces": {
    "claude-code-plugins": {
      "source": "github",
      "repo": "anthropics/claude-code",
      "description": "Official Anthropic plugins",
      "essential": true
    },
    "superpowers-marketplace": {
      "source": "github",
      "repo": "obra/superpowers-marketplace",
      "description": "Productivity toolkit by Jesse Vincent",
      "essential": true
    },
    "awesome-claude-code-plugins": {
      "source": "github",
      "repo": "ccplugins/marketplace",
      "description": "Community contributed plugins"
    },
    "every-marketplace": {
      "source": "git",
      "url": "https://github.com/EveryInc/compound-engineering-plugin.git",
      "description": "Compound Engineering tools"
    },
    "anthropic-agent-skills": {
      "source": "github",
      "repo": "anthropics/skills",
      "description": "Example agent patterns"
    },
    "claude-code-templates": {
      "source": "github",
      "repo": "davila7/claude-code-templates",
      "description": "DevOps and web development templates"
    }
  }
}
```

### setup-marketplaces.local.json (gitignored, private)

```json
{
  "marketplaces": {
    "tanzu-cf-architect": {
      "source": "github",
      "repo": "malston/tanzu-cf-architect-claude-plugin",
      "description": "Private Tanzu/CloudFoundry tools"
    }
  }
}
```

### Merge Strategy

Simple object merge: `.local.json` overwrites duplicates. Marketplaces with `"essential": true` auto-install in Phase 1.

### setup-plugins.json

Similar format, lists plugins to auto-install in auto mode:

```json
{
  "plugins": [
    "superpowers@superpowers-marketplace",
    "compound-engineering@every-marketplace",
    "code-review@claude-code-plugins"
  ]
}
```

## Error Handling & User Feedback

### Graceful Degradation

1. **Missing secrets (MCP servers)**:

   ```
   ⚠ Skipping context7: CONTEXT7_API_KEY not found
     → Set in config/.env or 1Password
     → Re-run ./setup.sh after configuring
   ```

2. **Private repo access denied**:

   ```
   ⚠ Skipping tanzu-cf-architect: repository not found
     → This is a private marketplace
     → Ensure you have access or remove from config
   ```

3. **Marketplace already added**:

   ```
   ✓ superpowers-marketplace (already added)
   ```

4. **Plugin installation failures**:

   ```
   ✗ some-plugin@broken-marketplace failed
     → Check 'claude plugin list broken-marketplace'
     → Report issue to marketplace maintainer
   ```

### Summary Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Setup Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ Marketplaces: 5/6 installed (1 skipped)
✓ Plugins: 22/23 installed (1 failed)
⚠ MCP Servers: 2/3 configured (1 missing secrets)

Next steps:
  • Configure missing secrets in config/.env
  • Browse plugins: claude plugin list <marketplace>
  • Read CLAUDE.md for usage tips
```

## Documentation Structure

### README.md Sections

1. **Quick Start** (newcomers):

   ```markdown
   ## Quick Start

   ```bash
   git clone https://github.com/malston/claude-config.git ~/.claude
   cd ~/.claude
   ./setup.sh
   ```

   Answer a few questions and you'll have a working setup in 2 minutes.

   ```

2. **Power User Setup**:

   ```markdown
   ## Power User Setup

   On a new machine with your private config fork:

   ```bash
   git clone YOUR_FORK ~/.claude
   cd ~/.claude
   SETUP_MODE=auto ./setup.sh
   ```

   Installs your complete config including private marketplaces.

   ```

3. **Adding Private Marketplaces**:

   ```markdown
   ## Customization

   Create `plugins/setup-marketplaces.local.json`:

   ```json
   {
     "marketplaces": {
       "your-private-marketplace": {
         "source": "github",
         "repo": "you/your-repo",
         "description": "Your private tools"
       }
     }
   }
   ```

   This file is gitignored and won't be committed, even in your fork.

   ```

4. **Attribution**:

   ```markdown
   ## Credits

   - Superpowers marketplace by Jesse Vincent (https://blog.fsck.com)
   - CLAUDE.md workflow inspired by Jesse's work
   - Setup patterns from the Claude Code community
   ```

## Implementation Notes

### Merging .local.json Files

```python
def load_config(base_file, local_file):
    with open(base_file) as f:
        config = json.load(f)
    if os.path.exists(local_file):
        with open(local_file) as f:
            local = json.load(f)
        # Merge marketplaces, local overwrites duplicates
        config['marketplaces'].update(local['marketplaces'])
    return config
```

### Interactive Marketplace Selector

- Use Python's built-in input for simplicity (avoid external dependencies)
- Multi-select with space bar if using `inquirer` library
- Fallback to simple numbered list if keeping it dependency-free

### Updating .gitignore

```
# Add to .gitignore
plugins/*.local.json
plugins/known_marketplaces.json
# plugins/installed_plugins.json already gitignored
```

### Migration from Current Setup

First run after deploying this design:

1. Detect if `setup-marketplaces.json` doesn't exist
2. Copy `known_marketplaces.json` → `setup-marketplaces.json`
3. Prompt: "Migrating to new config format..."
4. Keep seamless for existing users

### Testing Strategy

- Test in fresh VM/container for newcomer experience
- Verify interactive prompts work correctly
- Test auto mode with mix of public/private repos
- Test graceful failures (missing repos, missing secrets)
- Verify .local.json merging works correctly

## Success Criteria

1. ✅ Newcomer can clone and run `./setup.sh`, get working setup in under 2 minutes
2. ✅ Power user can run `SETUP_MODE=auto ./setup.sh` on new machine, get complete config
3. ✅ Private marketplaces work for power users, gracefully skipped for newcomers
4. ✅ Documentation is clear enough that users don't need to ask Mark how it works
5. ✅ Proper attribution to Jesse Vincent and community contributors

## Future Enhancements (Not in Scope)

- Web UI for browsing marketplaces/plugins
- Plugin recommendation engine based on usage patterns
- Automated testing in CI for setup.sh
- Support for plugin profiles/bundles beyond essentials
