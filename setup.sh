#!/bin/bash
# ABOUTME: Bootstraps Claude Code by installing claudeup, MCP servers, marketplaces, and plugins.
# ABOUTME: Supports interactive mode (essentials only) and auto mode (all configured items).

set -e

# Detect setup mode (default to auto for simplicity)
SETUP_MODE="${SETUP_MODE:-auto}"

if [ "$SETUP_MODE" = "auto" ]; then
    echo "→ Auto mode: Installing from config..."
else
    echo "→ Interactive mode: Setting up essentials..."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
ENV_FILE="$CONFIG_DIR/.env"

# Export SCRIPT_DIR so Python subprocesses can access it
export SCRIPT_DIR

# Loads base marketplace configuration and optionally merges local overrides.
# Returns merged JSON configuration on stdout.
load_marketplace_config() {
    local base_file="$SCRIPT_DIR/plugins/setup-marketplaces.json"
    local local_file="$SCRIPT_DIR/plugins/setup-marketplaces.local.json"

    # Use Python to merge configs
    python3 << 'PYTHON_SCRIPT'
import json
import sys
import os

script_dir = os.environ.get('SCRIPT_DIR', '.')
base_file = os.path.join(script_dir, 'plugins', 'setup-marketplaces.json')
local_file = os.path.join(script_dir, 'plugins', 'setup-marketplaces.local.json')

# Load base config
try:
    with open(base_file) as f:
        config = json.load(f)
except FileNotFoundError:
    print(f"Error: Base config file not found: {base_file}", file=sys.stderr)
    sys.exit(1)
except json.JSONDecodeError as e:
    print(f"Error: Invalid JSON in base config: {base_file}", file=sys.stderr)
    print(f"  {e}", file=sys.stderr)
    sys.exit(1)

# Merge local config if exists
if os.path.exists(local_file):
    try:
        with open(local_file) as f:
            local_config = json.load(f)
        config['marketplaces'].update(local_config['marketplaces'])
    except json.JSONDecodeError as e:
        print(f"Warning: Invalid JSON in local config: {local_file}", file=sys.stderr)
        print(f"  {e}", file=sys.stderr)
        print(f"  Continuing with base config only", file=sys.stderr)

# Output merged config as JSON
print(json.dumps(config))
PYTHON_SCRIPT
}

# Show platform-appropriate 1Password CLI install instructions
show_1password_install() {
    if command -v apt-get &> /dev/null; then
        echo "  Install 1Password CLI:"
        echo "    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \\"
        echo "      sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg"
        echo "    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main' | \\"
        echo "      sudo tee /etc/apt/sources.list.d/1password.list"
        echo "    sudo apt-get update && sudo apt-get install 1password-cli"
    elif command -v brew &> /dev/null; then
        echo "  Install 1Password CLI: brew install 1password-cli"
    else
        echo "  Install 1Password CLI: https://1password.com/downloads/command-line/"
    fi
}

# Show platform-appropriate direnv install instructions
show_direnv_install() {
    if command -v apt-get &> /dev/null; then
        echo "  Install direnv: sudo apt-get install direnv"
    elif command -v brew &> /dev/null; then
        echo "  Install direnv: brew install direnv"
    else
        echo "  Install direnv: https://direnv.net/docs/installation.html"
    fi
}

echo "Setting up Claude Code configuration..."
echo ""

# Configure git to use GitHub token if provided
if [ -n "$GITHUB_TOKEN" ]; then
    echo "Configuring git with GitHub token..."
    git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
    echo "  ✓ Git configured to use GITHUB_TOKEN"
    echo ""
fi

# Install Claude Code CLI
echo "Installing Claude Code CLI..."

# Check if already installed
if command -v claude &> /dev/null; then
    CURRENT_VERSION=$(claude --version 2>/dev/null | head -n1 || echo "unknown")
    echo "  ✓ Claude CLI already installed ($CURRENT_VERSION)"
else
    # Use official installer
    if curl -fsSL https://claude.ai/install.sh | bash; then
        # Verify installation
        if command -v claude &> /dev/null; then
            INSTALLED_VERSION=$(claude --version 2>/dev/null | head -n1 || echo "installed")
            echo "  ✓ Claude CLI installed ($INSTALLED_VERSION)"
        else
            echo "  ✓ Claude CLI installed (restart shell to use)"
        fi
    else
        echo "  ✗ Failed to install Claude CLI"
        echo "  Please install manually: https://code.claude.com/docs/en/setup"
        exit 1
    fi
fi

echo ""

# Install claudeup (skip if already available)
if command -v claudeup &> /dev/null; then
    echo "  ✓ claudeup already installed"
else
    echo "Installing claudeup..."
    if curl -fsSL https://raw.githubusercontent.com/claudeup/claudeup/main/install.sh | bash; then
        echo "  ✓ claudeup installed"
    else
        echo "  ✗ Failed to install claudeup"
        exit 1
    fi

    # Verify installation
    if command -v claudeup &> /dev/null; then
        echo "  ✓ claudeup is in PATH"
    else
        echo "  ⚠ Add ~/.local/bin to your PATH"
    fi
fi

echo ""

# Load environment variables if .env exists
if [ -f "$ENV_FILE" ]; then
    echo "Loading environment variables from $ENV_FILE"
    set -a
    source "$ENV_FILE"
    set +a
fi

# Install MCP servers from config
echo "Installing MCP servers..."
if [ -f "$CONFIG_DIR/mcp-servers.json" ]; then
    # Parse JSON and install each server
    # Using python for JSON parsing (available on most systems)
    python3 << 'PYTHON_SCRIPT'
import json
import subprocess
import os

config_path = os.path.join(os.environ.get('CONFIG_DIR', 'config'), 'mcp-servers.json')
with open(config_path) as f:
    config = json.load(f)

# Check if 1Password CLI is available
def op_available():
    try:
        subprocess.run(['op', '--version'], capture_output=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

has_op = op_available()

for server in config.get('servers', []):
    name = server['name']
    command = server['command']
    args = server['args']
    secrets = server.get('secrets', {})

    # Fetch secrets from 1Password if available
    env_vars = dict(os.environ)
    missing_secrets = []

    for env_var, op_ref in secrets.items():
        if env_var in os.environ:
            # Already set in environment
            continue
        if has_op:
            try:
                result = subprocess.run(
                    ['op', 'read', op_ref],
                    capture_output=True, check=True, text=True
                )
                env_vars[env_var] = result.stdout.strip()
            except subprocess.CalledProcessError:
                missing_secrets.append((env_var, op_ref))
        else:
            missing_secrets.append((env_var, op_ref))

    if missing_secrets:
        print(f"  Skipping {name}: missing secrets {[s[0] for s in missing_secrets]}")
        if not has_op:
            print(f"    (install 1Password CLI: https://1password.com/downloads/command-line/)")
        continue

    # Build the claude mcp add command (always user scope)
    cmd = ['claude', 'mcp', 'add', name, '-s', 'user', '--']
    cmd.append(command)

    # Substitute env vars in args
    expanded_args = []
    for arg in args:
        if arg.startswith('$'):
            env_var = arg[1:]
            expanded_args.append(env_vars.get(env_var, arg))
        else:
            expanded_args.append(arg)
    cmd.extend(expanded_args)

    print(f"  Adding {name}...")
    try:
        subprocess.run(cmd, check=True, capture_output=True)
        print(f"  ✓ {name} installed")
    except subprocess.CalledProcessError as e:
        # Server might already exist
        if b'already exists' in e.stderr:
            print(f"  ✓ {name} already installed")
        else:
            print(f"  ✗ {name} failed: {e.stderr.decode()}")
PYTHON_SCRIPT
else
    echo "  No mcp-servers.json found, skipping"
fi

echo ""

# Phase 1: Install essential marketplaces
install_essential_marketplaces() {
    echo ""
    echo "Installing essential marketplaces..."

    local config=$(load_marketplace_config)

    # Install essential marketplaces using Python
    echo "$config" | python3 << 'PYTHON_SCRIPT'
import json
import subprocess
import sys

config = json.load(sys.stdin)

for name, marketplace in config["marketplaces"].items():
    # Only install essentials in Phase 1
    if not marketplace.get("essential", False):
        continue

    source_type = marketplace.get("source")

    if source_type == "github":
        repo = marketplace.get("repo")
        desc = marketplace.get("description", "")
        print(f"  Installing {name} ({desc})...")
        try:
            subprocess.run(
                ["claude", "plugin", "marketplace", "add", repo],
                check=True, capture_output=True
            )
            print(f"  ✓ {name}")
        except subprocess.CalledProcessError as e:
            if b"already" in e.stderr.lower() or b"already" in e.stdout.lower():
                print(f"  ✓ {name} (already added)")
            else:
                print(f"  ✗ {name} failed")
    elif source_type == "git":
        url = marketplace.get("url")
        desc = marketplace.get("description", "")
        print(f"  Installing {name} ({desc})...")
        try:
            subprocess.run(
                ["claude", "plugin", "marketplace", "add", url],
                check=True, capture_output=True
            )
            print(f"  ✓ {name}")
        except subprocess.CalledProcessError:
            print(f"  ✓ {name} (already added or failed)")
PYTHON_SCRIPT
}

if [ "$SETUP_MODE" = "interactive" ]; then
    install_essential_marketplaces
    echo ""
    echo "→ Essentials installed! You have a working Claude Code setup."
fi

# Phase 2: Optional marketplace exploration
explore_additional_marketplaces() {
    echo ""
    read -r -p "Want to explore more marketplaces? [Y/n]: " response

    case $response in
        [nN][oO]|[nN])
            echo "Skipping additional marketplaces"
            return
            ;;
    esac

    echo ""
    echo "Popular marketplaces:"
    echo ""

    local config=$(load_marketplace_config)

    # Show non-essential marketplaces
    echo "$config" | python3 << 'PYTHON_SCRIPT'
import json
import sys

config = json.load(sys.stdin)
options = []

for name, marketplace in config['marketplaces'].items():
    if marketplace.get('essential', False):
        continue
    desc = marketplace.get('description', 'No description')
    options.append((name, desc, marketplace))

# Display options
for i, (name, desc, _) in enumerate(options, 1):
    print(f"  {i}. {name} - {desc}")

print("")
print("Enter numbers separated by spaces (e.g., '1 3 4'), or 'all', or 'none':")
PYTHON_SCRIPT

    read -r selection

    if [ "$selection" = "none" ] || [ -z "$selection" ]; then
        echo "No additional marketplaces selected"
        return
    fi

    # Install selected marketplaces
    echo ""
    echo "Installing selected marketplaces..."
    echo "$config" | SELECTION="$selection" python3 << 'PYTHON_SCRIPT'
import json
import subprocess
import sys
import os

config = json.load(sys.stdin)
selection = os.environ.get('SELECTION', '')

# Build list of non-essential marketplaces
options = []
for name, marketplace in config['marketplaces'].items():
    if not marketplace.get('essential', False):
        options.append((name, marketplace))

# Determine which to install
if selection == 'all':
    to_install = options
else:
    try:
        indices = [int(x.strip()) - 1 for x in selection.split()]
        # Validate indices are within bounds
        invalid_indices = [i for i in indices if i < 0 or i >= len(options)]
        if invalid_indices:
            print(f"Error: Invalid selection. Please enter numbers between 1 and {len(options)}", file=sys.stderr)
            sys.exit(1)
        to_install = [options[i] for i in indices]
    except ValueError as e:
        print(f"Error: Invalid input. Please enter numbers separated by spaces (e.g., '1 2 3')", file=sys.stderr)
        sys.exit(1)

# Install each
for name, marketplace in to_install:
    source_type = marketplace.get('source')

    if source_type == 'github':
        repo = marketplace.get('repo')
        print(f"  Installing {name}...")
        try:
            subprocess.run(
                ['claude', 'plugin', 'marketplace', 'add', repo],
                check=True, capture_output=True
            )
            print(f"  ✓ {name}")
        except subprocess.CalledProcessError as e:
            if b'already' in e.stderr.lower() or b'already' in e.stdout.lower():
                print(f"  ✓ {name} (already added)")
            else:
                print(f"  ✗ {name} failed")
    elif source_type == 'git':
        url = marketplace.get('url')
        print(f"  Installing {name}...")
        try:
            subprocess.run(
                ['claude', 'plugin', 'marketplace', 'add', url],
                check=True, capture_output=True
            )
            print(f"  ✓ {name}")
        except subprocess.CalledProcessError:
            print(f"  ✓ {name} (already added or failed)")
PYTHON_SCRIPT

    echo ""
    echo "✓ Done! Use 'claude plugin list <marketplace>' to browse plugins."
}

if [ "$SETUP_MODE" = "interactive" ]; then
    explore_additional_marketplaces
fi

# Auto mode: Install all configured marketplaces and plugins using claudeup
auto_mode_install() {
    echo ""
    echo "Installing marketplaces and plugins via claudeup profile..."

    # Copy docker-profile.json to claudeup profiles directory
    local profile_dir="$HOME/.claudeup/profiles"
    local profile_src="$SCRIPT_DIR/plugins/docker-profile.json"
    local profile_dst="$profile_dir/docker-setup.json"

    if [ ! -f "$profile_src" ]; then
        echo "  ✗ Profile not found: $profile_src"
        return 1
    fi

    mkdir -p "$profile_dir"
    cp "$profile_src" "$profile_dst"
    echo "  ✓ Copied profile to $profile_dst"

    # Apply the profile
    echo ""
    if claudeup profile apply docker-setup --yes 2>&1; then
        echo ""
        echo "  ✓ Profile applied successfully"
    else
        echo "  ✗ Failed to apply profile"
        return 1
    fi
}

if [ "$SETUP_MODE" = "auto" ]; then
    auto_mode_install
fi

echo ""

# Run health check
echo "Running health check..."
if command -v claudeup &> /dev/null; then
    claudeup doctor
    claudeup cleanup --yes
fi

echo ""
echo "Setup complete!"
echo ""

# Check for missing secrets and warn
python3 << 'PYTHON_SCRIPT'
import json
import subprocess
import os

config_path = os.path.join(os.environ.get('CONFIG_DIR', 'config'), 'mcp-servers.json')
if os.path.exists(config_path):
    with open(config_path) as f:
        config = json.load(f)

    # Check if 1Password CLI is available
    try:
        subprocess.run(['op', '--version'], capture_output=True, check=True)
        has_op = True
    except (subprocess.CalledProcessError, FileNotFoundError):
        has_op = False

    missing = []
    for server in config.get('servers', []):
        secrets = server.get('secrets', {})
        for env_var, op_ref in secrets.items():
            if not os.environ.get(env_var):
                if has_op:
                    try:
                        subprocess.run(['op', 'read', op_ref], capture_output=True, check=True)
                    except subprocess.CalledProcessError:
                        missing.append((server['name'], env_var, op_ref))
                else:
                    missing.append((server['name'], env_var, op_ref))

    if missing:
        print("Some MCP servers were skipped due to missing secrets:")
        print("")
        for name, env_var, op_ref in missing:
            print(f"  • {name}: {env_var}")
            print(f"    1Password: {op_ref}")
        print("")
        if not has_op:
            # Platform-aware install instructions
            import shutil
            if shutil.which('apt-get'):
                print("  Install 1Password CLI:")
                print("    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \\")
                print("      sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg")
                print("    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main' | \\")
                print("      sudo tee /etc/apt/sources.list.d/1password.list")
                print("    sudo apt-get update && sudo apt-get install 1password-cli")
            elif shutil.which('brew'):
                print("  Install 1Password CLI: brew install 1password-cli")
            else:
                print("  Install 1Password CLI: https://1password.com/downloads/command-line/")
            print("  Then run: op signin")
        else:
            print("  Ensure you're signed into 1Password: op signin")
        print("  Then re-run ./setup.sh")
PYTHON_SCRIPT

echo ""
echo "To install plugins: claude plugin install <plugin>@<marketplace>"
echo "To list plugins:    claude plugin marketplace list"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Auto-update Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if direnv is installed
if command -v direnv &> /dev/null; then
    echo "✓ direnv detected"
    echo ""
    echo "Would you like to enable automatic daily updates?"
    echo "  • Claude Code version checks"
    echo "  • Plugin and marketplace updates"
    echo ""
    read -r -p "Add auto-update scripts to .envrc? [Y/n] " response

    case $response in
        [nN][oO]|[nN])
            echo "Skipping auto-update configuration"
            ;;
        *)
            # Create or append to .envrc
            ENVRC_FILE="$SCRIPT_DIR/.envrc"

            if [ ! -f "$ENVRC_FILE" ]; then
                echo "# Claude Code auto-updates" > "$ENVRC_FILE"
            fi

            # Add auto-upgrade-claude.sh if not already present
            if ! grep -q "auto-upgrade-claude.sh" "$ENVRC_FILE"; then
                echo "" >> "$ENVRC_FILE"
                echo "# Auto-upgrade Claude Code and claudeup daily" >> "$ENVRC_FILE"
                echo 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' >> "$ENVRC_FILE"
                echo '"$SCRIPT_DIR/scripts/auto-upgrade-claude.sh" &' >> "$ENVRC_FILE"
            fi

            # Add auto-update-plugins.sh if not already present
            if ! grep -q "auto-update-plugins.sh" "$ENVRC_FILE"; then
                echo "" >> "$ENVRC_FILE"
                echo "# Auto-update plugins and marketplaces daily" >> "$ENVRC_FILE"
                echo '"$SCRIPT_DIR/scripts/auto-update-plugins.sh"' >> "$ENVRC_FILE"
            fi

            echo "✓ Added auto-update scripts to .envrc"
            echo ""
            echo "Run 'direnv allow .' to enable"
            ;;
    esac
else
    echo "⚠ direnv not installed"
    echo ""
    echo "To enable automatic daily updates:"
    echo "  1. Install direnv:"
    show_direnv_install
    echo "  2. Add to shell: eval \"\$(direnv hook zsh)\"  # or bash"
    echo "  3. Re-run: ./setup.sh"
fi
