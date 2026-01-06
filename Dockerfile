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
# Note: Don't run claude during build as it triggers interactive setup wizard
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    # Verify the binary exists (don't run it yet)
    test -f /root/.local/bin/claude && echo "Claude CLI binary installed" || exit 1

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

# Create a non-root user and copy Claude CLI
RUN useradd -m -s /bin/bash claude && \
    mkdir -p /home/claude/.local/bin && \
    cp /root/.local/bin/claude /home/claude/.local/bin/claude && \
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

# Note: setup.sh is not run during build because it requires interactive input
# from Claude CLI's first-run wizard. Run it manually after starting the container:
#   docker run -it --rm claude-code:latest /bin/bash
#   cd ~/.claude && SETUP_MODE=auto ./setup.sh

# Create workspace directory
RUN mkdir -p /home/claude/workspace
WORKDIR /home/claude/workspace

# Default command: provide helpful instructions
# Users can override with: docker run -it claude-code:latest /bin/bash
CMD ["/bin/bash", "-c", "echo 'Welcome to Claude Code Docker Environment!' && echo '' && echo 'To set up Claude Code and plugins, run:' && echo '  cd ~/.claude && SETUP_MODE=auto ./setup.sh' && echo '' && echo 'Then start Claude:' && echo '  claude' && echo '' && exec /bin/bash"]
