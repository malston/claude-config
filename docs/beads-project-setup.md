# Beads Project Setup Guide

How to initialize [beads](https://github.com/claudeup/beads) (`bd`) for issue tracking in a new or existing project.

## Prerequisites

- `bd` installed and on `$PATH`
- `gh` (GitHub CLI) -- only needed for brownfield import
- `jq` -- only needed for brownfield import

## Greenfield Project (no existing issues)

```bash
cd /path/to/project
bd init
bd setup claude --project
```

**What each command does:**

1. `bd init` -- creates `.beads/` directory with an embedded Dolt database. Auto-detects the issue prefix from the directory name (e.g., `myapp` produces issues like `myapp-a3f2dd`).
2. `bd setup claude --project` -- injects beads workflow instructions into your project-level Claude Code settings so `bd prime` fires at session start and pre-compact.

Then create your first issue:

```bash
bd create "First task" -p 1 -t task
bd ready   # confirm it appears
```

### Common `bd init` flags

| Flag            | Purpose                                                          |
| --------------- | ---------------------------------------------------------------- |
| `--prefix api`  | Custom issue prefix instead of directory name                    |
| `--stealth`     | Hide beads from git (personal use on shared repos)               |
| `--skip-hooks`  | Don't install git hooks                                          |
| `--skip-agents` | Don't generate AGENTS.md (use when `bd setup claude` handles it) |
| `--contributor` | OSS fork workflow -- stores issues in `~/.beads-planning/`       |
| `--team`        | Team workflow setup wizard                                       |

## Brownfield Project (importing from GitHub Issues)

```bash
cd /path/to/project
bd init
bd setup claude --project
~/.claude/scripts/gh-to-beads.sh owner/repo [options]
```

The first two commands are identical to greenfield. The third imports existing GitHub Issues into beads using the helper script.

### What gets preserved

All GitHub labels are carried over as beads labels, plus `github-import` is appended for easy filtering. The default type mapping (`bug` -> bug, `enhancement`/`feature` -> feature, everything else -> task) works for most repos. Use `--type-map` and `--priority-map` only if your repo uses non-standard label names (e.g., `defect` instead of `bug`).

### Import options

| Option                     | Default | Purpose                                       |
| -------------------------- | ------- | --------------------------------------------- |
| `--dry-run`                | --      | Preview what would be imported                |
| `--default-priority N`     | 2       | Fallback priority (0-4, 0 = highest)          |
| `--state STATE`            | open    | Which issues: `open`, `closed`, `all`         |
| `--limit N`                | 500     | Max issues to fetch                           |
| `--type-map label=type`    | --      | Map GitHub labels to beads types (repeatable) |
| `--priority-map label=pri` | --      | Map GitHub labels to priorities (repeatable)  |

### Example: importing claudeup issues

```bash
cd ~/code/claudeup
bd init
bd setup claude --project
~/.claude/scripts/gh-to-beads.sh claudeup/claudeup --default-priority 3
```

### After import

GitHub Issues are flat -- they don't carry dependency information. Wire up dependencies manually:

```bash
bd list --label github-import    # see what came in
bd dep add <issue> <depends-on>  # add dependency relationships
bd ready                         # see what's unblocked
```

## Post-Setup (both flows)

### Store project facts

Persistent memories are injected into every session via `bd prime`:

```bash
bd remember "always run tests with -race flag" --key go-race
bd remember "auth module uses JWT not sessions" --key auth-jwt
```

### Verify setup

```bash
bd doctor    # check database health
bd status    # overview of issue counts
bd prime     # preview what gets injected at session start
```

### Quick reference

```bash
bd quickstart   # print the full command reference guide
bd human        # show essential commands for human users
```
