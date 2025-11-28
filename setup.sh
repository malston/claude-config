#!/bin/bash
# Setup script for Claude Code configuration
# Run this after cloning the repo to a new machine

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
ENV_FILE="$CONFIG_DIR/.env"

echo "Setting up Claude Code configuration..."
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

for server in config.get('servers', []):
    name = server['name']
    command = server['command']
    args = server['args']
    env_required = server.get('env_required', [])

    # Check for required env vars
    missing_env = [e for e in env_required if not os.environ.get(e)]
    if missing_env:
        print(f"  Skipping {name}: missing env vars {missing_env}")
        continue

    # Build the claude mcp add command
    cmd = ['claude', 'mcp', 'add', name, '-s', 'user', '--']
    cmd.append(command)

    # Substitute env vars in args
    expanded_args = []
    for arg in args:
        if arg.startswith('$'):
            env_var = arg[1:]
            expanded_args.append(os.environ.get(env_var, arg))
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

# Add plugin marketplaces from known_marketplaces.json
echo "Adding plugin marketplaces..."
if [ -f "$SCRIPT_DIR/plugins/known_marketplaces.json" ]; then
    python3 << 'PYTHON_SCRIPT'
import json
import subprocess
import os

script_dir = os.environ.get('SCRIPT_DIR', '.')
config_path = os.path.join(script_dir, 'plugins', 'known_marketplaces.json')

with open(config_path) as f:
    marketplaces = json.load(f)

for name, config in marketplaces.items():
    source = config.get('source', {})
    source_type = source.get('source')

    if source_type == 'github':
        repo = source.get('repo')
        if repo:
            print(f"  Adding {name} from {repo}...")
            try:
                result = subprocess.run(
                    ['claude', 'plugin', 'marketplace', 'add', repo],
                    check=True, capture_output=True
                )
                print(f"  ✓ {name} added")
            except subprocess.CalledProcessError as e:
                if b'already' in e.stderr.lower() or b'already' in e.stdout.lower():
                    print(f"  ✓ {name} already added")
                else:
                    print(f"  ✗ {name} failed")
    elif source_type == 'git':
        url = source.get('url')
        if url:
            print(f"  Adding {name} from {url}...")
            try:
                subprocess.run(
                    ['claude', 'plugin', 'marketplace', 'add', url],
                    check=True, capture_output=True
                )
                print(f"  ✓ {name} added")
            except subprocess.CalledProcessError:
                print(f"  ✓ {name} already added or failed")
PYTHON_SCRIPT
else
    echo "  No known_marketplaces.json found, skipping"
fi

echo ""
echo "Setup complete!"
echo ""

# Check for missing env vars and warn
python3 << 'PYTHON_SCRIPT'
import json
import os

config_path = os.path.join(os.environ.get('CONFIG_DIR', 'config'), 'mcp-servers.json')
if os.path.exists(config_path):
    with open(config_path) as f:
        config = json.load(f)

    missing = []
    for server in config.get('servers', []):
        for env_var in server.get('env_required', []):
            if not os.environ.get(env_var):
                missing.append((server['name'], env_var, server.get('note', '')))

    if missing:
        print("Manual steps required:")
        print("")
        for name, env_var, note in missing:
            print(f"  • Set {env_var} for {name}")
            if note:
                print(f"    {note}")
        print("")
        print("  1. Copy config/env.example to config/.env")
        print("  2. Fill in the values")
        print("  3. Re-run ./setup.sh")
PYTHON_SCRIPT

echo ""
echo "To install plugins: claude plugin install <plugin>@<marketplace>"
echo "To list plugins:    claude plugin marketplace list"
