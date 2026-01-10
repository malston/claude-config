#!/bin/bash
# ABOUTME: Automatically check and update Claude Code plugins and marketplaces
# ABOUTME: Called by .envrc when entering the directory

set -e

BLUE='\033[38;2;6;176;204m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAST_CHECK_FILE="$SCRIPT_DIR/../.last_plugin_check"

# Parse arguments
FORCE=false
if [ "$1" = "--force" ]; then
    FORCE=true
fi

# Check if we've already run today (unless --force)
if [ "$FORCE" = false ] && [ -f "$LAST_CHECK_FILE" ]; then
    LAST_CHECK=$(cat "$LAST_CHECK_FILE")
    TODAY=$(date +%Y-%m-%d)

    if [ "$LAST_CHECK" = "$TODAY" ]; then
        exit 0
    fi
fi

# Display current settings
printf "\n${BLUE}ℹ %s${NC}\n" "Displaying Claude Code user settings..."
"$SCRIPT_DIR"/claude-config list -e

printf "\n${BLUE}ℹ %s${NC}\n" "Checking for plugin/marketplace updates..."

# Use claudeup to check and prompt for updates
claudeup update
claudeup upgrade

# Mark as checked today
date +%Y-%m-%d > "$LAST_CHECK_FILE"
