#!/usr/bin/env bash
# ABOUTME: Cleans Claude Code session history for a project to fix freezing issues.
# ABOUTME: Usage: clean-session-history.sh [project-path] or no args for current directory.

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"

# Get project path from arg or use current directory
if [[ $# -ge 1 ]]; then
    PROJECT_PATH="$(cd "$1" && pwd)"
else
    PROJECT_PATH="$(pwd)"
fi

# Convert path to Claude's project directory format (slashes become dashes)
PROJECT_DIR_NAME=$(echo "$PROJECT_PATH" | sed 's|^/||' | sed 's|/|-|g')
PROJECT_DIR_NAME="-${PROJECT_DIR_NAME}"

SESSIONS_DIR="$CLAUDE_DIR/projects/$PROJECT_DIR_NAME"

if [[ ! -d "$SESSIONS_DIR" ]]; then
    echo "No session history found for: $PROJECT_PATH"
    echo "Expected directory: $SESSIONS_DIR"
    exit 0
fi

# Show what we're about to delete
echo "Project: $PROJECT_PATH"
echo "Session directory: $SESSIONS_DIR"
echo ""

# Count files and size
file_count=$(find "$SESSIONS_DIR" -type f | wc -l | tr -d ' ')
dir_size=$(du -sh "$SESSIONS_DIR" | cut -f1)

echo "Files: $file_count"
echo "Size: $dir_size"
echo ""

# Confirm unless -f flag
if [[ "${1:-}" != "-f" && "${2:-}" != "-f" ]]; then
    read -p "Delete session history? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
fi

rm -rf "$SESSIONS_DIR"
echo "Removed session history for $PROJECT_PATH"
