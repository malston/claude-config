#!/usr/bin/env bash
# ABOUTME: Automates reinstalling Claude Code marketplaces with optional interactive selection
# ABOUTME: Reads known_marketplaces.json to uninstall and reinstall selected marketplaces

set -euo pipefail

# Configuration
PLUGINS_DIR="${HOME}/.claude/plugins"
KNOWN_MARKETPLACES_FILE="${PLUGINS_DIR}/known_marketplaces.json"

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

    if ! command -v jq &> /dev/null; then
        print_status "$RED" "Error: jq is required but not installed"
        print_status "$YELLOW" "Install with: brew install jq"
        exit 1
    fi
}

# Reinstall marketplaces (uninstall then add)
reinstall_marketplaces() {
    local interactive=$1

    print_status "$GREEN" "\n=== Reinstalling Marketplaces ==="

    local all_marketplaces
    mapfile -t all_marketplaces < <(jq -r 'keys[]' "$KNOWN_MARKETPLACES_FILE")

    if [[ ${#all_marketplaces[@]} -eq 0 ]]; then
        print_status "$YELLOW" "No marketplaces found"
        return
    fi

    local marketplaces
    if [[ "$interactive" == true ]]; then
        mapfile -t marketplaces < <(select_items "Select marketplaces to reinstall:" "${all_marketplaces[@]}")
        if [[ ${#marketplaces[@]} -eq 0 ]]; then
            print_status "$YELLOW" "No marketplaces selected for reinstallation"
            return
        fi
    else
        marketplaces=("${all_marketplaces[@]}")
    fi

    local count=0
    local failed=0
    for marketplace in "${marketplaces[@]}"; do
        print_status "$YELLOW" "Reinstalling: $marketplace"

        # Get the marketplace source info from known_marketplaces.json
        local source_type
        local repo_or_url
        source_type=$(jq -r --arg mp "$marketplace" '.[$mp].source.source' "$KNOWN_MARKETPLACES_FILE")

        if [[ "$source_type" == "github" ]]; then
            repo_or_url=$(jq -r --arg mp "$marketplace" '.[$mp].source.repo' "$KNOWN_MARKETPLACES_FILE")
        elif [[ "$source_type" == "git" ]]; then
            repo_or_url=$(jq -r --arg mp "$marketplace" '.[$mp].source.url' "$KNOWN_MARKETPLACES_FILE")
        else
            print_status "$RED" "✘ Unknown source type for $marketplace: $source_type"
            failed=$((failed + 1))
            continue
        fi

        # Uninstall (capture output to check error type)
        set +e
        local uninstall_output
        uninstall_output=$(claude plugin marketplace remove "$marketplace" 2>&1 < /dev/null)
        local uninstall_status=$?
        set -e

        # Check if uninstall failed
        if [[ $uninstall_status -ne 0 ]]; then
            # Check if it's because marketplace is already uninstalled or not found
            if echo "$uninstall_output" | grep -qE "(not found|not installed)"; then
                print_status "$YELLOW" "⚠ Marketplace not currently installed, will attempt fresh install"
            else
                # Real uninstall error - skip this marketplace
                print_status "$RED" "✘ Failed to uninstall: $marketplace"
                echo "$uninstall_output"
                failed=$((failed + 1))
                continue
            fi
        fi

        # Add/Install
        if [[ "$source_type" == "github" ]]; then
            if claude plugin marketplace add "$repo_or_url" < /dev/null; then
                count=$((count + 1))
                print_status "$GREEN" "✓ Successfully reinstalled: $marketplace"
            else
                print_status "$RED" "✘ Failed to add: $marketplace"
                failed=$((failed + 1))
            fi
        elif [[ "$source_type" == "git" ]]; then
            if claude plugin marketplace add "$repo_or_url" < /dev/null; then
                count=$((count + 1))
                print_status "$GREEN" "✓ Successfully reinstalled: $marketplace"
            else
                print_status "$RED" "✘ Failed to add: $marketplace"
                failed=$((failed + 1))
            fi
        fi
    done

    print_status "$GREEN" "Reinstalled $count marketplace(s)"
    if [[ $failed -gt 0 ]]; then
        print_status "$RED" "Failed: $failed marketplace(s)"
    fi
}

# Main execution
main() {
    print_status "$GREEN" "Claude Code Marketplace Refresh Tool"
    print_status "$GREEN" "===================================="

    check_files

    # Parse arguments
    local interactive=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --interactive|-i)
                interactive=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --interactive, -i   Interactively select which marketplaces to reinstall"
                echo "  --help, -h          Show this help message"
                echo ""
                echo "Without options, reinstalls all marketplaces"
                exit 0
                ;;
            *)
                print_status "$RED" "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Execute reinstallation
    reinstall_marketplaces "$interactive"

    print_status "$GREEN" "\n✓ Complete"
}

main "$@"
