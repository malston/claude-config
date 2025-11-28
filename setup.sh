#!/bin/bash
# Setup script for Claude Code configuration
# Run this after cloning the repo to a new machine

set -e

echo "Setting up Claude Code configuration..."

# Install user-scoped MCP servers
echo "Adding MCP servers..."
claude mcp add chrome-devtools -s user -- npx -y chrome-devtools-mcp@latest

# Add marketplaces
echo "Adding plugin marketplaces..."
claude plugin marketplace add malston/tanzu-cf-architect-claude-plugin

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Run 'claude plugin marketplace list' to see available plugins"
echo "  2. Run 'claude plugin install <plugin>@<marketplace>' to install plugins"
echo "  3. Review settings.json and adjust enabledPlugins as needed"
