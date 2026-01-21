#!/usr/bin/env bash
# ABOUTME: PreToolUse hook that logs all Bash commands to an audit file.
# ABOUTME: Useful for debugging and reviewing what Claude executed.

set -uo pipefail

LOG_FILE="$HOME/.claude/bash-command-log.txt"

# Read JSON input from stdin
input=$(cat)

# Extract command and description from tool_input
command=$(echo "$input" | jq -r '.tool_input.command // "unknown"' 2>/dev/null)
description=$(echo "$input" | jq -r '.tool_input.description // "No description"' 2>/dev/null)

# Get timestamp
timestamp=$(date '+%Y-%m-%d %H:%M:%S')

# Log to file
echo "[$timestamp] $command - $description" >> "$LOG_FILE"

# Always allow (exit 0)
exit 0
