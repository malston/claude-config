# ABOUTME: Dockerfile for running Claude Code with pre-configured settings and plugins
# ABOUTME: Builds a containerized environment with this repository's configuration

FROM ubuntu:22.04

# Avoid interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    python3 \
    python3-pip \
    jq \
    direnv \
    ca-certificates \
    gnupg \
    unzip \
    vim \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (required for some Claude Code plugins)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
# Note: Don't run claude during build as it triggers interactive setup wizard
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    # Verify the binary exists (don't run it yet)
    test -f /root/.local/bin/claude && echo "Claude CLI binary installed" || exit 1

# Install claudeup
RUN curl -fsSL https://raw.githubusercontent.com/claudeup/claudeup/main/install.sh | bash && \
    test -f /root/.local/bin/claudeup && echo "claudeup binary installed" || exit 1

# Install Bun (required for Claude Code plugins)
RUN curl -fsSL https://bun.sh/install | bash && \
    test -f /root/.bun/bin/bun && echo "Bun installed" || exit 1

# Install 1Password CLI (optional, for MCP secrets)
ARG INSTALL_1PASSWORD=false
RUN if [ "$INSTALL_1PASSWORD" = "true" ]; then \
    ARCH=$(dpkg --print-architecture) && \
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
      gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg && \
    echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/${ARCH} stable main" | \
      tee /etc/apt/sources.list.d/1password.list && \
    apt-get update && \
    apt-get install -y 1password-cli && \
    rm -rf /var/lib/apt/lists/*; \
    fi

# Create a non-root user and copy Claude CLI, claudeup, and Bun
RUN useradd -m -s /bin/bash claude && \
    mkdir -p /home/claude/.local/bin && \
    cp /root/.local/bin/claude /home/claude/.local/bin/claude && \
    cp /root/.local/bin/claudeup /home/claude/.local/bin/claudeup && \
    cp -r /root/.bun /home/claude/.bun && \
    chown -R claude:claude /home/claude && \
    echo "claude ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch to non-root user
USER claude
WORKDIR /home/claude

# Add local bin and Bun to PATH
ENV PATH="/home/claude/.local/bin:/home/claude/.bun/bin:${PATH}"

# Copy Claude Code configuration
COPY --chown=claude:claude . /home/claude/.claude/

# Copy claudeup docker profile (named docker.json so profile name is "docker")
RUN mkdir -p /home/claude/.claudeup/profiles
COPY --chown=claude:claude config/docker-profile.json /home/claude/.claudeup/profiles/docker.json

# Create workspace, state, and temp directories
RUN mkdir -p /home/claude/workspace /home/claude/.claude-state /home/claude/.claude/tmp
WORKDIR /home/claude/workspace

# Entrypoint runs setup on first start, then executes command
ENTRYPOINT ["/home/claude/.claude/docker-entrypoint.sh"]

# Default: start claude (entrypoint handles setup automatically)
# Override with: docker run -it claude-code:latest /bin/bash
CMD []
