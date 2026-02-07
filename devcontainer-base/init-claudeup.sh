#!/usr/bin/env bash
# ABOUTME: Installs claudeup and applies the specified profile.
# ABOUTME: Reads CLAUDE_PROFILE and CLAUDE_BASE_PROFILE env vars.

set -euo pipefail

CLAUDEUP_HOME="/home/node/.claudeup"
CLAUDE_HOME="/home/node/.claude"
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

# Apply base profile first (if provided) to install its marketplaces and plugins
if [ -n "${CLAUDE_BASE_PROFILE:-}" ]; then
    echo "Applying base profile: $CLAUDE_BASE_PROFILE..."
    if claudeup profile apply "$CLAUDE_BASE_PROFILE" -y; then
        echo "[OK] Base profile '$CLAUDE_BASE_PROFILE' applied"
    else
        echo "[WARN] Base profile apply failed, will retry on next container start"
        exit 1
    fi
    # Capture base profile's enabledPlugins before they get replaced
    base_plugins=$(jq '.enabledPlugins // {}' "$CLAUDE_HOME/settings.json")
fi

echo "Applying profile: $CLAUDE_PROFILE..."
if claudeup profile apply "$CLAUDE_PROFILE" -y; then
    echo "[OK] Profile '$CLAUDE_PROFILE' applied"
else
    echo "[WARN] claudeup profile apply failed, will retry on next container start"
    exit 1
fi

# Merge base profile's enabledPlugins back so both sets of plugins are active
if [ -n "${base_plugins:-}" ] && [ "$base_plugins" != "{}" ]; then
    local_settings="$CLAUDE_HOME/settings.json"
    jq --argjson base "$base_plugins" '.enabledPlugins = ($base + .enabledPlugins)' "$local_settings" > "${local_settings}.tmp"
    mv "${local_settings}.tmp" "$local_settings"
    echo "[OK] Base profile enabledPlugins merged"
fi

touch "$MARKER_FILE"

echo "Claudeup initialization complete"
