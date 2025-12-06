#!/bin/bash
# ABOUTME: Automatically upgrade Claude Code and display changelog
# ABOUTME: Called by .envrc when entering the directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAST_CHECK_FILE="$SCRIPT_DIR/../.last_brew_check"

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
        # Already checked today, skip
        exit 0
    fi
fi

echo "Checking for Claude Code updates..."

# Get current version before upgrading
OLD_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

# Run the upgrade
UPGRADE_OUTPUT=$(brew upgrade --cask claude-code 2>&1)

# Get new version after upgrading
NEW_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

# Check if version changed
if [ -n "$OLD_VERSION" ] && [ -n "$NEW_VERSION" ] && [ "$OLD_VERSION" != "$NEW_VERSION" ]; then
    echo ""
    echo "✨ Claude Code upgraded: $OLD_VERSION → $NEW_VERSION"
    echo ""
    echo "Fetching changelog..."

    # Fetch and parse CHANGELOG.md using Python
    CHANGELOG_URL="https://raw.githubusercontent.com/anthropics/claude-code/refs/heads/main/CHANGELOG.md"
    VERSION_CHANGES=$(curl -sL "$CHANGELOG_URL" | python3 -c "
import sys, re
version = '${NEW_VERSION}'
changelog = sys.stdin.read()
sections = re.split(r'^## ', changelog, flags=re.MULTILINE)
for section in sections:
    if section.startswith(version):
        print(f'## {section.split(chr(10) + chr(10) + \"## \")[0].strip()}')
        break
")

    if [ -n "$VERSION_CHANGES" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "$VERSION_CHANGES"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
        echo "Full changelog: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md"
    fi
elif echo "$UPGRADE_OUTPUT" | grep -q "is already installed"; then
    echo "Claude Code is up to date ($OLD_VERSION)"
fi

# Update claude-pm tool itself
echo "Checking for claude-pm updates..."
CLAUDE_PM_CURRENT=$("$HOME/.local/bin/claude-pm" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "0.0.0")

# Get latest version from GitHub
CLAUDE_PM_LATEST=$(curl -sL https://api.github.com/repos/malston/claude-pm/releases/latest |
    python3 -c "import sys, json; print(json.load(sys.stdin)['tag_name'].lstrip('v'))")

if [ "$CLAUDE_PM_CURRENT" != "$CLAUDE_PM_LATEST" ]; then
    echo "Upgrading claude-pm: $CLAUDE_PM_CURRENT → $CLAUDE_PM_LATEST"

    # Download and install new version
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    [[ $ARCH == "x86_64" ]] && ARCH="amd64" || ARCH="arm64"

    curl -L -o "$HOME/.local/bin/claude-pm" \
        "https://github.com/malston/claude-pm/releases/latest/download/claude-pm-${OS}-${ARCH}"
    chmod +x "$HOME/.local/bin/claude-pm"
    echo "✓ claude-pm upgraded"
else
    echo "claude-pm is up to date ($CLAUDE_PM_CURRENT)"
fi

# Mark as checked today
date +%Y-%m-%d > "$LAST_CHECK_FILE"
