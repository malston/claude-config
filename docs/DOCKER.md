# Running Claude Code in Docker

This directory includes Docker configuration to run Claude Code in a containerized environment with your pre-configured settings and plugins.

## Quick Start

### Build the Image

**Basic build** (without 1Password CLI):
```bash
docker build -t claude-code:latest .
```

**With 1Password CLI** (for MCP server secrets):
```bash
docker build --build-arg INSTALL_1PASSWORD=true -t claude-code:latest .
```

The 1Password CLI is optional and only needed if you use MCP servers that require secrets from 1Password. Without it, you can still use environment variables or mounted `.env` files for secrets.

### Run with Docker Compose (Recommended)

```bash
# Start container with interactive shell
docker-compose run --rm claude /bin/bash

# First time: run setup inside the container
cd ~/.claude && SETUP_MODE=auto ./setup.sh

# Then start Claude
claude
```

### Run with Docker Directly

```bash
# Interactive shell (recommended for first run)
docker run -it --rm \
  -v $(pwd)/workspace:/home/claude/workspace \
  -e GITHUB_TOKEN=${GITHUB_TOKEN} \
  claude-code:latest

# Inside the container, run setup on first use:
cd ~/.claude && SETUP_MODE=auto ./setup.sh

# Then start Claude
claude
```

**Note:** Set `GITHUB_TOKEN` in your environment first:
```bash
export GITHUB_TOKEN=ghp_your_token_here
```

Or pass it directly:
```bash
docker run -it --rm \
  -v $(pwd)/workspace:/home/claude/workspace \
  -e GITHUB_TOKEN=ghp_your_token_here \
  -e CONTEXT7_API_KEY=your_context7_key \
  claude-code:latest
```

## Configuration

### Environment Variables

Set these in `docker-compose.yml` or pass with `-e`:

- `SETUP_MODE=auto` - Install all configured plugins automatically
- `SETUP_MODE=interactive` - Guided setup (requires TTY)
- `ANTHROPIC_API_KEY` - Your Anthropic API key
- `GITHUB_TOKEN` - GitHub personal access token for cloning plugin marketplaces (optional but recommended)
- `CONTEXT7_API_KEY` - Context7 API key for documentation MCP server (optional)

### Secrets and Private Config

**Option 1: Environment Variables**
```bash
# In docker-compose.yml
environment:
  - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
```

**Option 2: Mount .env file**
```bash
# Uncomment in docker-compose.yml
volumes:
  - ./config/.env:/home/claude/.claude/config/.env:ro
```

**Option 3: Build-time secrets**
```bash
# Create config/.env before building
docker build -t claude-code:latest .
```

### Private Marketplaces

If you have private marketplaces in `plugins/setup-marketplaces.local.json`:

1. **Build-time inclusion** (copied into image):
   ```bash
   # Local file is automatically included during build
   docker build -t claude-code:latest .
   ```

2. **Runtime mount** (not persisted in image):
   ```bash
   docker run -v $(pwd)/plugins/setup-marketplaces.local.json:/home/claude/.claude/plugins/setup-marketplaces.local.json:ro claude-code:latest
   ```

## Persistence

### Persist Plugin Data Across Rebuilds

Uncomment the volume in `docker-compose.yml`:

```yaml
volumes:
  - claude-plugins:/home/claude/.claude/plugins
```

This preserves installed plugins between container restarts.

### Workspace Data

Your workspace is mounted from the host, so files are automatically persistent:

```yaml
volumes:
  - ./workspace:/home/claude/workspace
```

## Customization

### Interactive Mode

For guided setup during first run:

```yaml
environment:
  - SETUP_MODE=interactive
```

Then start with:
```bash
docker-compose run --rm claude /bin/bash
# Inside container:
cd ~/.claude && ./setup.sh
```

### Add Additional Tools

Edit `Dockerfile` to install additional dependencies:

```dockerfile
# After the apt-get install section
RUN apt-get update && apt-get install -y \
    vim \
    tmux \
    htop \
    && rm -rf /var/lib/apt/lists/*
```

### Custom Entrypoint

Override the entrypoint for different workflows:

```bash
# Python development environment
docker run -it --rm \
  --entrypoint python3 \
  claude-code:latest

# Run a script
docker run -it --rm \
  --entrypoint /bin/bash \
  -v $(pwd)/my-script.sh:/tmp/script.sh \
  claude-code:latest /tmp/script.sh
```

## Troubleshooting

### Build Fails During Setup

If `setup.sh` fails during build (e.g., private marketplace not accessible):

**Option 1:** Skip setup during build, run manually:
```dockerfile
# Comment out the RUN setup.sh line
# RUN SETUP_MODE=auto ./setup.sh
```

Then run setup inside the container:
```bash
docker run -it claude-code:latest /bin/bash
cd ~/.claude && SETUP_MODE=auto ./setup.sh
```

**Option 2:** Build with `--network host` for access to private repos:
```bash
docker build --network host -t claude-code:latest .
```

### Plugin Installation Fails

Check the container logs:
```bash
docker-compose logs claude
```

Run setup manually inside container:
```bash
docker-compose run --rm claude /bin/bash
cd ~/.claude
./setup.sh
```

### Secrets Not Available

Verify environment variables are set:
```bash
docker-compose run --rm claude env | grep ANTHROPIC
```

Or check mounted .env file:
```bash
docker-compose run --rm claude cat ~/.claude/config/.env
```

### Container Exits Immediately

The default CMD is `claude --help`. For interactive use:

```bash
# Use docker-compose
docker-compose run --rm claude /bin/bash

# Or override CMD
docker run -it --rm claude-code:latest /bin/bash
```

## Production Use

### Multi-Stage Build (Smaller Image)

For production, create a multi-stage build to reduce image size:

```dockerfile
# Build stage
FROM ubuntu:22.04 AS builder
# ... install and setup ...

# Runtime stage
FROM ubuntu:22.04
COPY --from=builder /home/claude/.claude /home/claude/.claude
# ... minimal runtime deps ...
```

### Security Hardening

1. **Run as non-root** (already configured)
2. **Read-only root filesystem**:
   ```bash
   docker run --read-only -v /tmp --tmpfs /home/claude/.claude/tmp claude-code:latest
   ```
3. **Drop capabilities**:
   ```bash
   docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE claude-code:latest
   ```

### CI/CD Integration

**GitHub Actions Example:**
```yaml
name: Claude Code CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build Claude Code image
        run: docker build -t claude-code:latest .
      - name: Run tests with Claude
        run: docker run --rm claude-code:latest test
```

## Architecture

The Docker image includes:

- **Base**: Ubuntu 22.04
- **Runtime**: Python 3, Node.js 20, direnv
- **Claude PM**: Installed via setup.sh
- **Configuration**: Your .claude directory (CLAUDE.md, settings.json, hooks, skills, etc.)
- **Plugins**: Installed during build via `SETUP_MODE=auto`
- **Workspace**: Mounted volume at `/home/claude/workspace`

**Build time**: ~5-10 minutes (depending on plugin count)
**Image size**: ~2-3 GB (base + dependencies + plugins)

## Examples

### Development Environment

```bash
# Start persistent dev container
docker-compose up -d

# Enter the container
docker-compose exec claude /bin/bash

# Your workspace is at ~/workspace (mounted from host)
cd ~/workspace
claude chat "Help me refactor this code"
```

### Automated Script Execution

```bash
# Run Claude Code automation
docker run --rm \
  -v $(pwd)/data:/home/claude/workspace/data \
  -e ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
  claude-code:latest \
  chat "Analyze the CSV files in workspace/data and create a summary report"
```

### Testing in Clean Environment

```bash
# Test your config in isolation
docker build -t claude-test .
docker run --rm -it claude-test /bin/bash

# Verify plugins loaded
cd ~/.claude
claude plugin list
```

## Maintenance

### Rebuild After Config Changes

```bash
# Rebuild image
docker-compose build --no-cache

# Or with Docker
docker build --no-cache -t claude-code:latest .
```

### Update Plugins

**Option 1:** Rebuild image
```bash
docker-compose build
```

**Option 2:** Update inside running container
```bash
docker-compose exec claude /bin/bash
cd ~/.claude/scripts
./check-updates.sh
```

### Clean Up

```bash
# Stop and remove containers
docker-compose down

# Remove image
docker rmi claude-code:latest

# Remove volumes
docker volume rm claude-code_claude-plugins
```
