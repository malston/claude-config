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

# Interactive selection helper
select_items() {
    local prompt=$1
    shift
    local items=("$@")

    if [[ ${#items[@]} -eq 0 ]]; then
        echo ""
        return
    fi

    print_status "$GREEN" "\n$prompt" >&2
    print_status "$YELLOW" "Enter numbers separated by spaces (e.g., 1 3 5), 'all' for all items, or 'none' to skip:" >&2
    echo "" >&2

    local i=1
    for item in "${items[@]}"; do
        echo "  $i) $item" >&2
        ((i++))
    done
    echo "" >&2

    read -r -p "Selection: " selection

    # Handle special cases
    if [[ "$selection" == "none" ]] || [[ -z "$selection" ]]; then
        echo ""
        return
    fi

    if [[ "$selection" == "all" ]]; then
        printf '%s\n' "${items[@]}"
        return
    fi

    # Parse numbers and return selected items
    local selected=()
    for num in $selection; do
        if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le ${#items[@]} ]]; then
            selected+=("${items[$((num-1))]}")
        else
            print_status "$RED" "Invalid selection: $num (skipping)" >&2
        fi
    done

    printf '%s\n' "${selected[@]}"
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
    local interactive=$1

    print_status "$GREEN" "\n=== Updating Marketplaces ==="

    local all_marketplaces
    mapfile -t all_marketplaces < <(jq -r 'keys[]' "$KNOWN_MARKETPLACES_FILE")

    if [[ ${#all_marketplaces[@]} -eq 0 ]]; then
        print_status "$YELLOW" "No marketplaces found"
        return
    fi

    local marketplaces
    if [[ "$interactive" == true ]]; then
        mapfile -t marketplaces < <(select_items "Select marketplaces to update:" "${all_marketplaces[@]}")
        if [[ ${#marketplaces[@]} -eq 0 ]]; then
            print_status "$YELLOW" "No marketplaces selected for update"
            return
        fi
    else
        marketplaces=("${all_marketplaces[@]}")
    fi

    local count=0
    for marketplace in "${marketplaces[@]}"; do
        print_status "$YELLOW" "Updating marketplace: $marketplace"
        if claude plugin marketplace update "$marketplace" < /dev/null; then
            count=$((count + 1))
        else
            print_status "$RED" "Failed to update: $marketplace"
        fi
    done

    print_status "$GREEN" "Updated $count marketplace(s)"
}

# Reinstall all plugins (uninstall then install)
reinstall_plugins() {
    local interactive=$1

    print_status "$GREEN" "\n=== Reinstalling Plugins ==="

    local all_plugins
    mapfile -t all_plugins < <(jq -r '.plugins | keys[]' "$INSTALLED_PLUGINS_FILE")

    if [[ ${#all_plugins[@]} -eq 0 ]]; then
        print_status "$YELLOW" "No plugins found"
        return
    fi

    local plugins
    if [[ "$interactive" == true ]]; then
        mapfile -t plugins < <(select_items "Select plugins to reinstall:" "${all_plugins[@]}")
        if [[ ${#plugins[@]} -eq 0 ]]; then
            print_status "$YELLOW" "No plugins selected for reinstallation"
            return
        fi
    else
        plugins=("${all_plugins[@]}")
    fi

    local count=0
    local failed=0
    for plugin in "${plugins[@]}"; do
        print_status "$YELLOW" "Reinstalling: $plugin"

        # Uninstall (capture output to check error type)
        # Temporarily disable exit on error to capture status properly
        set +e
        local uninstall_output
        uninstall_output=$(claude plugin uninstall "$plugin" 2>&1 < /dev/null)
        local uninstall_status=$?
        set -e

        # Check if uninstall failed
        if [[ $uninstall_status -ne 0 ]]; then
            # Check if it's because plugin is already uninstalled or not found
            if echo "$uninstall_output" | grep -qE "(already uninstalled|not found)"; then
                print_status "$YELLOW" "⚠ Plugin not currently installed, will attempt fresh install"
            else
                # Real uninstall error - skip this plugin
                print_status "$RED" "✘ Failed to uninstall: $plugin"
                echo "$uninstall_output"
                failed=$((failed + 1))
                continue
            fi
        fi

        # Install
        if claude plugin install "$plugin" < /dev/null; then
            count=$((count + 1))
            print_status "$GREEN" "✓ Successfully reinstalled: $plugin"
        else
            print_status "$RED" "✘ Failed to install: $plugin"
            failed=$((failed + 1))
        fi
    done

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
    local interactive=false

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
            --interactive|-i)
                interactive=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --update-only       Only update marketplaces"
                echo "  --reinstall-only    Only reinstall plugins"
                echo "  --interactive, -i   Interactively select which items to process"
                echo "  --help, -h          Show this help message"
                echo ""
                echo "Without options, updates marketplaces and reinstalls all plugins"
                echo "The --interactive flag can be combined with --update-only or --reinstall-only"
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
        update_marketplaces "$interactive"
    elif [[ "$reinstall_only" == true ]]; then
        reinstall_plugins "$interactive"
    else
        update_marketplaces "$interactive"
        reinstall_plugins "$interactive"
    fi

    print_status "$GREEN" "\n✓ Complete"
}

main "$@"
