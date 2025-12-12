# Cross-Platform Installer Design

**Date:** 2025-12-06
**Status:** Approved
**Primary Use Case:** Development environment (interactive Docker containers)
**Platform Support:** Ubuntu/Debian (explicit), macOS (maintained), others (may work)

## Overview

Enhance setup.sh and Dockerfile to support non-macOS environments by:

1. Installing Claude CLI using Anthropic's official installer
2. Making 1password-cli and direnv optional with graceful detection
3. Showing platform-appropriate install instructions (apt-get vs brew)
4. Maintaining existing macOS support

## Architecture

### Platform Detection

Extend the existing OS detection (currently lines 72-77 for claudeup):

- Detect: Ubuntu/Debian (via apt-get availability), macOS (via brew availability)
- Store platform info in variables: `$OS` (darwin/linux), `$PKG_MANAGER` (apt-get/brew)

### Installation Flow

```
1. Detect platform and package manager
2. Install Claude CLI (via official installer - platform agnostic)
3. Install claudeup (existing logic - already cross-platform)
4. Load environment / configure MCP servers (existing)
5. Install marketplaces (existing)
6. Install plugins (existing)
7. Check optional tools (1password-cli, direnv)
   - If found: use them
   - If missing: show platform-appropriate install instructions
8. Health check (existing)
```

**Key principle:** Fail gracefully. Missing optional tools show helpful messages but don't block setup. Missing required tools (Claude CLI, claudeup) fail with clear instructions.

## Claude CLI Installation

### Installation Method

Use Anthropic's official installer which works cross-platform:

```bash
curl -fsSL https://anthropic.com/install.sh | bash
```

Or similar. Verify the actual URL from Anthropic's documentation.

### Implementation in setup.sh

Add before the claudeup installation section (around line 67):

```bash
echo "Installing Claude Code CLI..."

# Check if already installed
if command -v claude &> /dev/null; then
    CURRENT_VERSION=$(claude --version 2>/dev/null || echo "unknown")
    echo "  ✓ Claude CLI already installed ($CURRENT_VERSION)"
else
    # Use official installer
    if curl -fsSL OFFICIAL_INSTALLER_URL | bash; then
        echo "  ✓ Claude CLI installed"
    else
        echo "  ✗ Failed to install Claude CLI"
        echo "  Please install manually: https://docs.anthropic.com/claude-code/installation"
        exit 1
    fi
fi
```

### Dockerfile Changes

Add the same installation step before the setup.sh run (around line 42):

```dockerfile
# Install Claude Code CLI
RUN curl -fsSL OFFICIAL_INSTALLER_URL | bash
```

Ensures Claude is available before setup.sh uses it for MCP servers and plugins.

## Optional Dependencies Handling

### For 1Password CLI

Replace the current hardcoded `brew install 1password-cli` messages (lines 162, 570) with platform-aware helpers:

```bash
# Helper function for install instructions
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
```

### For direnv

Similar pattern for direnv (line 633):

```bash
show_direnv_install() {
    if command -v apt-get &> /dev/null; then
        echo "  Install direnv: sudo apt-get install direnv"
    elif command -v brew &> /dev/null; then
        echo "  Install direnv: brew install direnv"
    else
        echo "  Install direnv: https://direnv.net/docs/installation.html"
    fi
}
```

Call these functions when the tool is missing but needed. The MCP server and auto-update sections already handle missing tools gracefully - this change improves the messaging.

## Dockerfile Changes

### Add Claude CLI installation

After Node.js install, before user creation:

```dockerfile
# Install Claude Code CLI
RUN curl -fsSL OFFICIAL_INSTALLER_URL | bash && \
    # Verify installation
    claude --version
```

### Add 1Password CLI (Optional)

Since 1Password CLI requires adding a repository, make it optional with a build arg:

```dockerfile
# Install 1Password CLI (optional, for MCP secrets)
ARG INSTALL_1PASSWORD=false
RUN if [ "$INSTALL_1PASSWORD" = "true" ]; then \
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
      gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg && \
    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main' | \
      tee /etc/apt/sources.list.d/1password.list && \
    apt-get update && \
    apt-get install -y 1password-cli && \
    rm -rf /var/lib/apt/lists/*; \
    fi
```

### direnv

Already installed (line 16) - no changes needed.

### Build Examples

```bash
# Without 1Password
docker build -t claude-code:latest .

# With 1Password
docker build --build-arg INSTALL_1PASSWORD=true -t claude-code:latest .
```

This keeps the base image lean while allowing users who need 1Password to add it.

## Error Handling & User Feedback

### Required vs Optional Failures

**Required tools** (Claude CLI, claudeup) must exit with clear errors:

```bash
if ! command -v claude &> /dev/null; then
    echo "✗ ERROR: Claude CLI installation failed"
    echo "  Manual installation: https://docs.anthropic.com/claude-code/installation"
    exit 1
fi
```

**Optional tools** (1password-cli, direnv) skip gracefully with helpful messages:

```bash
if ! command -v op &> /dev/null; then
    echo "⚠ 1Password CLI not found - MCP secrets will be skipped"
    show_1password_install
    echo ""
fi
```

### User Feedback Improvements

**Platform detection visibility:**

```bash
echo "Detected platform: $OS ($PKG_MANAGER)"
```

**Installation progress:**

```bash
echo "Installing Claude CLI..."
echo "  ✓ Claude CLI installed (version X.Y.Z)"
```

**Summary at end:**

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Setup Summary:"
echo "  ✓ Claude CLI (required)"
echo "  ✓ claudeup (required)"
echo "  ✓ direnv (optional)"
echo "  ⚠ 1Password CLI (optional, not installed)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

Gives users clear visibility into what worked, what didn't, and what they need to do next.

## Implementation Notes

1. First verify the actual Anthropic official installer URL
2. Test on Ubuntu 22.04 (matches Dockerfile base)
3. Verify macOS compatibility maintained
4. Update DOCKER.md with new build args and examples
5. Consider adding platform detection output to setup.sh for debugging
