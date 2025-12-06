#!/usr/bin/env bash
# ABOUTME: Toggles any Claude Code plugin on/off to manage context usage
# ABOUTME: Accepts plugin name as argument, shows current status and available commands

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Print colored message
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if a plugin is installed
is_installed() {
    local plugin=$1
    local plugins_file="${HOME}/.claude/plugins/installed_plugins.json"

    if [[ ! -f "$plugins_file" ]]; then
        return 1
    fi

    local exists
    exists=$(jq -r --arg plugin "$plugin" '
        .plugins | keys[] | select(. == $plugin or startswith($plugin + "@"))
    ' "$plugins_file" | head -1)

    [[ -n "$exists" ]]
}

# Get plugin info from installed_plugins.json
get_plugin_info() {
    local plugin=$1
    local plugins_file="${HOME}/.claude/plugins/installed_plugins.json"

    if [[ ! -f "$plugins_file" ]]; then
        echo "{}"
        return
    fi

    # Find plugin by matching the key (handle both exact match and @marketplace suffix)
    jq -r --arg plugin "$plugin" '
        .plugins | to_entries[] |
        select(.key == $plugin or (.key | startswith($plugin + "@"))) |
        {
            version: .value.version,
            marketplace: (.key | split("@")[1] // "unknown"),
            installPath: .value.installPath
        }
    ' "$plugins_file" | head -1
}

# List all installed plugins
list_plugins() {
    local plugins_file="${HOME}/.claude/plugins/installed_plugins.json"

    if [[ ! -f "$plugins_file" ]]; then
        print_status "$RED" "Error: installed_plugins.json not found"
        return 1
    fi

    print_status "$CYAN" "\n=== Installed Plugins ==="
    echo ""

    local count=0

    # Read plugins from JSON
    while IFS= read -r plugin; do
        print_status "$GREEN" "  • $plugin"
        count=$((count + 1))
    done < <(jq -r '.plugins | keys[]' "$plugins_file")

    echo ""
    print_status "$BLUE" "Total: $count plugins"
    echo ""
    print_status "$YELLOW" "Note: To toggle a plugin, run: toggle-plugin.sh <plugin-name>"
}

# Toggle a specific plugin
toggle_plugin() {
    local plugin=$1
    local plugins_file="${HOME}/.claude/plugins/installed_plugins.json"

    # Handle both short name and full name@marketplace format
    # First, try to find the plugin in the installed plugins
    local full_plugin_name
    full_plugin_name=$(jq -r --arg plugin "$plugin" '
        .plugins | keys[] | select(. == $plugin or startswith($plugin + "@"))
    ' "$plugins_file" | head -1)

    if [[ -z "$full_plugin_name" ]]; then
        print_status "$RED" "Error: Plugin '$plugin' not found"
        echo ""
        echo "Available plugins:"
        jq -r '.plugins | keys[] | "  • " + .' "$plugins_file"
        exit 1
    fi

    # Try to disable first
    set +e
    local disable_output
    disable_output=$(claude plugin disable "$full_plugin_name" 2>&1 < /dev/null)
    local disable_exit=$?
    set -e

    if [[ $disable_exit -eq 0 ]]; then
        # Successfully disabled
        print_status "$GREEN" "✓ Disabled $full_plugin_name"
        echo ""
        print_status "$YELLOW" "Plugin commands, agents, skills, and MCP servers are now unavailable"
        print_status "$BLUE" "Run again to re-enable"
    elif echo "$disable_output" | grep -q "not found in enabled plugins"; then
        # Plugin is already disabled, try to enable it
        print_status "$YELLOW" "Enabling $full_plugin_name..."
        if claude plugin enable "$full_plugin_name" < /dev/null; then
            print_status "$GREEN" "✓ Enabled $full_plugin_name"
            echo ""
            print_status "$GREEN" "Plugin commands, agents, skills, and MCP servers are now available"
            print_status "$BLUE" "Run again to disable"
        else
            print_status "$RED" "✗ Failed to enable plugin"
            exit 1
        fi
    else
        print_status "$RED" "✗ Failed to toggle plugin"
        echo "$disable_output"
        exit 1
    fi
}

# Show help
show_help() {
    cat << 'EOF'
Usage: toggle-plugin.sh [OPTIONS] [PLUGIN_NAME]

Toggles Claude Code plugins on/off to manage context usage and functionality.

OPTIONS:
  -l, --list        List all installed plugins with their status
  -h, --help        Show this help message

PLUGIN_NAME:
  Name of the plugin to toggle (with or without @marketplace suffix)
  Examples: compound-engineering, superpowers@superpowers-marketplace

EXAMPLES:
  # List all plugins
  toggle-plugin.sh --list

  # Toggle a specific plugin
  toggle-plugin.sh compound-engineering

  # Toggle using full name
  toggle-plugin.sh compound-engineering@every-marketplace

  # Check status (no changes)
  toggle-plugin.sh superpowers

NOTES:
  - Disabling a plugin removes its MCP servers, reducing context usage
  - Plugin commands, agents, and skills become unavailable when disabled
  - Use --list to see which plugins are currently enabled/disabled
  - Toggle the same plugin again to re-enable it

EOF
}

# Main execution
main() {
    # Parse arguments
    case "${1:-}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--list)
            list_plugins
            exit 0
            ;;
        "")
            print_status "$RED" "Error: No plugin name provided"
            echo ""
            echo "Usage: $0 [OPTIONS] PLUGIN_NAME"
            echo "Try '$0 --help' for more information"
            echo ""
            echo "Or use '$0 --list' to see available plugins"
            exit 1
            ;;
        *)
            toggle_plugin "$1"
            ;;
    esac
}

main "$@"
