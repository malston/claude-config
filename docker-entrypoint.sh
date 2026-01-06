#!/usr/bin/env bash
# ABOUTME: Docker entrypoint that runs setup on first start, then executes the command.
# ABOUTME: Tracks setup completion with a marker file to avoid re-running.

set -e

# Always configure git identity if env vars are set (not persisted in volume)
if [ -n "$GIT_USER_NAME" ]; then
    git config --global user.name "$GIT_USER_NAME"
fi
if [ -n "$GIT_USER_EMAIL" ]; then
    git config --global user.email "$GIT_USER_EMAIL"
fi
if [ -n "$GITHUB_TOKEN" ]; then
    git config --global url."https://${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
fi

# Clone dotfiles if repo is set and directory is empty
if [ -n "$DOTFILES_REPO" ] && [ -z "$(ls -A ~/dotfiles 2>/dev/null)" ]; then
    echo "Cloning dotfiles from $DOTFILES_REPO (branch: ${DOTFILES_BRANCH:-main})..."
    git clone --branch "${DOTFILES_BRANCH:-main}" "$DOTFILES_REPO" ~/dotfiles
    echo "  ✓ Dotfiles cloned to ~/dotfiles"

    # Run install script if it exists
    if [ -f ~/dotfiles/install.sh ]; then
        echo "Running dotfiles install script..."
        cd ~/dotfiles && ./install.sh
    fi
fi

# Use persistent state directory if available, otherwise fall back to home
STATE_DIR="$HOME/.claude-state"
if [ -d "$STATE_DIR" ]; then
    MARKER_FILE="$STATE_DIR/.setup-complete"
else
    MARKER_FILE="$HOME/.claude-setup-complete"
fi

# Run setup if not already done
if [ ! -f "$MARKER_FILE" ]; then
    echo "First run detected - running setup..."
    echo ""

    # Run setup.sh for MCP servers, git config, env loading
    cd ~/.claude
    SETUP_MODE=auto ./setup.sh

    # Install plugins via claudeup profile
    claudeup setup --profile docker -y

    # Create marker file
    touch "$MARKER_FILE"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi

# Execute the provided command, or start claude if none given
if [ $# -eq 0 ]; then
    exec claude --dangerously-skip-permissions
else
    exec "$@"
fi
