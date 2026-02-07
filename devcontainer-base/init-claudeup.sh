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
if claudeup profile apply "$CLAUDE_PROFILE" -y; then
    echo "[OK] Profile '$CLAUDE_PROFILE' applied"
else
    echo "[WARN] claudeup profile apply failed, will retry on next container start"
    exit 1
fi

# In additive mode, merge base enabledPlugins back into settings.json
# so the profile's plugins are added on top of the base rather than replacing them
if [ "${CLAUDE_ADDITIVE_PROFILE:-}" = "true" ] && [ -f /tmp/base-settings.json ]; then
    CLAUDE_HOME="/home/node/.claude"
    local_settings="$CLAUDE_HOME/settings.json"
    base_plugins=$(jq -r '.enabledPlugins // {}' /tmp/base-settings.json)
    if [ "$base_plugins" != "{}" ]; then
        jq --argjson base "$base_plugins" '.enabledPlugins = ($base + .enabledPlugins)' "$local_settings" > "${local_settings}.tmp"
        mv "${local_settings}.tmp" "$local_settings"
        echo "[OK] Base enabledPlugins merged (additive mode)"
    fi
fi

touch "$MARKER_FILE"

echo "Claudeup initialization complete"
