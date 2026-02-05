# Claude Sandbox: Isolated Configuration Testing with Dev Containers

## Problem

Testing different Claude Code configurations (plugins, skills, hooks, agents) requires switching the active `~/.claude` directory. The current approach uses a symlink script (`switch-claude-config`) to point `~/.claude` at different config directories. This creates three problems:

1. **Path resolution breaks the abstraction.** Claude Code resolves the symlink to the real path, so `~/.claude.json` accumulates entries like `/Users/markalston/.claude_config_malston` instead of `/Users/markalston/.claude`.
2. **The symlink approach bypasses `CLAUDE_CONFIG_DIR`.** Claude Code provides this env var for non-default config directories.
3. **Hooks and skills run against the host toolchain.** The system provides no isolation. Configuration behavior in different environments cannot be tested.

## Goals

- Test different combinations of plugins, skills, hooks, agents, and commands in isolation.
- Support extended working sessions: real coding work, not smoke tests.
- Keep project files accessible and git-integrated.
- Launch from the terminal; attach VS Code for visual diffing.
- Preserve clean working directories and git state on the host.

## Architecture

Three layers separate concerns:

1. **claudeup profiles** define what gets installed: plugins, marketplaces, settings. These live in `~/.claudeup/profiles/` and serve as the source of truth for a configuration.
2. **A base Docker image** provides Claude Code, claudeup, Node.js, and common dev tools. It contains no profiles or project-specific tooling.
3. **A launcher script** (`claude-sandbox`) orchestrates the session: creates a git worktree for the project, generates a `devcontainer.json` from a template, and starts the container with `devcontainer up`.

Claude Code runs inside the container. Hooks and skills execute against the container's toolchain, providing true isolation.

## Base Docker Image

The image provides a foundation for any project and profile combination.

```dockerfile
FROM node:22

ARG TZ=America/Denver
ENV TZ="$TZ"

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget ca-certificates gnupg2 \
    git git-lfs gh \
    procps htop \
    jq yq \
    ripgrep fd-find \
    build-essential make \
    python3 \
    nano vim \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1

ARG USERNAME=node

RUN mkdir /commandhistory && \
    touch /commandhistory/.bash_history && \
    chown -R $USERNAME /commandhistory && \
    echo 'export PATH=$PATH:/home/node/.npm-global/bin:/home/node/.local/bin:/home/node/.bun/bin' >> /home/node/.bashrc && \
    echo 'export HISTFILE=/commandhistory/.bash_history' >> /home/node/.bashrc

ENV DEVCONTAINER=true

RUN mkdir -p /home/node/.config/gh /home/node/.claude \
    /home/node/.claudeup/profiles /home/node/.claude-mem \
    /home/node/dotfiles /home/node/.npm-global/lib \
    /home/node/.aws /home/node/.local/bin && \
    chown -R node:node /home/node

WORKDIR /workspaces
USER node

ENV NPM_CONFIG_PREFIX=/home/node/.npm-global
ENV PATH=$PATH:/home/node/.npm-global/bin:/home/node/.local/bin:/home/node/.bun/bin

# Bun (required by some Claude Code plugins)
RUN curl -fsSL https://bun.sh/install | bash

RUN git config --global core.excludesfile ~/.gitignore_global && \
    echo ".claude/settings.local.json" > /home/node/.gitignore_global

# Claude Code (official installer)
RUN curl -fsSL https://claude.ai/install.sh | bash

USER root

COPY --chmod=755 init-claude-config.sh /usr/local/bin/
COPY --chmod=755 init-claudeup.sh /usr/local/bin/

USER node
```

Design decisions:

- **The official installer bakes Claude Code into the image.** `claude upgrade` at container start picks up updates without rebuilding the image.
- **The image contains no profiles or project tools.** `init-claudeup.sh` applies profiles at container start. Devcontainer features add project-specific tools (Go, Rust, etc.) at launch time.
- **Rebuild cadence is low.** Rebuilds are needed only for base tool updates or major Node.js LTS bumps.

## Generated devcontainer.json

The launcher generates a `devcontainer.json` in the worktree's `.devcontainer/` directory from a template. Generation time substitutes placeholders.

Template (`devcontainer-base/devcontainer.template.json`):

```jsonc
{
  "name": "Claude Sandbox - {{PROJECT_NAME}} ({{PROFILE}})",
  "image": "claude-sandbox:latest",
  "features": {
    // Injected by launcher based on --feature flags
  },
  "remoteUser": "node",
  "mounts": [
    "source=claude-sandbox-bashhistory-{{SANDBOX_ID}},target=/commandhistory,type=volume",
    "source=claude-sandbox-config-{{SANDBOX_ID}},target=/home/node/.claude,type=volume",
    "source=claude-sandbox-claudeup-{{SANDBOX_ID}},target=/home/node/.claudeup,type=volume",
    "source=claude-sandbox-npm-{{SANDBOX_ID}},target=/home/node/.npm-global,type=volume",
    "source=claude-sandbox-local-{{SANDBOX_ID}},target=/home/node/.local,type=volume",
    "source=claude-sandbox-bun-{{SANDBOX_ID}},target=/home/node/.bun,type=volume",
    "source={{HOME}}/.claude-mem,target=/home/node/.claude-mem,type=bind",
    "source={{HOME}}/.ssh,target=/home/node/.ssh,type=bind,readonly",
    "source={{HOME}}/.claude.json,target=/home/node/.claude.json,type=bind"
  ],
  "containerEnv": {
    "CLAUDE_CONFIG_DIR": "/home/node/.claude",
    "CLAUDE_PROFILE": "{{PROFILE}}",
    "NODE_OPTIONS": "--max-old-space-size=4096",
    "GIT_USER_NAME": "{{GIT_USER_NAME}}",
    "GIT_USER_EMAIL": "{{GIT_USER_EMAIL}}",
    "GITHUB_TOKEN": "{{GITHUB_TOKEN}}",
    "CONTEXT7_API_KEY": "{{CONTEXT7_API_KEY}}"
  },
  "workspaceFolder": "/workspaces/{{PROJECT_NAME}}",
  "postCreateCommand": "claude upgrade && /usr/local/bin/init-claude-config.sh && /usr/local/bin/init-claudeup.sh",
  "waitFor": "postCreateCommand"
}
```

Key properties:

- **`SANDBOX_ID` derives from `<project>-<profile>`** (e.g., `diego-capacity-analyzer-frontend-heavy`). Docker volumes are scoped to this ID. Restarting the same project+profile reuses existing volumes; a different profile gets fresh volumes.
- **The host bind-mounts `~/.claude.json`** for authentication state.
- **The host bind-mounts `~/.claude-mem`** so memory persists across sandbox sessions.
- **The host bind-mounts `~/.ssh` read-only** for git access.
- **The launcher injects devcontainer features** based on `--feature` flags (e.g., `--feature go:1.23`).

## Init Scripts

Two scripts run at container creation, generalized from the existing `diego-capacity-analyzer` devcontainer setup.

### init-claude-config.sh

Configures git identity, GitHub auth, dotfiles, and the `~/.claude` directory structure. This uses the same logic as the existing script, with one change: settings, CLAUDE.md templates, and enabled.json come from the claudeup profile or from dotfiles. The image no longer bakes these in.

### init-claudeup.sh

Installs claudeup if missing and applies the profile specified by the `CLAUDE_PROFILE` env var:

```bash
claudeup setup --profile "$CLAUDE_PROFILE" -y
```

A marker file (`~/.claudeup/.setup-complete`) skips re-running on container restarts.

## Launcher Script (`claude-sandbox`)

A bash script in `scripts/` manages the full sandbox lifecycle.

### `claude-sandbox start`

```bash
claude-sandbox start \
  --project ~/code/diego-capacity-analyzer \
  --profile frontend-heavy \
  --branch feature/new-dashboard \
  --feature go:1.23
```

Steps:

1. **Validate.** Verify project path is a git repo, profile exists, and `devcontainer` CLI is installed.
2. **Create worktree.** Path: `<project-dir>-<profile>/` (e.g., `~/code/diego-capacity-analyzer-frontend-heavy/`). Create the branch if it does not exist.
3. **Generate devcontainer.json.** Read template, substitute placeholders, inject features, and pull env vars from host. Write to `<worktree>/.devcontainer/devcontainer.json`. Add `.devcontainer/` to the worktree's local `.gitignore`.
4. **Copy init scripts.** Copy `init-claude-config.sh` and `init-claudeup.sh` into the worktree's `.devcontainer/`.
5. **Launch.** Run `devcontainer up --workspace-folder <worktree-path>`. Record the container ID in `~/.claude-sandboxes/<sandbox-id>`.
6. **Report.** Print status and usage hints.

### `claude-sandbox exec`

Opens an interactive shell inside the container:

```bash
claude-sandbox exec                    # infers sandbox from cwd
claude-sandbox exec --sandbox <name>   # explicit
```

### `claude-sandbox claude`

Runs Claude Code inside the container:

```bash
claude-sandbox claude                        # interactive session
claude-sandbox claude "explain this function" # one-shot prompt
```

### `claude-sandbox attach`

Opens VS Code attached to the running container:

```bash
claude-sandbox attach
```

### `claude-sandbox list`

Shows all active sandboxes with project, profile, and status:

```
SANDBOX                                      PROJECT                    PROFILE          STATUS
diego-capacity-analyzer-frontend-heavy       diego-capacity-analyzer    frontend-heavy   running
diego-capacity-analyzer-minimal              diego-capacity-analyzer    minimal          stopped
```

### `claude-sandbox stop`

Stops the container. Docker volumes persist so the next `start` with the same project+profile is fast.

### `claude-sandbox cleanup`

Full teardown with confirmation prompt:

1. Stop the container.
2. Remove Docker volumes.
3. Remove the git worktree.
4. Remove metadata from `~/.claude-sandboxes/`.

## Project Files and Git Isolation

Each sandbox operates on a **git worktree**, not the main working directory. This provides:

- **Isolated git state.** Own branch, own index, own HEAD. The main working tree stays clean.
- **Shared object store.** No clone overhead. Branches created in the worktree appear in the main repo.
- **Clean merge path.** Work done in a sandbox produces a branch that can be merged or PR'd through the normal workflow.

The worktree directory name follows the pattern `<project-dir>-<profile>/`, placed alongside the original project directory.

## Repo Directory Layout

```
~/.claude_config_malston/
├── Makefile                          # existing (add sandbox targets)
├── README.md                         # existing
├── setup.sh                          # existing
├── config/
│   └── my-profile.json               # existing claudeup profile
├── scripts/
│   ├── switch-claude-config          # existing (may retire)
│   └── claude-sandbox                # launcher script
├── devcontainer-base/
│   ├── Dockerfile                    # shared base image
│   ├── devcontainer.template.json    # template for generated configs
│   ├── init-claude-config.sh         # config deployment script
│   ├── init-claudeup.sh              # profile application script
│   └── features.json                 # maps shorthand to devcontainer features
└── docs/
    └── plans/
        └── 2026-02-05-claude-sandbox-design.md
```

**`features.json`** maps shorthand names to devcontainer feature URIs:

```json
{
  "go": { "feature": "ghcr.io/devcontainers/features/go:1", "default_version": "1.23" },
  "rust": { "feature": "ghcr.io/devcontainers/features/rust:1", "default_version": "latest" },
  "python": { "feature": "ghcr.io/devcontainers/features/python:1", "default_version": "3.12" }
}
```

**Not in this repo:**

- Profiles remain in `~/.claudeup/profiles/` (claudeup owns those).
- Sandbox runtime state lives in `~/.claude-sandboxes/` (not config, not version-controlled).

## Makefile Targets

```makefile
##@ Sandbox Management

build-sandbox-image:  ## Build the base sandbox Docker image
sandbox-start:        ## Start a sandbox (PROJECT=path PROFILE=name [BRANCH=name] [FEATURE=lang])
sandbox-list:         ## List active sandboxes
sandbox-stop:         ## Stop a sandbox (SANDBOX=name)
sandbox-cleanup:      ## Remove a sandbox and its worktree (SANDBOX=name)
```

These are thin wrappers around `claude-sandbox` for discoverability via `make help`.

## Prerequisites

Host machine requirements:

- **Docker Desktop** (container runtime)
- **`devcontainer` CLI** (`bun install -g @devcontainers/cli`)
- **Git** (worktree management)

## First-Time Setup

```bash
bun install -g @devcontainers/cli
make build-sandbox-image
```

## Typical Session

```bash
# Start a sandbox
claude-sandbox start \
  --project ~/code/diego-capacity-analyzer \
  --profile frontend-heavy \
  --branch feature/new-dashboard \
  --feature go:1.23

# Work in the container
claude-sandbox claude

# Attach VS Code for visual diffing
claude-sandbox attach

# Done for the day
claude-sandbox stop

# Done with this experiment entirely
claude-sandbox cleanup
```

## Future Considerations

- **Project-specific overrides.** A `.claude-sandbox.json` in a project repo could specify default features, ports, and env vars so `--feature` flags become optional.
- **VS Code customizations in the template.** Baseline extensions and settings in the generated `devcontainer.json` for a consistent editor experience.
- **Retiring `switch-claude-config`.** Once sandboxes handle all configuration testing, the symlink script can be removed.
