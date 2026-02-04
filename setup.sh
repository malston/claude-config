#!/usr/bin/env bash
# ABOUTME: Bootstraps Claude Code by installing the CLI, claudeup, MCP servers, marketplaces, and plugins.
# ABOUTME: Reads profile configuration from config/my-profile.json.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
ENV_FILE="$CONFIG_DIR/.env"
PROFILE_FILE="$CONFIG_DIR/my-profile.json"

# Export for Python subprocesses
export SCRIPT_DIR
export CONFIG_DIR
export PROFILE_FILE

# Load environment variables if .env exists (before checking env vars)
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
fi

echo "Setting up Claude Code configuration..."
echo ""

# Configure git identity if provided
if [ -n "$GIT_USER_NAME" ]; then
    git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "$GIT_USER_EMAIL" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
fi

# Configure git to use GitHub token if provided
if [ -n "$GITHUB_TOKEN" ]; then
    echo "Configuring git with GitHub token..."
    git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
    echo "  ✓ Git configured to use GITHUB_TOKEN"
    echo ""
fi

# Install Claude Code CLI
echo "Installing Claude Code CLI..."
if command -v claude &> /dev/null; then
    CURRENT_VERSION=$(claude --version 2>/dev/null | head -n1 || echo "unknown")
    echo "  ✓ Claude CLI already installed ($CURRENT_VERSION)"
else
    if curl -fsSL https://claude.ai/install.sh | bash; then
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

# Install claudeup
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

    if command -v claudeup &> /dev/null; then
        echo "  ✓ claudeup is in PATH"
    else
        echo "  ⚠ Add ~/.local/bin to your PATH"
    fi
fi

echo ""

# Install switch-claude-config script
echo "Installing switch-claude-config..."
mkdir -p "$HOME/.local/bin"
if cp "$SCRIPT_DIR/scripts/switch-claude-config" "$HOME/.local/bin/switch-claude-config" 2>/dev/null; then
    chmod +x "$HOME/.local/bin/switch-claude-config"
    echo "  ✓ switch-claude-config installed to ~/.local/bin"
else
    echo "  ⚠ switch-claude-config not found in scripts/"
fi

echo ""

# Install MCP servers from config
echo "Installing MCP servers..."
if [ -f "$CONFIG_DIR/mcp-servers.json" ]; then
    python3 << 'PYTHON_SCRIPT'
import json
import subprocess
import os

config_path = os.path.join(os.environ.get('CONFIG_DIR', 'config'), 'mcp-servers.json')
with open(config_path) as f:
    config = json.load(f)

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

    env_vars = dict(os.environ)
    missing_secrets = []

    for env_var, op_ref in secrets.items():
        if env_var in os.environ:
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

    cmd = ['claude', 'mcp', 'add', name, '-s', 'user', '--']
    cmd.append(command)

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
        if b'already exists' in e.stderr:
            print(f"  ✓ {name} already installed")
        else:
            print(f"  ✗ {name} failed: {e.stderr.decode()}")
PYTHON_SCRIPT
else
    echo "  No mcp-servers.json found, skipping"
fi

echo ""

# Install marketplaces and plugins from profile
echo "Installing marketplaces and plugins from profile..."
if [ -f "$PROFILE_FILE" ]; then
    python3 << 'PYTHON_SCRIPT'
import json
import subprocess
import os

profile_path = os.environ.get('PROFILE_FILE', os.path.join(os.environ.get('CONFIG_DIR', 'config'), 'my-profile.json'))
if not os.path.exists(profile_path):
    profile_path = os.path.join(os.environ.get('CONFIG_DIR', 'config'), 'my-profile.json')

with open(profile_path) as f:
    profile = json.load(f)

# Install marketplaces
print("  Installing marketplaces...")
for marketplace in profile.get('marketplaces', []):
    source = marketplace.get('source')
    if source == 'github':
        repo = marketplace.get('repo')
        print(f"    Adding {repo}...")
        try:
            subprocess.run(
                ['claude', 'plugin', 'marketplace', 'add', repo],
                check=True, capture_output=True
            )
            print(f"    ✓ {repo}")
        except subprocess.CalledProcessError as e:
            stderr = e.stderr.decode() if e.stderr else ''
            if 'already' in stderr.lower():
                print(f"    ✓ {repo} (already added)")
            else:
                print(f"    ✗ {repo}: {stderr}")
    elif source == 'git':
        url = marketplace.get('url')
        print(f"    Adding {url}...")
        try:
            subprocess.run(
                ['claude', 'plugin', 'marketplace', 'add', url],
                check=True, capture_output=True
            )
            print(f"    ✓ {url}")
        except subprocess.CalledProcessError as e:
            stderr = e.stderr.decode() if e.stderr else ''
            if 'already' in stderr.lower():
                print(f"    ✓ {url} (already added)")
            else:
                print(f"    ✗ {url}: {stderr}")

# Install plugins
print("")
print("  Installing plugins...")
for plugin in profile.get('plugins', []):
    print(f"    Installing {plugin}...")
    try:
        subprocess.run(
            ['claude', 'plugin', 'install', plugin],
            check=True, capture_output=True
        )
        print(f"    ✓ {plugin}")
    except subprocess.CalledProcessError as e:
        stderr = e.stderr.decode() if e.stderr else ''
        if 'already' in stderr.lower():
            print(f"    ✓ {plugin} (already installed)")
        else:
            print(f"    ✗ {plugin}: {stderr}")
PYTHON_SCRIPT
else
    echo "  ✗ Profile not found: $PROFILE_FILE"
    exit 1
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
            print(f"  - {name}: {env_var}")
            print(f"    1Password: {op_ref}")
        print("")
        if not has_op:
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
