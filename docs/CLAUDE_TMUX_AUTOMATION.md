# Claude Code CLI Automation (TMUX)

A collection of bash scripts to automate Claude Code CLI commands via tmux, with structured output parsing.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Scripts](#scripts)
  - [run-claude-command.sh](#run-claude-commandsh)
  - [parse-claude-output.sh](#parse-claude-outputsh)
- [Usage Examples](#usage-examples)
- [Integration Examples](#integration-examples)
- [Troubleshooting](#troubleshooting)
- [tmux Configuration](#tmux-configuration)

## Overview

These scripts enable you to:

- Run Claude Code CLI commands in detached tmux sessions
- Capture command output programmatically
- Parse structured data (JSON, YAML, env vars)
- Integrate Claude Code into automation workflows

## Prerequisites

- **tmux** 3.6a or later
- **Claude Code** CLI (`claude`) installed via mise or pnpm
- **jq** for JSON parsing (optional but recommended)
- **bash** 4.0+

### Install Prerequisites

```bash
# Install tmux (macOS)
brew install tmux

# Install jq
brew install jq

# Verify versions
tmux -V        # Should be 3.6a or later
claude --version  # Should be 2.1.12 or later
```

## Installation

1. Create the scripts directory:

```bash
mkdir -p ~/.claude/scripts
```

1. Create the scripts (see [Scripts](#scripts) section below)

2. Make them executable:

```bash
chmod +x ~/.claude/scripts/{run-claude-command.sh,parse-claude-output.sh}
```

## Scripts

### run-claude-command.sh

Executes Claude Code commands in a tmux session and captures output.

**Location:** `~/.claude/scripts/run-claude-command.sh`

```bash
#!/usr/bin/env bash
# .claude/scripts/run-claude-command.sh
# Executes Claude Code commands in tmux

set -euo pipefail

COMMAND="${1:-/help}"
SESSION_NAME="${2:-claude-cmd-$$}"
KEEP_ALIVE="${3:-false}"
TIMEOUT=60

# Create session with full PATH
tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
tmux new-session -d -s "$SESSION_NAME" "export PATH='$PATH' && exec \$SHELL"
sleep 1

# Start Claude with permission bypass
echo "Starting Claude..." >&2
tmux send-keys -t "$SESSION_NAME" 'claude --dangerously-skip-permissions' Enter

# Wait for Claude prompt
echo "Waiting for Claude prompt..." >&2
for i in {1..30}; do
    if tmux capture-pane -t "$SESSION_NAME" -p | grep -q "cluster01\|main"; then
        echo "Claude ready!" >&2
        break
    fi
    sleep 1
done

sleep 2

# Clear screen and history
tmux send-keys -t "$SESSION_NAME" C-l
sleep 0.5
tmux clear-history -t "$SESSION_NAME"
sleep 0.5

# Send command
echo "Sending: $COMMAND" >&2
tmux send-keys -t "$SESSION_NAME" "$COMMAND" Enter

# Wait for completion
echo "Waiting for completion..." >&2
for i in $(seq 1 "$TIMEOUT"); do
    pane=$(tmux capture-pane -t "$SESSION_NAME" -p)

    # Done when no spinner and prompt is back
    if ! echo "$pane" | grep -q "∙" && echo "$pane" | grep -q "❯"; then
        echo "Completed after ${i}s!" >&2
        sleep 2
        break
    fi

    if (( i % 10 == 0 )); then
        echo "Still waiting... (${i}/${TIMEOUT}s)" >&2
    fi
    sleep 1
done

# Capture output
tmux capture-pane -t "$SESSION_NAME" -p -S -100

# Cleanup or keep alive
if [[ "$KEEP_ALIVE" == "true" ]]; then
    echo "" >&2
    echo "Session: tmux attach -t $SESSION_NAME" >&2
else
    tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
fi
```

**Usage:**

```bash
# Run a command (auto-cleanup)
.claude/scripts/run-claude-command.sh /context

# Keep session alive for inspection
.claude/scripts/run-claude-command.sh /context my-session true

# Custom session name
.claude/scripts/run-claude-command.sh /help debug-session
```

### parse-claude-output.sh

Parses Claude Code command output into structured formats.

**Location:** `~/.claude/scripts/parse-claude-output.sh`

```bash
#!/usr/bin/env bash
# .claude/scripts/parse-claude-output.sh
# Parses Claude Code output into structured data

set -euo pipefail

COMMAND="${1:-/context}"
FORMAT="${2:-json}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get raw output
RAW_OUTPUT=$("$SCRIPT_DIR/run-claude-command.sh" "$COMMAND" 2>&1)

# Filter out script messages
FILTERED_OUTPUT=$(echo "$RAW_OUTPUT" | grep -v "^Starting\|^Waiting\|^Sending\|^Completed\|^Session:\|^Claude ready!")

parse_context() {
    local output="$1"

    # Extract model and plan
    MODEL=$(echo "$output" | grep -oE '(Opus|Sonnet|Haiku) [0-9.]+' | head -1 || echo "")
    PLAN=$(echo "$output" | grep -oE 'Claude (Max|Pro|Free)' | sed 's/Claude //' | head -1 || echo "")
    [[ -z "$PLAN" ]] && PLAN=$(echo "$output" | grep -oE '\| (Max|Pro|Free)\]' | grep -oE 'Max|Pro|Free' | head -1 || echo "")
    USERNAME=$(echo "$output" | grep -E '^\s*[a-zA-Z0-9_-]+\s*$' | tr -d '[:space:]' | head -1 || echo "")

    # Parse stats - strip leading spaces and handle plurals
    STATS_LINE=$(echo "$output" | grep -E 'CLAUDE\.md.*MCP.*hook' | sed 's/^[[:space:]]*//' || echo "")

    # Extract numbers
    CLAUDE_MD=$(echo "$STATS_LINE" | grep -oE '[0-9]+[[:space:]]+CLAUDE\.md' | grep -oE '[0-9]+' || echo "0")
    MCPS=$(echo "$STATS_LINE" | grep -oE '[0-9]+[[:space:]]+MCPs?' | grep -oE '[0-9]+' || echo "0")
    HOOKS=$(echo "$STATS_LINE" | grep -oE '[0-9]+[[:space:]]+hooks?' | grep -oE '[0-9]+' || echo "0")

    # Parse usage
    USAGE_LINE=$(echo "$output" | grep -E '[0-9]+h:.*[0-9]+%' || echo "")
    TIME_LIMIT=$(echo "$USAGE_LINE" | grep -oE '[0-9]+h' | head -1 | grep -oE '[0-9]+' || echo "0")
    USAGE_PERCENT=$(echo "$output" | grep -oE '[0-9]+%' | head -1 | grep -oE '[0-9]+' || echo "0")

    # Time remaining
    TIME_REMAINING=$(echo "$output" | grep -oE '\([0-9]+h[[:space:]]+[0-9]+m\)' | tr -d '()' || echo "unknown")

    case "$FORMAT" in
        json)
            cat << EOF
{
  "command": "/context",
  "model": "${MODEL:-unknown}",
  "plan": "${PLAN:-unknown}",
  "username": "${USERNAME:-unknown}",
  "stats": {
    "claude_md_files": ${CLAUDE_MD},
    "mcps": ${MCPS},
    "hooks": ${HOOKS}
  },
  "usage": {
    "time_limit_hours": ${TIME_LIMIT},
    "percent_used": ${USAGE_PERCENT},
    "time_remaining": "${TIME_REMAINING}"
  }
}
EOF
            ;;
        yaml)
            cat << EOF
command: /context
model: ${MODEL:-unknown}
plan: ${PLAN:-unknown}
username: ${USERNAME:-unknown}
stats:
  claude_md_files: ${CLAUDE_MD}
  mcps: ${MCPS}
  hooks: ${HOOKS}
usage:
  time_limit_hours: ${TIME_LIMIT}
  percent_used: ${USAGE_PERCENT}
  time_remaining: ${TIME_REMAINING}
EOF
            ;;
        env)
            cat << EOF
CLAUDE_MODEL="${MODEL:-unknown}"
CLAUDE_PLAN="${PLAN:-unknown}"
CLAUDE_USERNAME="${USERNAME:-unknown}"
CLAUDE_MD_FILES=${CLAUDE_MD}
CLAUDE_MCPS=${MCPS}
CLAUDE_HOOKS=${HOOKS}
CLAUDE_TIME_LIMIT=${TIME_LIMIT}
CLAUDE_USAGE_PERCENT=${USAGE_PERCENT}
CLAUDE_TIME_REMAINING="${TIME_REMAINING}"
EOF
            ;;
        raw)
            echo "$FILTERED_OUTPUT"
            ;;
    esac
}

case "$COMMAND" in
    /context)
        parse_context "$FILTERED_OUTPUT"
        ;;
    *)
        echo "$FILTERED_OUTPUT"
        ;;
esac
```

**Usage:**

```bash
# JSON output
.claude/scripts/parse-claude-output.sh /context json | jq .

# Environment variables
.claude/scripts/parse-claude-output.sh /context env

# YAML format
.claude/scripts/parse-claude-output.sh /context yaml

# Raw output
.claude/scripts/parse-claude-output.sh /context raw
```

## Usage Examples

### Basic Command Execution

```bash
# Get Claude context
.claude/scripts/run-claude-command.sh /context

# List available commands
.claude/scripts/run-claude-command.sh /help

# Show available tools
.claude/scripts/run-claude-command.sh /mcp

# List skills
.claude/scripts/run-claude-command.sh /skills
```

### Parsed Output

```bash
# Get structured JSON
.claude/scripts/parse-claude-output.sh /context json

# Example output:
{
  "command": "/context",
  "model": "Opus 4.5",
  "plan": "Max",
  "username": "markalston",
  "stats": {
    "claude_md_files": 3,
    "mcps": 1,
    "hooks": 6
  },
  "usage": {
    "time_limit_hours": 5,
    "percent_used": 23,
    "time_remaining": "3h 14m"
  }
}
```

### Query Specific Values

```bash
# Get usage percentage
.claude/scripts/parse-claude-output.sh /context json | jq -r '.usage.percent_used'
# Output: 23

# Get time remaining
.claude/scripts/parse-claude-output.sh /context json | jq -r '.usage.time_remaining'
# Output: 3h 14m

# Get model
.claude/scripts/parse-claude-output.sh /context json | jq -r '.model'
# Output: Opus 4.5

# Get all stats
.claude/scripts/parse-claude-output.sh /context json | jq '.stats'
```

## Integration Examples

### 1. Load as Environment Variables

```bash
#!/usr/bin/env bash
# Load Claude context into environment

eval $(.claude/scripts/parse-claude-output.sh /context env)

echo "Model: $CLAUDE_MODEL"
echo "Plan: $CLAUDE_PLAN"
echo "Usage: $CLAUDE_USAGE_PERCENT% ($CLAUDE_TIME_REMAINING remaining)"
echo "Files: $CLAUDE_MD_FILES CLAUDE.md, $CLAUDE_MCPS MCPs, $CLAUDE_HOOKS hooks"
```

### 2. Usage Monitoring Script

```bash
#!/usr/bin/env bash
# ~/.claude/scripts/check-usage.sh
# Monitor Claude usage and warn at thresholds

USAGE=$(.claude/scripts/parse-claude-output.sh /context json | jq -r '.usage.percent_used')

if (( USAGE >= 90 )); then
    echo "⚠️  WARNING: Claude usage at ${USAGE}%!"
elif (( USAGE >= 75 )); then
    echo "⚡ Claude usage at ${USAGE}%"
else
    echo "✅ Claude usage: ${USAGE}%"
fi
```

### 3. Status Dashboard

```bash
#!/usr/bin/env bash
# ~/.claude/scripts/claude-dashboard.sh
# Display comprehensive Claude status

DATA=$(.claude/scripts/parse-claude-output.sh /context json)

cat << EOF
╭─── Claude Code Status ────────────────────────────╮
│ Model:      $(echo "$DATA" | jq -r '.model')
│ Plan:       $(echo "$DATA" | jq -r '.plan')
│ User:       $(echo "$DATA" | jq -r '.username')
├───────────────────────────────────────────────────┤
│ Files:      $(echo "$DATA" | jq -r '.stats.claude_md_files') CLAUDE.md
│ MCPs:       $(echo "$DATA" | jq -r '.stats.mcps')
│ Hooks:      $(echo "$DATA" | jq -r '.stats.hooks')
├───────────────────────────────────────────────────┤
│ Time Limit: $(echo "$DATA" | jq -r '.usage.time_limit_hours') hours
│ Used:       $(echo "$DATA" | jq -r '.usage.percent_used')%
│ Remaining:  $(echo "$DATA" | jq -r '.usage.time_remaining')
╰───────────────────────────────────────────────────╯
EOF
```

Make it executable and run:

```bash
chmod +x ~/.claude/scripts/claude-dashboard.sh
~/.claude/scripts/claude-dashboard.sh
```

### 4. Save to File

```bash
# Save JSON output
.claude/scripts/parse-claude-output.sh /context json > claude-status.json

# Save with timestamp
.claude/scripts/parse-claude-output.sh /context json > "claude-status-$(date +%Y%m%d-%H%M%S).json"

# Log usage over time
echo "$(date +%Y-%m-%d-%H:%M:%S),$(.claude/scripts/parse-claude-output.sh /context json | jq -r '.usage.percent_used')" >> usage.log
```

### 5. Conditional Script Execution

```bash
#!/usr/bin/env bash
# Only run expensive operations if usage is low

USAGE=$(.claude/scripts/parse-claude-output.sh /context json | jq -r '.usage.percent_used')

if (( USAGE < 80 )); then
    echo "Running batch analysis..."
    # Your expensive Claude operations here
else
    echo "Skipping - usage too high (${USAGE}%)"
fi
```

## Troubleshooting

### Claude not found in PATH

If you see `command not found: claude`, ensure Claude is properly installed:

```bash
# Check if claude is in PATH
which claude

# Should show:
# /Users/yourusername/.local/share/mise/installs/node/XX.X.X/bin/claude

# If not found, check mise
mise where claude

# Or reinstall
pnpm add -g @anthropic-ai/claude-code
```

### tmux Configuration Issues

If you get "invalid option" errors, your tmux.conf may be outdated. See the [tmux Configuration](#tmux-configuration) section.

### Permission Prompts

The scripts use `--dangerously-skip-permissions` to bypass interactive prompts. If you want to be prompted, edit `run-claude-command.sh` and remove this flag.

### Parsing Returns Zeros

If stats show as 0, check the raw output:

```bash
.claude/scripts/parse-claude-output.sh /context raw
```

This will show the unfiltered output for debugging.

### Script Hangs

If scripts hang, increase the timeout:

Edit `run-claude-command.sh` and change:

```bash
TIMEOUT=60  # Increase to 120 or more
```

### Debug Mode

Run with bash debug mode:

```bash
bash -x .claude/scripts/run-claude-command.sh /context
```

## tmux Configuration

### Recommended tmux.conf

For modern tmux (3.6a+), use this configuration:

**Location:** `~/.tmux.conf`

```bash
# Use zsh (or your preferred shell)
set-option -g default-shell "/bin/zsh"
set-option -g default-command "/bin/zsh -l"

# Modern terminal settings
set-option -g default-terminal "tmux-256color"
set-option -sa terminal-overrides ",xterm*:Tc"

# Key bindings
set -g prefix C-b
bind C-b send-prefix

# Escape time for neovim
set-option -sg escape-time 10

# Mouse support
set -g mouse on

# Status line
set -g status-right "%H:%M"
set -g window-status-current-style "underscore"

# Vi mode
set -g mode-keys vi

# Copy to clipboard (macOS)
bind-key -T copy-mode-vi 'y' send -X copy-pipe-and-cancel "pbcopy"

# Reload config
bind r source-file ~/.tmux.conf \; display "Reloaded!"

# Split windows
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# Vim-style pane navigation
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Pane resizing
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# Window/pane settings
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g history-limit 20000

# Colors (modern syntax)
set -g pane-border-style fg=blue
set -g pane-active-border-style fg=blue
set -g message-style bg=yellow,fg=black,bold
set -g status-style bg=default,fg=default
```

Apply changes:

```bash
tmux source-file ~/.tmux.conf
# Or restart tmux
tmux kill-server && tmux
```

## Advanced Usage

### Chaining Multiple Commands

```bash
#!/usr/bin/env bash
# Run multiple commands in sequence

COMMANDS=("/context" "/help" "/tools")

for cmd in "${COMMANDS[@]}"; do
    echo "Running: $cmd"
    .claude/scripts/parse-claude-output.sh "$cmd" json > "${cmd//\//_}.json"
done
```

### Parallel Execution

```bash
#!/usr/bin/env bash
# Run commands in parallel (careful with rate limits)

.claude/scripts/run-claude-command.sh /context context-session &
.claude/scripts/run-claude-command.sh /help help-session &
.claude/scripts/run-claude-command.sh /tools tools-session &

wait
echo "All commands completed"
```

### Cron Job for Usage Tracking

```bash
# Add to crontab: crontab -e
# Run every hour
0 * * * * /Users/yourusername/.claude/scripts/parse-claude-output.sh /context json >> /Users/yourusername/claude-usage.log
```

## Available Commands

Common Claude Code CLI commands (check `/help` for full list):

- `/context` - Show current context, usage, and stats
- `/help` - List available commands
- `/tools` - Show available tools
- `/skills` - List available skills
- `/settings` - Show settings
- `/status` - Show status

## Tips & Best Practices

1. **Always check usage before batch operations**

   ```bash
   USAGE=$(.claude/scripts/parse-claude-output.sh /context json | jq -r '.usage.percent_used')
   ```

2. **Use session names for debugging**

   ```bash
   .claude/scripts/run-claude-command.sh /context debug-session true
   tmux attach -t debug-session
   ```

3. **Save outputs for auditing**

   ```bash
   .claude/scripts/parse-claude-output.sh /context json | \
     tee "logs/claude-$(date +%Y%m%d).json" | jq .
   ```

4. **Create aliases for common operations**

   ```bash
   # Add to ~/.zshrc
   alias claude-status='.claude/scripts/parse-claude-output.sh /context json | jq .'
   alias claude-usage='.claude/scripts/parse-claude-output.sh /context json | jq -r .usage'
   ```

## License

These scripts are provided as-is for personal use.

---

**Questions or Issues?** Check the [Troubleshooting](#troubleshooting) section or review the tmux debug output with `bash -x`.
