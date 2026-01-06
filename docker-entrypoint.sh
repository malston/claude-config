#!/usr/bin/env bash
# ABOUTME: Docker entrypoint that runs setup on first start, then executes the command.
# ABOUTME: Tracks setup completion with a marker file to avoid re-running.

set -e

# Use persistent state directory if available, otherwise fall back to home
STATE_DIR="$HOME/.claude-state"
if [ -d "$STATE_DIR" ]; then
    MARKER_FILE="$STATE_DIR/.setup-complete"
else
    MARKER_FILE="$HOME/.claude-setup-complete"
fi

# Run setup if not already done
if [ ! -f "$MARKER_FILE" ]; then
    echo "First run detected - running setup..."
    echo ""

    # Install plugins via claudeup profile (skip prompts)
    claudeup setup --profile docker -y

    # Create marker file
    touch "$MARKER_FILE"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi

# Execute the provided command, or start claude if none given
if [ $# -eq 0 ]; then
    exec claude --dangerously-skip-permissions
else
    exec "$@"
fi
