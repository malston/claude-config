#!/bin/bash
# ABOUTME: Docker entrypoint that runs setup on first start, then executes the command.
# ABOUTME: Tracks setup completion with a marker file to avoid re-running.

set -e

MARKER_FILE="$HOME/.claude-setup-complete"

# Run setup if not already done
if [ ! -f "$MARKER_FILE" ]; then
    echo "First run detected - running setup..."
    echo ""

    cd ~/.claude
    SETUP_MODE=auto ./setup.sh

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
