#!/usr/bin/env bash
# ABOUTME: Automates updating all Claude Code marketplaces and uninstalling all plugins
# ABOUTME: Reads known_marketplaces.json and installed_plugins.json to perform bulk operations

set -euo pipefail

# Configuration
PLUGINS_DIR="${HOME}/.claude/plugins"
KNOWN_MARKETPLACES_FILE="${PLUGINS_DIR}/known_marketplaces.json"
INSTALLED_PLUGINS_FILE="${PLUGINS_DIR}/installed_plugins.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print colored message
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Check if required files exist
check_files() {
    if [[ ! -f "$KNOWN_MARKETPLACES_FILE" ]]; then
        print_status "$RED" "Error: $KNOWN_MARKETPLACES_FILE not found"
        exit 1
    fi

    if [[ ! -f "$INSTALLED_PLUGINS_FILE" ]]; then
        print_status "$RED" "Error: $INSTALLED_PLUGINS_FILE not found"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        print_status "$RED" "Error: jq is required but not installed"
        print_status "$YELLOW" "Install with: brew install jq"
        exit 1
    fi
}

# Update all marketplaces
update_marketplaces() {
    print_status "$GREEN" "\n=== Updating Marketplaces ==="

    local count=0
    while IFS= read -r marketplace; do
        if [[ -z "$marketplace" ]]; then
            continue
        fi
        print_status "$YELLOW" "Updating marketplace: $marketplace"
        if claude plugin marketplace update "$marketplace" < /dev/null; then
            ((count++))
        else
            print_status "$RED" "Failed to update: $marketplace"
        fi
    done < <(jq -r 'keys[]' "$KNOWN_MARKETPLACES_FILE")

    if [[ $count -eq 0 ]]; then
        print_status "$YELLOW" "No marketplaces found"
        return
    fi

    print_status "$GREEN" "Updated $count marketplace(s)"
}

# Reinstall all plugins (uninstall then install)
reinstall_plugins() {
    print_status "$GREEN" "\n=== Reinstalling Plugins ==="

    local count=0
    local failed=0
    while IFS= read -r plugin; do
        if [[ -z "$plugin" ]]; then
            continue
        fi
        print_status "$YELLOW" "Reinstalling: $plugin"

        # Uninstall
        if ! claude plugin uninstall "$plugin" < /dev/null; then
            print_status "$RED" "Failed to uninstall: $plugin"
            ((failed++))
            continue
        fi

        # Install
        if claude plugin install "$plugin" < /dev/null; then
            ((count++))
            print_status "$GREEN" "✓ Successfully reinstalled: $plugin"
        else
            print_status "$RED" "Failed to install: $plugin"
            ((failed++))
        fi
    done < <(jq -r '.plugins | keys[]' "$INSTALLED_PLUGINS_FILE")

    if [[ $count -eq 0 && $failed -eq 0 ]]; then
        print_status "$YELLOW" "No plugins found"
        return
    fi

    print_status "$GREEN" "Reinstalled $count plugin(s)"
    if [[ $failed -gt 0 ]]; then
        print_status "$RED" "Failed: $failed plugin(s)"
    fi
}

# Main execution
main() {
    print_status "$GREEN" "Claude Code Plugin Refresh Tool"
    print_status "$GREEN" "==============================="

    check_files

    # Parse arguments
    local update_only=false
    local reinstall_only=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --update-only)
                update_only=true
                shift
                ;;
            --reinstall-only)
                reinstall_only=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --update-only       Only update marketplaces"
                echo "  --reinstall-only    Only reinstall plugins"
                echo "  --help, -h          Show this help message"
                echo ""
                echo "Without options, updates marketplaces and reinstalls all plugins"
                exit 0
                ;;
            *)
                print_status "$RED" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Execute requested operations
    if [[ "$update_only" == true ]]; then
        update_marketplaces
    elif [[ "$reinstall_only" == true ]]; then
        reinstall_plugins
    else
        update_marketplaces
        reinstall_plugins
    fi

    print_status "$GREEN" "\n✓ Complete"
}

main "$@"
