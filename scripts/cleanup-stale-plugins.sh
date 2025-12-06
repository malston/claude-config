#!/usr/bin/env bash
# ABOUTME: Identifies and cleans up stale plugin entries with missing installation paths
# ABOUTME: Offers to uninstall stale entries and optionally reinstall them

set -euo pipefail

# Configuration
PLUGINS_DIR="${HOME}/.claude/plugins"
INSTALLED_PLUGINS_FILE="${PLUGINS_DIR}/installed_plugins.json"

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

# Check if required files exist
check_files() {
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

# Find plugins with missing paths
find_stale_plugins() {
    local all_plugins
    mapfile -t all_plugins < <(jq -r '.plugins | keys[]' "$INSTALLED_PLUGINS_FILE")

    local stale_plugins=()

    for plugin in "${all_plugins[@]}"; do
        local install_path
        install_path=$(jq -r --arg p "$plugin" '.plugins[$p].installPath' "$INSTALLED_PLUGINS_FILE")

        if [[ ! -d "$install_path" ]]; then
            stale_plugins+=("$plugin")
        fi
    done

    printf '%s\n' "${stale_plugins[@]}"
}

# Clean up stale plugins
cleanup_stale_plugins() {
    local -n stale=$1
    local reinstall=$2

    if [[ ${#stale[@]} -eq 0 ]]; then
        print_status "$GREEN" "No stale plugins found"
        return
    fi

    print_status "$CYAN" "\n━━━ Found ${#stale[@]} Stale Plugin Entries ━━━"
    for plugin in "${stale[@]}"; do
        local install_path
        install_path=$(jq -r --arg p "$plugin" '.plugins[$p].installPath' "$INSTALLED_PLUGINS_FILE")
        echo "  • $plugin"
        echo "    Path: $install_path"
    done
    echo ""

    read -r -p "Remove these stale entries from installed_plugins.json? [Y/n] " response
    case $response in
        [nN][oO]|[nN])
            print_status "$YELLOW" "Skipping cleanup"
            return
            ;;
    esac

    print_status "$GREEN" "\nCleaning up stale entries..."
    local removed=0
    local failed=0

    for plugin in "${stale[@]}"; do
        print_status "$BLUE" "Removing: $plugin"

        # Uninstall to clean up the JSON entry
        set +e
        local output
        output=$(claude plugin uninstall "$plugin" 2>&1 < /dev/null)
        local status=$?
        set -e

        if [[ $status -eq 0 ]]; then
            removed=$((removed + 1))
            print_status "$GREEN" "  ✓ Removed"
        else
            # Check if it's already uninstalled
            if echo "$output" | grep -qE "(not found|not installed)"; then
                removed=$((removed + 1))
                print_status "$GREEN" "  ✓ Already removed"
            else
                failed=$((failed + 1))
                print_status "$RED" "  ✗ Failed to remove"
                echo "$output"
            fi
        fi
    done

    print_status "$GREEN" "\nRemoved $removed stale entry(ies)"
    if [[ $failed -gt 0 ]]; then
        print_status "$RED" "Failed: $failed entry(ies)"
    fi

    # Offer to reinstall
    if [[ "$reinstall" == true ]] && [[ $removed -gt 0 ]]; then
        echo ""
        read -r -p "Reinstall these plugins? [Y/n] " response
        case $response in
            [nN][oO]|[nN])
                print_status "$YELLOW" "Skipping reinstall"
                return
                ;;
        esac

        print_status "$GREEN" "\nReinstalling plugins..."
        local installed=0
        for plugin in "${stale[@]}"; do
            print_status "$BLUE" "Installing: $plugin"

            if claude plugin install "$plugin" < /dev/null; then
                installed=$((installed + 1))
                print_status "$GREEN" "  ✓ Installed"
            else
                print_status "$RED" "  ✗ Failed to install"
            fi
        done

        print_status "$GREEN" "\nInstalled $installed plugin(s)"
    fi
}

# Main execution
main() {
    print_status "$GREEN" "Claude Code Plugin Cleanup Tool"
    print_status "$GREEN" "================================"

    check_files

    # Parse arguments
    local list_only=false
    local reinstall=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --list-only)
                list_only=true
                shift
                ;;
            --reinstall)
                reinstall=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --list-only     Only list stale plugins, don't clean them up"
                echo "  --reinstall     Offer to reinstall plugins after cleanup"
                echo "  --help, -h      Show this help message"
                echo ""
                echo "Without options, identifies and removes stale plugin entries"
                exit 0
                ;;
            *)
                print_status "$RED" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Find stale plugins
    print_status "$CYAN" "\nScanning for stale plugin entries..."
    local stale_plugins
    mapfile -t stale_plugins < <(find_stale_plugins)

    if [[ ${#stale_plugins[@]} -eq 0 ]]; then
        print_status "$GREEN" "\n✓ No stale plugins found - everything looks good!"
        exit 0
    fi

    # If list-only mode, just show them and exit
    if [[ "$list_only" == true ]]; then
        print_status "$YELLOW" "\nFound ${#stale_plugins[@]} stale plugin entries:"
        for plugin in "${stale_plugins[@]}"; do
            local install_path
            install_path=$(jq -r --arg p "$plugin" '.plugins[$p].installPath' "$INSTALLED_PLUGINS_FILE")
            echo "  • $plugin"
            echo "    Path: $install_path"
        done
        exit 0
    fi

    # Clean up stale plugins
    cleanup_stale_plugins stale_plugins "$reinstall"

    print_status "$GREEN" "\n✓ Complete"
}

main "$@"
