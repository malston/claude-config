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
# Start Claude (setup runs automatically on first start)
docker-compose run --rm claude
```

The container automatically:
1. Detects first run and executes setup.sh
2. Installs marketplaces and plugins via claudeup
3. Starts Claude with `--dangerously-skip-permissions`

To get a shell instead of starting Claude:

```bash
docker-compose run --rm claude /bin/bash
```

### Run with Docker Directly

```bash
docker run -it --rm \
  -v $(pwd)/workspace:/home/claude/workspace \
  -e GITHUB_TOKEN=${GITHUB_TOKEN} \
  -e CONTEXT7_API_KEY=${CONTEXT7_API_KEY} \
  claude-code:latest
```

**Note:** Set `GITHUB_TOKEN` and `CONTEXT7_API_KEY` in your environment first:

```bash
export GITHUB_TOKEN=ghp_your_token_here
export CONTEXT7_API_KEY=your_context7_key
```

## Configuration

### Environment Variables

Set these in `docker-compose.yml` or pass with `-e`:

- `ANTHROPIC_API_KEY` - Your Anthropic API key
- `GITHUB_TOKEN` - GitHub personal access token for cloning marketplaces and pushing code
- `GIT_USER_NAME` - Git commit author name (e.g., "Your Name")
- `GIT_USER_EMAIL` - Git commit author email (e.g., "you@example.com")
- `CONTEXT7_API_KEY` - Context7 API key for documentation MCP server (optional)

### Git Setup

To commit and push code from inside the container, set these environment variables before running:

```bash
export GITHUB_TOKEN=ghp_your_token_here
export GIT_USER_NAME="Your Name"
export GIT_USER_EMAIL="you@example.com"

docker-compose -f docker-compose.yml -f docker-compose.auth.yml run --rm claude /bin/bash
```

Or add to your shell profile (~/.zshrc or ~/.bashrc) for persistence.

### Authentication

To avoid re-authenticating Claude Code on each container start, use the auth override file:

```bash
# With credentials (uses ~/.claude.json from host)
docker-compose -f docker-compose.yml -f docker-compose.auth.yml run --rm claude

# Without credentials (will prompt for login)
docker-compose run --rm claude
```

Or create a shell alias for convenience:

```bash
alias claude-docker='docker-compose -f docker-compose.yml -f docker-compose.auth.yml run --rm claude'
```

The override file (`docker-compose.auth.yml`) mounts your `~/.claude.json` into the container (read-write so Claude can refresh tokens).

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

### Claude Config (Marketplaces, Plugins, Settings)

The `claude-config` volume persists the entire `~/.claude` directory, including:
- Marketplace registrations
- Installed plugin cache
- User settings (settings.json)
- MCP server configurations

```yaml
volumes:
  - claude-config:/home/claude/.claude
```

On first run, Docker copies the image's config into the empty volume, then setup adds marketplaces and plugins. Subsequent runs use the persisted data.

To reset config and reinstall everything:

```bash
docker-compose down -v  # Removes all volumes
docker-compose run --rm claude
```

### Setup State

The `claude-state` volume tracks whether setup has completed:

```yaml
volumes:
  - claude-state:/home/claude/.claude-state
```

To force re-running setup without losing installed plugins:

```bash
docker volume rm claude_claude-state
docker-compose run --rm claude
```

### Workspace Data

Your workspace is mounted from the host (defaults to `~/workspace`), so files are automatically persistent:

```yaml
volumes:
  - ${WORKSPACE:-~/workspace}:/home/claude/workspace
```

Override the workspace location:

```bash
# Mount a specific project
WORKSPACE=~/workspace/my-project docker-compose run --rm claude

# Mount entire projects directory
WORKSPACE=~/projects docker-compose run --rm claude
```

## Customization

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

## Managing Context Usage

MCP tools use ~53k tokens (26% of context) with all plugins enabled. See the main [README.md](../README.md#managing-context-usage) for detailed guidance on disabling heavy Playwright-based plugins to save ~45k tokens.

## Troubleshooting

### Setup Fails on First Run

If setup fails (e.g., private marketplace not accessible), you can:

**Option 1:** Run setup manually inside the container:

```bash
docker-compose run --rm claude /bin/bash
cd ~/.claude && ./setup.sh
```

**Option 2:** Force re-run setup after fixing the issue:

```bash
docker volume rm claude_claude-state
docker-compose run --rm claude
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

The default command starts Claude interactively. If the container exits immediately:

1. Ensure you're running with `-it` flags for interactive mode
2. Check that ANTHROPIC_API_KEY is set
3. For a shell instead: `docker run -it --rm claude-code:latest /bin/bash`

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
- **Runtime**: Python 3, Node.js 20, Bun, direnv
- **Claude CLI**: Pre-installed
- **claudeup**: Pre-installed, manages plugins and marketplaces
- **Configuration**: Your .claude directory (CLAUDE.md, settings.json, hooks, skills, etc.)
- **Entrypoint**: Runs setup.sh automatically on first start, tracks completion with marker file
- **Plugins**: Installed during first run via entrypoint
- **Workspace**: Mounted volume at `/home/claude/workspace`

**Build time**: ~3-5 minutes
**Image size**: ~1.5-2 GB

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
claudeup doctor
```

## Testing Changes

When modifying Docker configuration, follow this workflow to test from a clean state:

### 1. Clean Up Existing State

```bash
# Stop any running containers and remove volumes
docker-compose down -v

# Verify volumes are removed (compose prefixes with project name)
docker volume ls | grep claude
# Should not show: claude_claude-state or claude_claude-config
```

### 2. Rebuild the Image

```bash
# Rebuild with no cache to ensure changes are picked up
docker-compose build --no-cache

# Or with Docker directly
docker build --no-cache -t claude-code:latest .
```

### 3. Test Fresh Setup

```bash
# Run and verify automatic setup executes
docker-compose run --rm claude /bin/bash

# You should see "First run detected - running setup..."
# followed by setup.sh output and claudeup setup output
```

### 4. Test Subsequent Runs

```bash
# Run again - setup should be skipped (marker file persisted)
docker-compose run --rm claude /bin/bash

# Should NOT see "First run detected..."
# Should go directly to bash prompt
```

### Common Issues

**Setup runs every time:**
- Volume not persisting - check `docker volume ls | grep claude`
- Wrong volume name - compose uses `<project>_<volume>` format

**Setup doesn't run at all:**
- Stale marker file in volume - run `docker-compose down -v` to reset

**Changes not taking effect:**
- Image not rebuilt - run `docker-compose build --no-cache`
- Using cached layers - ensure you're building the right context

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
claudeup marketplace update
claudeup plugin update
```

### Clean Up

```bash
# Stop and remove containers
docker-compose down

# Remove image
docker rmi claude-code:latest

# Remove all volumes (full reset)
docker-compose down -v

# Or remove individual volumes
docker volume rm claude_claude-state   # Reset setup state only
docker volume rm claude_claude-config  # Reset plugins and marketplaces
```
