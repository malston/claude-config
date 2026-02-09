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
3. **A launcher script** (`claude-sandbox`) orchestrates the session: maintains a bare clone of the project, creates a git worktree from it, generates a `devcontainer.json` from a template, and starts the container with `devcontainer up`.

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
    "source={{HOME}}/.claudeup/profiles,target=/home/node/.claudeup/profiles,type=bind,readonly",
    "source=claude-sandbox-npm-{{SANDBOX_ID}},target=/home/node/.npm-global,type=volume",
    "source=claude-sandbox-local-{{SANDBOX_ID}},target=/home/node/.local,type=volume",
    "source=claude-sandbox-bun-{{SANDBOX_ID}},target=/home/node/.bun,type=volume",
    "source={{HOME}}/.claude-mem,target=/home/node/.claude-mem,type=bind",
    "source={{HOME}}/.ssh,target=/home/node/.ssh,type=bind,readonly",
    "source={{HOME}}/.claude.json,target=/home/node/.claude.json,type=bind",
    "source={{BARE_REPO_PATH}},target={{BARE_REPO_PATH}},type=bind",
  ],
  "containerEnv": {
    "CLAUDE_CONFIG_DIR": "/home/node/.claude",
    "CLAUDE_PROFILE": "{{PROFILE}}",
    "NODE_OPTIONS": "--max-old-space-size=4096",
    "GIT_USER_NAME": "{{GIT_USER_NAME}}",
    "GIT_USER_EMAIL": "{{GIT_USER_EMAIL}}",
    "GITHUB_TOKEN": "{{GITHUB_TOKEN}}",
    "CONTEXT7_API_KEY": "{{CONTEXT7_API_KEY}}",
  },
  "workspaceFolder": "/workspaces/{{DISPLAY_NAME}}",
  "postCreateCommand": "claude upgrade && /usr/local/bin/init-claude-config.sh && /usr/local/bin/init-claudeup.sh",
  "waitFor": "postCreateCommand",
}
```

Key properties:

- **`SANDBOX_ID` is a UUID** generated at sandbox creation. Docker volumes are scoped to this UUID, guaranteeing uniqueness even for multiple sandboxes of the same project+profile.
- **`DISPLAY_NAME` is the human-readable name** (default: `<project>-<profile>`, or overridden via `--name`). Used as the workspace folder name inside the container and as the primary way to reference sandboxes.
- **The host bind-mounts `~/.claude.json`** for authentication state.
- **The host bind-mounts `~/.claude-mem`** so memory persists across sandbox sessions.
- **The host bind-mounts `~/.ssh` read-only** for git access.
- **The host bind-mounts `~/.claudeup/profiles` read-only** inside the claudeup volume so `claudeup setup` can find profiles.
- **The host bind-mounts the bare clone** at its host path so the worktree's `.git` file (which contains a `gitdir:` pointer to the bare repo's `worktrees/` directory) resolves inside the container.
- **The launcher injects devcontainer features** based on `--feature` flags (e.g., `--feature go:1.23`).

## Init Scripts

Two scripts run at container creation.

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
  --project ~/code/myapp \
  --profile frontend-heavy \
  --branch feature/new-dashboard \
  --feature go:1.23 \
  --name myapp-dashboard
```

Steps:

1. **Validate.** Verify project path is a git repo (canonicalized via `pwd -P`), profile exists, and `devcontainer` CLI is installed.
2. **Generate UUID.** Each sandbox gets a unique ID via `uuidgen`.
3. **Ensure bare clone.** Create or refresh a bare clone of the project's upstream in `~/.claude-sandboxes/repos/<project>.git`. Multiple sandboxes of the same project share this clone. A source marker file prevents project name collisions.
4. **Compute display name.** Default: `<project>-<profile>`. The `--name` flag overrides this. Collisions with existing sandboxes are disambiguated with a short UUID suffix.
5. **Create worktree.** From the bare clone into `~/.claude-sandboxes/workspaces/<display-name>/`. If the branch is already checked out in another worktree, a short UUID suffix is appended to the branch name.
6. **Generate devcontainer.json.** Read template, substitute placeholders (including `BARE_REPO_PATH` and `DISPLAY_NAME`), inject features, and pull env vars from host. Write to `<worktree>/.devcontainer/devcontainer.json`.
7. **Copy init scripts.** Copy init scripts into the worktree's `.devcontainer/`.
8. **Launch.** Run `devcontainer up --workspace-folder <worktree-path>`. Save metadata to `~/.claude-sandboxes/state/<uuid>.json`.
9. **Report.** Print sandbox name, short UUID, worktree path, branch, and usage hints.

### `claude-sandbox exec`

Opens an interactive shell inside the container:

```bash
claude-sandbox exec --sandbox myapp-dashboard   # by display name
claude-sandbox exec --sandbox 57af889a          # by partial UUID
claude-sandbox exec                             # infers sandbox from cwd
```

The `--sandbox` flag supports fuzzy matching: display name, partial UUID prefix, project name, or profile name. Ambiguous matches list available options.

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

Shows all sandboxes with display name, short UUID, project, profile, and status:

```
NAME                           ID         PROJECT              PROFILE         STATUS
myapp-frontend-heavy           57af889a   myapp                frontend-heavy  running
myapp-minimal                  a3c2f810   myapp                minimal         stopped
```

### `claude-sandbox stop`

Stops the container. Docker volumes persist so the next `start` is fast.

### `claude-sandbox cleanup`

Full teardown with confirmation prompt:

1. Stop the container.
2. Remove Docker volumes (matched by UUID).
3. Remove the git worktree from the bare repo.
4. Remove metadata from `~/.claude-sandboxes/state/`.
5. If the bare repo has no remaining worktrees, offer to remove it.

## Project Files and Git Isolation

Each sandbox operates on a **git worktree** created from a **bare clone** of the project's upstream repository. This provides:

- **Source project isolation.** The bare clone is separate from the source project's `.git` directory. A misbehaving sandbox cannot corrupt the main repo.
- **Shared object store.** Multiple sandboxes of the same project share one bare clone, avoiding redundant disk usage.
- **Isolated git state.** Own branch, own index, own HEAD. The main working tree stays clean.
- **Clean merge path.** Work done in a sandbox produces a branch that can be pushed and PR'd through the normal workflow.

Storage layout:

```
~/.claude-sandboxes/
  state/                          # metadata (one JSON file per sandbox)
    <uuid>.json
  repos/                          # bare clones (one per source project)
    <project-name>.git/
  workspaces/                     # worktrees (one per sandbox)
    <display-name>/
```

## Repo Directory Layout

```
~/.claude/
├── Makefile                          # sandbox targets included
├── README.md                         # existing
├── setup.sh                          # existing
├── config/
│   └── my-profile.json               # existing claudeup profile
├── scripts/
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
  "go": {
    "feature": "ghcr.io/devcontainers/features/go:1",
    "default_version": "1.23"
  },
  "rust": {
    "feature": "ghcr.io/devcontainers/features/rust:1",
    "default_version": "latest"
  },
  "python": {
    "feature": "ghcr.io/devcontainers/features/python:1",
    "default_version": "3.12"
  },
  "java": {
    "feature": "ghcr.io/devcontainers/features/java:1",
    "default_version": "21"
  }
}
```

**Not in this repo:**

- Profiles remain in `~/.claudeup/profiles/` (claudeup owns those).
- Sandbox runtime state lives in `~/.claude-sandboxes/` (not config, not version-controlled), organized into `state/`, `repos/`, and `workspaces/` subdirectories.

## Makefile Targets

```makefile
##@ Sandbox Management

build-sandbox-image:    ## Build the base sandbox Docker image
rebuild-sandbox-image:  ## Rebuild the sandbox image from scratch (no cache)
sandbox-start:          ## Start a sandbox (PROJECT=path PROFILE=name [BRANCH=name] [NAME=name] [FEATURE=lang])
sandbox-list:           ## List active sandboxes
sandbox-exec:           ## Open a shell in a sandbox (SANDBOX=name)
sandbox-claude:         ## Run Claude Code in a sandbox (SANDBOX=name)
sandbox-attach:         ## Attach VS Code to a sandbox (SANDBOX=name)
sandbox-stop:           ## Stop a sandbox (SANDBOX=name)
sandbox-cleanup:        ## Remove a sandbox and its worktree (SANDBOX=name)
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
  --project ~/code/myapp \
  --profile frontend-heavy \
  --branch feature/new-dashboard \
  --feature go:1.23

# Start a second sandbox of the same project
claude-sandbox start \
  --project ~/code/myapp \
  --profile frontend-heavy \
  --branch feature/experiment \
  --name myapp-experiment

# Work in the container
claude-sandbox claude --sandbox myapp-frontend-heavy

# Attach VS Code for visual diffing
claude-sandbox attach --sandbox myapp-frontend-heavy

# Done for the day
claude-sandbox stop --sandbox myapp-frontend-heavy

# Done with this experiment entirely
claude-sandbox cleanup --sandbox myapp-experiment
```

## Future Considerations

- **Project-specific overrides.** A `.claude-sandbox.json` in a project repo could specify default features, ports, and env vars so `--feature` flags become optional.
- **VS Code customizations in the template.** Baseline extensions and settings in the generated `devcontainer.json` for a consistent editor experience.
