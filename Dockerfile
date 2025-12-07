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
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (required for some Claude Code plugins)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    # Verify installation - claude is installed to /root/.local/bin during build
    export PATH="/root/.local/bin:$PATH" && \
    claude --version

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

# Create a non-root user
RUN useradd -m -s /bin/bash claude && \
    mkdir -p /home/claude/.local/bin && \
    chown -R claude:claude /home/claude

# Switch to non-root user
USER claude
WORKDIR /home/claude

# Add local bin to PATH
ENV PATH="/home/claude/.local/bin:${PATH}"

# Copy Claude Code configuration
COPY --chown=claude:claude . /home/claude/.claude/

# Set working directory to config
WORKDIR /home/claude/.claude

# Run setup in auto mode to install all configured marketplaces and plugins
# This will install claude-pm, configure MCP servers, and set up plugins
RUN SETUP_MODE=auto ./setup.sh || echo "Setup completed with warnings"

# Create workspace directory
RUN mkdir -p /home/claude/workspace
WORKDIR /home/claude/workspace

# Default command: run claude code
# Users can override this to run specific commands
ENTRYPOINT ["claude"]
CMD ["--help"]
