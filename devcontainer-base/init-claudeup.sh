#!/usr/bin/env bash
# ABOUTME: Installs claudeup and applies the specified profile.
# ABOUTME: Reads CLAUDE_PROFILE env var for the profile name.

set -euo pipefail

CLAUDEUP_HOME="/home/node/.claudeup"
MARKER_FILE="$CLAUDEUP_HOME/.setup-complete"

echo "Initializing claudeup..."

if [ -f "$MARKER_FILE" ]; then
    echo "[SKIP] Claudeup setup already complete"
    exit 0
fi

if [ -z "${CLAUDE_PROFILE:-}" ]; then
    echo "[WARN] CLAUDE_PROFILE not set, skipping profile setup"
    exit 0
fi

mkdir -p "$CLAUDEUP_HOME/profiles"

if ! command -v claudeup &> /dev/null; then
    echo "Installing claudeup..."
    curl -fsSL https://raw.githubusercontent.com/claudeup/claudeup/main/install.sh | bash
    export PATH="$HOME/.local/bin:$PATH"
    echo "[OK] claudeup installed"
else
    echo "[SKIP] claudeup already installed"
fi

echo "Applying profile: $CLAUDE_PROFILE..."
if claudeup setup --profile "$CLAUDE_PROFILE" -y; then
    echo "[OK] Profile '$CLAUDE_PROFILE' applied"
    touch "$MARKER_FILE"
else
    echo "[WARN] claudeup setup failed, will retry on next container start"
    exit 1
fi

echo "Claudeup initialization complete"
