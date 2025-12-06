#!/usr/bin/env bash
# ABOUTME: Fixes incorrect plugin paths in installed_plugins.json by adding missing /plugins/ subdirectory
# ABOUTME: Workaround for Claude CLI bug where isLocal plugins have incorrect paths

set -euo pipefail

PLUGINS_FILE="${HOME}/.claude/plugins/installed_plugins.json"
BACKUP_FILE="${HOME}/.claude/plugins/installed_plugins.json.backup"

# Backup first
cp "$PLUGINS_FILE" "$BACKUP_FILE"
echo "✓ Backed up to: $BACKUP_FILE"

# Fix paths for marketplaces with plugins/ subdirectory
jq '
.plugins |= with_entries(
  if .value.isLocal == true then
    .value.installPath |=
      # Fix claude-code-plugins
      if test("/marketplaces/claude-code-plugins/[^/]+$") then
        sub("/marketplaces/claude-code-plugins/"; "/marketplaces/claude-code-plugins/plugins/")
      # Fix claude-code-templates
      elif test("/marketplaces/claude-code-templates/[^/]+$") then
        sub("/marketplaces/claude-code-templates/"; "/marketplaces/claude-code-templates/plugins/")
      # Fix every-marketplace
      elif test("/marketplaces/every-marketplace/[^/]+$") then
        sub("/marketplaces/every-marketplace/"; "/marketplaces/every-marketplace/plugins/")
      # Fix anthropic-agent-skills
      elif test("/marketplaces/anthropic-agent-skills/[^/]+$") then
        sub("/marketplaces/anthropic-agent-skills/"; "/marketplaces/anthropic-agent-skills/skills/")
      # Fix awesome-claude-code-plugins
      elif test("/marketplaces/awesome-claude-code-plugins/[^/]+$") then
        sub("/marketplaces/awesome-claude-code-plugins/"; "/marketplaces/awesome-claude-code-plugins/plugins/")
      # Fix tanzu-cf-architect (flat structure, remove duplicate)
      elif test("/marketplaces/tanzu-cf-architect/tanzu-cf-architect$") then
        sub("/tanzu-cf-architect/tanzu-cf-architect$"; "/tanzu-cf-architect")
      else
        .
      end
  else
    .
  end
)
' "$PLUGINS_FILE" > "${PLUGINS_FILE}.tmp"

mv "${PLUGINS_FILE}.tmp" "$PLUGINS_FILE"

echo "✓ Fixed plugin paths in installed_plugins.json"
echo ""
echo "Changes made:"
jq -r '
.plugins | to_entries[] |
select(.value.isLocal == true) |
"  • \(.key)\n    \(.value.installPath)"
' "$PLUGINS_FILE"
