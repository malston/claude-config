#!/usr/bin/env bash
# ABOUTME: Checks for out-of-date marketplaces and plugins, prompting user to upgrade them
# ABOUTME: Compares git commits to detect available updates and offers interactive upgrade

set -euo pipefail

# Configuration
PLUGINS_DIR="${HOME}/.claude/plugins"
KNOWN_MARKETPLACES_FILE="${PLUGINS_DIR}/known_marketplaces.json"
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

# Check if a marketplace has updates available
check_marketplace_updates() {
    local marketplace=$1
    local install_location=$2

    if [[ ! -d "$install_location" ]]; then
        echo "not_installed"
        return
    fi

    # Get the default branch name
    local default_branch
    default_branch=$(cd "$install_location" && git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

    # Fetch latest from remote (suppress output)
    if ! (cd "$install_location" && git fetch origin &>/dev/null); then
        echo "fetch_failed"
        return
    fi

    # Compare local HEAD with remote HEAD
    local local_commit
    local remote_commit
    local_commit=$(cd "$install_location" && git rev-parse HEAD 2>/dev/null || echo "")
    remote_commit=$(cd "$install_location" && git rev-parse "origin/$default_branch" 2>/dev/null || echo "")

    if [[ -z "$local_commit" ]] || [[ -z "$remote_commit" ]]; then
        echo "unknown"
        return
    fi

    if [[ "$local_commit" != "$remote_commit" ]]; then
        echo "outdated"
    else
        echo "up_to_date"
    fi
}

# Check if a plugin has updates available
check_plugin_updates() {
    local plugin=$1
    local installed_sha=$2
    local install_path=$3

    if [[ ! -d "$install_path" ]]; then
        echo "not_found"
        return
    fi

    # Get the current commit SHA in the marketplace
    local current_sha
    current_sha=$(cd "$install_path" && git rev-parse HEAD 2>/dev/null || echo "")

    if [[ -z "$current_sha" ]]; then
        echo "unknown"
        return
    fi

    if [[ "$installed_sha" != "$current_sha" ]]; then
        echo "outdated"
    else
        echo "up_to_date"
    fi
}

# Check all marketplaces for updates
scan_marketplace_updates() {
    print_status "$CYAN" "\n━━━ Checking Marketplaces ━━━" >&2

    local all_marketplaces
    mapfile -t all_marketplaces < <(jq -r 'keys[]' "$KNOWN_MARKETPLACES_FILE")

    if [[ ${#all_marketplaces[@]} -eq 0 ]]; then
        print_status "$YELLOW" "No marketplaces found" >&2
        return
    fi

    local outdated_marketplaces=()
    local up_to_date_count=0

    for marketplace in "${all_marketplaces[@]}"; do
        local install_location
        install_location=$(jq -r --arg mp "$marketplace" '.[$mp].installLocation' "$KNOWN_MARKETPLACES_FILE")

        print_status "$BLUE" "Checking $marketplace..." >&2
        local status
        status=$(check_marketplace_updates "$marketplace" "$install_location")

        case $status in
            outdated)
                outdated_marketplaces+=("$marketplace")
                print_status "$YELLOW" "  ⚠ Update available" >&2
                ;;
            up_to_date)
                up_to_date_count=$((up_to_date_count + 1))
                print_status "$GREEN" "  ✓ Up to date" >&2
                ;;
            not_installed)
                print_status "$RED" "  ✗ Not installed" >&2
                ;;
            fetch_failed)
                print_status "$RED" "  ✗ Failed to fetch updates" >&2
                ;;
            *)
                print_status "$YELLOW" "  ? Status unknown" >&2
                ;;
        esac
    done

    echo "" >&2
    print_status "$GREEN" "Summary: $up_to_date_count up to date, ${#outdated_marketplaces[@]} updates available" >&2

    # Store outdated marketplaces for later use
    printf '%s\n' "${outdated_marketplaces[@]}"
}

# Check all plugins for updates
scan_plugin_updates() {
    print_status "$CYAN" "\n━━━ Checking Plugins ━━━" >&2

    local all_plugins
    mapfile -t all_plugins < <(jq -r '.plugins | keys[]' "$INSTALLED_PLUGINS_FILE")

    if [[ ${#all_plugins[@]} -eq 0 ]]; then
        print_status "$YELLOW" "No plugins found" >&2
        return
    fi

    local outdated_plugins=()
    local up_to_date_count=0

    for plugin in "${all_plugins[@]}"; do
        local installed_sha install_path
        installed_sha=$(jq -r --arg p "$plugin" '.plugins[$p].gitCommitSha' "$INSTALLED_PLUGINS_FILE")
        install_path=$(jq -r --arg p "$plugin" '.plugins[$p].installPath' "$INSTALLED_PLUGINS_FILE")

        print_status "$BLUE" "Checking $plugin..." >&2
        local status
        status=$(check_plugin_updates "$plugin" "$installed_sha" "$install_path")

        case $status in
            outdated)
                outdated_plugins+=("$plugin")
                print_status "$YELLOW" "  ⚠ Update available" >&2
                ;;
            up_to_date)
                up_to_date_count=$((up_to_date_count + 1))
                print_status "$GREEN" "  ✓ Up to date" >&2
                ;;
            not_found)
                print_status "$RED" "  ✗ Plugin path not found" >&2
                ;;
            *)
                print_status "$YELLOW" "  ? Status unknown" >&2
                ;;
        esac
    done

    echo "" >&2
    print_status "$GREEN" "Summary: $up_to_date_count up to date, ${#outdated_plugins[@]} updates available" >&2

    # Store outdated plugins for later use
    printf '%s\n' "${outdated_plugins[@]}"
}

# Prompt user to update marketplaces
prompt_marketplace_updates() {
    local -n outdated=$1

    if [[ ${#outdated[@]} -eq 0 ]]; then
        return
    fi

    print_status "$CYAN" "\n━━━ Marketplace Updates Available ━━━"
    for mp in "${outdated[@]}"; do
        echo "  • $mp"
    done
    echo ""

    read -r -p "Update these marketplaces? [Y/n] " response
    case $response in
        [nN][oO]|[nN])
            print_status "$YELLOW" "Skipping marketplace updates"
            return
            ;;
        *)
            print_status "$GREEN" "\nUpdating marketplaces..."
            for mp in "${outdated[@]}"; do
                print_status "$BLUE" "Updating $mp..."
                if claude plugin marketplace update "$mp" < /dev/null; then
                    print_status "$GREEN" "  ✓ Updated successfully"
                else
                    print_status "$RED" "  ✗ Update failed"
                fi
            done
            ;;
    esac
}

# Prompt user to update plugins
prompt_plugin_updates() {
    local -n outdated=$1

    if [[ ${#outdated[@]} -eq 0 ]]; then
        return
    fi

    print_status "$CYAN" "\n━━━ Plugin Updates Available ━━━"
    for plugin in "${outdated[@]}"; do
        echo "  • $plugin"
    done
    echo ""

    read -r -p "Reinstall these plugins to get updates? [Y/n] " response
    case $response in
        [nN][oO]|[nN])
            print_status "$YELLOW" "Skipping plugin updates"
            return
            ;;
        *)
            print_status "$GREEN" "\nReinstalling plugins..."
            for plugin in "${outdated[@]}"; do
                print_status "$BLUE" "Reinstalling $plugin..."

                # Uninstall
                set +e
                claude plugin uninstall "$plugin" &>/dev/null
                set -e

                # Install
                if claude plugin install "$plugin" < /dev/null; then
                    print_status "$GREEN" "  ✓ Reinstalled successfully"
                else
                    print_status "$RED" "  ✗ Reinstall failed"
                fi
            done
            ;;
    esac
}

# Main execution
main() {
    print_status "$GREEN" "Claude Code Update Checker"
    print_status "$GREEN" "=========================="

    check_files

    # Parse arguments
    local check_only=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --check-only)
                check_only=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --check-only    Only check for updates, don't prompt to install"
                echo "  --help, -h      Show this help message"
                echo ""
                echo "Without options, checks for updates and prompts to install them"
                exit 0
                ;;
            *)
                print_status "$RED" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Check for marketplace updates
    local outdated_marketplaces
    mapfile -t outdated_marketplaces < <(scan_marketplace_updates)

    # Check for plugin updates
    local outdated_plugins
    mapfile -t outdated_plugins < <(scan_plugin_updates)

    # If check-only mode, exit here
    if [[ "$check_only" == true ]]; then
        print_status "$GREEN" "\n✓ Check complete"
        exit 0
    fi

    # Prompt for updates
    if [[ ${#outdated_marketplaces[@]} -eq 0 ]] && [[ ${#outdated_plugins[@]} -eq 0 ]]; then
        print_status "$GREEN" "\n✓ Everything is up to date!"
        exit 0
    fi

    prompt_marketplace_updates outdated_marketplaces
    prompt_plugin_updates outdated_plugins

    print_status "$GREEN" "\n✓ Complete"
}

main "$@"
