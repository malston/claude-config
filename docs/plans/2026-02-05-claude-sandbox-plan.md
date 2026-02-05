# Claude Sandbox Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a CLI tool (`claude-sandbox`) that creates isolated dev container environments for testing different Claude Code configurations.

**Architecture:** A launcher bash script orchestrates git worktrees, generates `devcontainer.json` from a template, and delegates container lifecycle to the `devcontainer` CLI. Init scripts inside the container apply claudeup profiles and configure git/auth.

**Tech Stack:** Bash, Docker, devcontainer CLI, claudeup, git worktrees

---

### Task 1: Create devcontainer-base directory and Dockerfile

**Files:**

- Create: `devcontainer-base/Dockerfile`

**Step 1: Create directory**

Run: `mkdir -p devcontainer-base`

**Step 2: Write Dockerfile**

Create `devcontainer-base/Dockerfile` with the base image from the design doc. This is a generalized version of the diego-capacity-analyzer Dockerfile. Key differences from the diego version:

- No `claude-config/` baked in (no COPY of settings, enabled.json, CLAUDE.md templates, .library, scripts, completions)
- No project-specific hooks or session-start templates
- No `/usr/local/share/claude-defaults` directory (claudeup profiles replace baked-in config)
- Claude Code installed via official installer (`curl -fsSL https://claude.ai/install.sh | bash`)
- Init scripts are simplified (only `init-claude-config.sh` and `init-claudeup.sh`)

```dockerfile
# ABOUTME: Base dev container image for Claude Code sandbox environments.
# ABOUTME: Provides Node.js, dev tools, Claude Code, claudeup, and Bun.

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

RUN curl -fsSL https://bun.sh/install | bash

RUN git config --global core.excludesfile ~/.gitignore_global && \
    echo ".claude/settings.local.json" > /home/node/.gitignore_global

RUN curl -fsSL https://claude.ai/install.sh | bash

USER root

COPY --chmod=755 init-claude-config.sh /usr/local/bin/
COPY --chmod=755 init-claudeup.sh /usr/local/bin/

USER node
```

**Step 3: Verify Dockerfile syntax**

Run: `docker build --check devcontainer-base/`
Expected: No syntax errors (this may fail if init scripts don't exist yet; that's fine, we just want to check Dockerfile syntax)

**Step 4: Commit**

```bash
git add devcontainer-base/Dockerfile
git commit -m "Add base Dockerfile for sandbox dev containers"
```

---

### Task 2: Create init-claudeup.sh

**Files:**

- Create: `devcontainer-base/init-claudeup.sh`

**Step 1: Write init-claudeup.sh**

Generalized from `diego-capacity-analyzer/.devcontainer/init-claudeup.sh`. Key changes:

- Reads profile name from `CLAUDE_PROFILE` env var instead of hardcoding "docker"
- Validates that `CLAUDE_PROFILE` is set
- Uses `claudeup setup --profile "$CLAUDE_PROFILE" -y`

```bash
#!/usr/bin/env bash
# ABOUTME: Installs claudeup and applies the specified profile.
# ABOUTME: Reads CLAUDE_PROFILE env var for the profile name.

set -euo pipefail

CLAUDEUP_HOME="/home/node/.claudeup"
MARKER_FILE="$CLAUDEUP_HOME/.setup-complete"

echo "Initializing claudeup..."

if [ -f "$MARKER_FILE" ]; then
    echo "[SKIP] Claudeup setup already complete"
    exit 0
fi

if [ -z "${CLAUDE_PROFILE:-}" ]; then
    echo "[WARN] CLAUDE_PROFILE not set, skipping profile setup"
    exit 0
fi

mkdir -p "$CLAUDEUP_HOME/profiles"

if ! command -v claudeup &> /dev/null; then
    echo "Installing claudeup..."
    curl -fsSL https://raw.githubusercontent.com/claudeup/claudeup/main/install.sh | bash
    export PATH="$HOME/.local/bin:$PATH"
    echo "[OK] claudeup installed"
else
    echo "[SKIP] claudeup already installed"
fi

echo "Applying profile: $CLAUDE_PROFILE..."
if claudeup setup --profile "$CLAUDE_PROFILE" -y; then
    echo "[OK] Profile '$CLAUDE_PROFILE' applied"
    touch "$MARKER_FILE"
else
    echo "[WARN] claudeup setup failed, will retry on next container start"
    exit 1
fi

echo "Claudeup initialization complete"
```

**Step 2: Verify the script is valid bash**

Run: `bash -n devcontainer-base/init-claudeup.sh`
Expected: No output (no syntax errors)

**Step 3: Commit**

```bash
git add devcontainer-base/init-claudeup.sh
git commit -m "Add parameterized init-claudeup script for sandbox containers"
```

---

### Task 3: Create init-claude-config.sh

**Files:**

- Create: `devcontainer-base/init-claude-config.sh`

**Step 1: Write init-claude-config.sh**

Simplified from `diego-capacity-analyzer/.devcontainer/init-claude-config.sh`. This version handles:

- Git identity configuration (from env vars)
- GitHub auth via gh CLI
- Dotfiles cloning (optional)
- Basic `~/.claude` directory structure

It does NOT deploy settings.json, enabled.json, CLAUDE.md templates, .library, scripts, or completions. Those come from `claudeup setup --profile` in `init-claudeup.sh`.

Reuse the input validation functions (`validate_email`, `validate_git_name`, `validate_git_url`) and the git/GitHub/dotfiles sections from the diego version. Remove the "Deploy .library", "Deploy settings.json", "Deploy enabled.json", "Deploy CLAUDE.md", "Deploy MCP configuration", "Deploy claude.json", "Create symlinks", and "Deploy scripts/completions" sections.

```bash
#!/usr/bin/env bash
# ABOUTME: Configures git identity, GitHub auth, and dotfiles inside sandbox containers.
# ABOUTME: Reads GIT_USER_NAME, GIT_USER_EMAIL, GITHUB_TOKEN, and DOTFILES_REPO env vars.

set -euo pipefail

CLAUDE_HOME="/home/node/.claude"
DOTFILES_DIR="/home/node/dotfiles"

echo "Initializing Claude Code configuration..."

validate_email() {
    local email="$1"
    [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validate_git_name() {
    local name="$1"
    if [[ "$name" =~ [\;\|\&\$\`\'\"\<\>\(\)\{\}\[\]\\] ]] || [[ "$name" =~ [[:cntrl:]] ]]; then
        return 1
    fi
    [ -n "$name" ] && [ ${#name} -le 256 ]
}

validate_git_url() {
    local url="$1"
    [[ "$url" =~ ^https://(github\.com|gitlab\.com|bitbucket\.org)/ ]] || \
    [[ "$url" =~ ^git@(github\.com|gitlab\.com|bitbucket\.org): ]]
}

# Configure git identity
pushd /tmp > /dev/null
if [ -n "${GIT_USER_NAME:-}" ]; then
    if validate_git_name "$GIT_USER_NAME"; then
        git config --global user.name "$GIT_USER_NAME"
        echo "[OK] Git user.name: $GIT_USER_NAME"
    else
        echo "[WARN] GIT_USER_NAME contains invalid characters, skipping"
    fi
fi

if [ -n "${GIT_USER_EMAIL:-}" ]; then
    if validate_email "$GIT_USER_EMAIL"; then
        git config --global user.email "$GIT_USER_EMAIL"
        echo "[OK] Git user.email: $GIT_USER_EMAIL"
    else
        echo "[WARN] GIT_USER_EMAIL is not a valid email format, skipping"
    fi
fi

# Configure GitHub auth
if [ -n "${GITHUB_TOKEN:-}" ]; then
    if command -v gh &> /dev/null; then
        gh auth setup-git 2>/dev/null || true
        echo "[OK] GitHub auth configured via gh CLI"
    else
        git config --global credential.helper \
            "!f() { echo \"username=x-access-token\"; echo \"password=\${GITHUB_TOKEN}\"; }; f"
        echo "[OK] GitHub credential helper configured"
    fi
fi
popd > /dev/null

# Clone dotfiles if configured
if [ -n "${DOTFILES_REPO:-}" ] && [ -z "$(ls -A "$DOTFILES_DIR" 2>/dev/null)" ]; then
    if validate_git_url "$DOTFILES_REPO"; then
        echo "Cloning dotfiles from $DOTFILES_REPO..."
        git clone --branch "${DOTFILES_BRANCH:-main}" "$DOTFILES_REPO" "$DOTFILES_DIR"
        echo "[OK] Dotfiles cloned"

        if [ -f "$DOTFILES_DIR/install.sh" ]; then
            echo "[SECURITY] Executing install.sh from $DOTFILES_REPO"
            # shellcheck disable=SC2086
            cd "$DOTFILES_DIR" && chmod +x install.sh && ./install.sh ${DOTFILES_INSTALL_ARGS:-}
            echo "[OK] Dotfiles install script completed"
        fi
    else
        echo "[WARN] DOTFILES_REPO must be a valid GitHub/GitLab/Bitbucket URL, skipping"
    fi
elif [ -n "${DOTFILES_REPO:-}" ]; then
    echo "[SKIP] Dotfiles directory not empty, preserving"
fi

mkdir -p "$CLAUDE_HOME"

mkdir -p /home/node/.npm-global/lib

echo "Claude configuration complete"
```

**Step 2: Verify the script is valid bash**

Run: `bash -n devcontainer-base/init-claude-config.sh`
Expected: No output (no syntax errors)

**Step 3: Commit**

```bash
git add devcontainer-base/init-claude-config.sh
git commit -m "Add simplified init-claude-config script for sandbox containers"
```

---

### Task 4: Create devcontainer template and features.json

**Files:**

- Create: `devcontainer-base/devcontainer.template.json`
- Create: `devcontainer-base/features.json`

**Step 1: Write devcontainer.template.json**

This template uses `{{PLACEHOLDER}}` syntax. The launcher script substitutes these at generation time using `sed`.

```json
{
  "name": "Claude Sandbox - {{PROJECT_NAME}} ({{PROFILE}})",
  "image": "claude-sandbox:latest",
  "features": {
    {{FEATURES}}
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

**Step 2: Write features.json**

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

**Step 3: Validate JSON syntax**

Run: `jq . devcontainer-base/features.json`
Expected: Pretty-printed JSON, no errors

**Step 4: Commit**

```bash
git add devcontainer-base/devcontainer.template.json devcontainer-base/features.json
git commit -m "Add devcontainer template and feature mappings"
```

---

### Task 5: Build and test the Docker image

**Files:**

- None (uses files from Tasks 1-3)

**Step 1: Build the image**

Run: `docker build -t claude-sandbox:latest devcontainer-base/`
Expected: Successful build. Verify Claude Code and claudeup are installed.

**Step 2: Smoke test the image**

Run: `docker run --rm claude-sandbox:latest claude --version`
Expected: Prints Claude Code version

Run: `docker run --rm claude-sandbox:latest bash -c 'which bun && bun --version'`
Expected: Prints bun path and version

Run: `docker run --rm claude-sandbox:latest bash -c 'which claudeup && claudeup --version'`
Expected: Prints claudeup path and version (or install claudeup at runtime if the curl in the Dockerfile fails due to network -- the init script handles this as fallback)

**Step 3: Commit (no file changes, but tag the milestone)**

If the build succeeds, no commit needed here. If Dockerfile needed adjustments, commit the fixes.

---

### Task 6: Write the claude-sandbox launcher script -- argument parsing and validation

**Files:**

- Create: `scripts/claude-sandbox`

**Step 1: Write the script skeleton with argument parsing**

The launcher supports these subcommands: `start`, `exec`, `claude`, `attach`, `list`, `stop`, `cleanup`.

For `start`, parse these flags:

- `--project <path>` (required)
- `--profile <name>` (required)
- `--branch <name>` (optional, defaults to `sandbox/<profile>`)
- `--feature <name[:version]>` (optional, repeatable)

Validation checks:

- `--project` path exists and is a git repo
- `--profile` exists in `~/.claudeup/profiles/<name>.json`
- `devcontainer` CLI is on PATH
- Docker is running

```bash
#!/usr/bin/env bash
# ABOUTME: Manages Claude Code sandbox environments using dev containers.
# ABOUTME: Orchestrates git worktrees, devcontainer generation, and container lifecycle.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SANDBOX_STATE_DIR="$HOME/.claude-sandboxes"
DEVCONTAINER_BASE="$REPO_DIR/devcontainer-base"

# ... (full script in implementation)
```

Write the `usage()`, `die()`, `parse_start_args()`, and `validate_start_args()` functions. Include `main()` that dispatches to subcommand handlers.

**Step 2: Test argument parsing**

Run: `scripts/claude-sandbox --help`
Expected: Prints usage

Run: `scripts/claude-sandbox start --project /nonexistent --profile test`
Expected: Error about project path not existing

Run: `scripts/claude-sandbox start --project ~/code/diego-capacity-analyzer --profile nonexistent`
Expected: Error about profile not found

**Step 3: Commit**

```bash
git add scripts/claude-sandbox
git commit -m "Add claude-sandbox launcher with argument parsing and validation"
```

---

### Task 7: Write the claude-sandbox `start` subcommand -- worktree and devcontainer generation

**Files:**

- Modify: `scripts/claude-sandbox`

**Step 1: Implement worktree creation**

The `start_sandbox()` function:

1. Derives `SANDBOX_ID` from `basename($PROJECT)-$PROFILE`
2. Derives worktree path: `$PROJECT_DIR/../$PROJECT_NAME-$PROFILE/`
3. Creates worktree with `git -C $PROJECT worktree add $WORKTREE_PATH -b $BRANCH`
   - If branch exists, use `git -C $PROJECT worktree add $WORKTREE_PATH $BRANCH`
4. Creates `.devcontainer/` in the worktree
5. Adds `.devcontainer/` to `$WORKTREE_PATH/.git/info/exclude`

**Step 2: Implement devcontainer.json generation**

Read `devcontainer-base/devcontainer.template.json` and substitute placeholders:

- `{{PROJECT_NAME}}` -- basename of project path
- `{{PROFILE}}` -- profile name
- `{{SANDBOX_ID}}` -- derived sandbox ID
- `{{HOME}}` -- `$HOME`
- `{{FEATURES}}` -- built from `--feature` flags using `features.json` lookup
- `{{GIT_USER_NAME}}` -- from `git config user.name` or env
- `{{GIT_USER_EMAIL}}` -- from `git config user.email` or env
- `{{GITHUB_TOKEN}}` -- from `$GITHUB_TOKEN` env
- `{{CONTEXT7_API_KEY}}` -- from `$CONTEXT7_API_KEY` env

Use `sed` for substitution. For `{{FEATURES}}`, build the JSON snippet from `features.json` using `jq`.

**Step 3: Implement container launch**

Copy init scripts to worktree's `.devcontainer/`:

```bash
cp "$DEVCONTAINER_BASE/init-claude-config.sh" "$WORKTREE/.devcontainer/"
cp "$DEVCONTAINER_BASE/init-claudeup.sh" "$WORKTREE/.devcontainer/"
```

Launch:

```bash
devcontainer up --workspace-folder "$WORKTREE_PATH"
```

Save sandbox metadata to `~/.claude-sandboxes/<sandbox-id>.json`:

```json
{
  "sandbox_id": "...",
  "project": "...",
  "profile": "...",
  "worktree": "...",
  "branch": "...",
  "created": "..."
}
```

**Step 4: Test with a real project**

Run:

```bash
scripts/claude-sandbox start \
  --project ~/code/diego-capacity-analyzer \
  --profile docker \
  --branch sandbox/docker-test \
  --feature go:1.23
```

Expected:

- Worktree created at `~/code/diego-capacity-analyzer-docker/`
- `.devcontainer/devcontainer.json` generated with correct substitutions
- Container starts and `postCreateCommand` runs (claudeup applies docker profile)
- Sandbox metadata saved to `~/.claude-sandboxes/`

**Step 5: Commit**

```bash
git add scripts/claude-sandbox
git commit -m "Implement claude-sandbox start with worktree and devcontainer generation"
```

---

### Task 8: Write the claude-sandbox `exec`, `claude`, and `attach` subcommands

**Files:**

- Modify: `scripts/claude-sandbox`

**Step 1: Implement sandbox ID inference**

Add a `resolve_sandbox()` function that:

1. If `--sandbox <name>` is provided, use it directly
2. Otherwise, check if cwd is inside a worktree that matches a known sandbox
3. If neither, print error listing available sandboxes

**Step 2: Implement `exec` subcommand**

```bash
exec_sandbox() {
    local sandbox_id
    sandbox_id=$(resolve_sandbox "$@")
    local worktree
    worktree=$(jq -r .worktree "$SANDBOX_STATE_DIR/$sandbox_id.json")
    devcontainer exec --workspace-folder "$worktree" bash
}
```

**Step 3: Implement `claude` subcommand**

```bash
claude_sandbox() {
    local sandbox_id
    sandbox_id=$(resolve_sandbox "$@")
    local worktree
    worktree=$(jq -r .worktree "$SANDBOX_STATE_DIR/$sandbox_id.json")
    shift  # remove sandbox args if present
    devcontainer exec --workspace-folder "$worktree" claude "$@"
}
```

**Step 4: Implement `attach` subcommand**

```bash
attach_sandbox() {
    local sandbox_id
    sandbox_id=$(resolve_sandbox "$@")
    local worktree
    worktree=$(jq -r .worktree "$SANDBOX_STATE_DIR/$sandbox_id.json")
    local container_id
    container_id=$(devcontainer exec --workspace-folder "$worktree" hostname)
    local hex_id
    hex_id=$(printf '%s' "$container_id" | xxd -p | tr -d '\n')
    code --folder-uri "vscode-remote://attached-container+${hex_id}/workspaces/$(basename "$worktree")"
}
```

**Step 5: Test each subcommand**

Run (from inside the worktree created in Task 7):

```bash
scripts/claude-sandbox exec
scripts/claude-sandbox claude --version
scripts/claude-sandbox attach
```

Expected: Shell opens, Claude version prints, VS Code attaches.

**Step 6: Commit**

```bash
git add scripts/claude-sandbox
git commit -m "Add exec, claude, and attach subcommands to claude-sandbox"
```

---

### Task 9: Write the claude-sandbox `list`, `stop`, and `cleanup` subcommands

**Files:**

- Modify: `scripts/claude-sandbox`

**Step 1: Implement `list` subcommand**

Read all `~/.claude-sandboxes/*.json` files. For each, check container status via `docker inspect`. Print table:

```
SANDBOX                                      PROJECT                    PROFILE          STATUS
```

**Step 2: Implement `stop` subcommand**

```bash
stop_sandbox() {
    local sandbox_id
    sandbox_id=$(resolve_sandbox "$@")
    local worktree
    worktree=$(jq -r .worktree "$SANDBOX_STATE_DIR/$sandbox_id.json")
    devcontainer stop --workspace-folder "$worktree"
    echo "Stopped sandbox: $sandbox_id"
}
```

**Step 3: Implement `cleanup` subcommand**

```bash
cleanup_sandbox() {
    local sandbox_id
    sandbox_id=$(resolve_sandbox "$@")
    local meta="$SANDBOX_STATE_DIR/$sandbox_id.json"
    local worktree project
    worktree=$(jq -r .worktree "$meta")
    project=$(jq -r .project "$meta")

    echo "This will:"
    echo "  - Stop the container"
    echo "  - Remove Docker volumes (claude-sandbox-*-$sandbox_id)"
    echo "  - Remove worktree: $worktree"
    echo "  - Remove sandbox metadata"
    read -rp "Continue? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; return 1; }

    devcontainer stop --workspace-folder "$worktree" 2>/dev/null || true

    docker volume ls --format '{{.Name}}' | grep "claude-sandbox-.*-$sandbox_id" | \
        xargs -r docker volume rm

    git -C "$project" worktree remove "$worktree" --force

    rm -f "$meta"
    echo "Cleaned up sandbox: $sandbox_id"
}
```

**Step 4: Test each subcommand**

Run:

```bash
scripts/claude-sandbox list
scripts/claude-sandbox stop --sandbox diego-capacity-analyzer-docker
scripts/claude-sandbox list  # verify status changed
scripts/claude-sandbox cleanup --sandbox diego-capacity-analyzer-docker
scripts/claude-sandbox list  # verify sandbox removed
```

**Step 5: Commit**

```bash
git add scripts/claude-sandbox
git commit -m "Add list, stop, and cleanup subcommands to claude-sandbox"
```

---

### Task 10: Add Makefile targets

**Files:**

- Modify: `Makefile`

**Step 1: Add sandbox targets**

Add to the `.PHONY` declaration and add a new section:

```makefile
##@ Sandbox Management

build-sandbox-image: ## Build the base sandbox Docker image
	@docker build -t claude-sandbox:latest devcontainer-base/

sandbox-start: ## Start a sandbox (PROJECT=path PROFILE=name [BRANCH=name] [FEATURE=lang])
	@test -n "$(PROJECT)" || (echo "Error: PROJECT required (path to git repo)" && exit 1)
	@test -n "$(PROFILE)" || (echo "Error: PROFILE required (claudeup profile name)" && exit 1)
	@scripts/claude-sandbox start --project $(PROJECT) --profile $(PROFILE) \
		$(if $(BRANCH),--branch $(BRANCH)) $(if $(FEATURE),--feature $(FEATURE))

sandbox-list: ## List active sandboxes
	@scripts/claude-sandbox list

sandbox-stop: ## Stop a sandbox (SANDBOX=name)
	@test -n "$(SANDBOX)" || (echo "Error: SANDBOX required" && exit 1)
	@scripts/claude-sandbox stop --sandbox $(SANDBOX)

sandbox-cleanup: ## Remove a sandbox and its worktree (SANDBOX=name)
	@test -n "$(SANDBOX)" || (echo "Error: SANDBOX required" && exit 1)
	@scripts/claude-sandbox cleanup --sandbox $(SANDBOX)
```

**Step 2: Verify targets appear in help**

Run: `make help`
Expected: "Sandbox Management" section with all five targets

**Step 3: Commit**

```bash
git add Makefile
git commit -m "Add sandbox management targets to Makefile"
```

---

### Task 11: End-to-end test

**Files:**

- None (integration test using all components)

**Step 1: Full lifecycle test**

Run the complete workflow:

```bash
# Build image (if not already built)
make build-sandbox-image

# Start sandbox
make sandbox-start PROJECT=~/code/diego-capacity-analyzer PROFILE=docker FEATURE=go:1.23

# Verify sandbox is listed
make sandbox-list

# Verify Claude Code works inside the container
scripts/claude-sandbox claude --sandbox diego-capacity-analyzer-docker -- --version

# Verify exec works
scripts/claude-sandbox exec --sandbox diego-capacity-analyzer-docker

# Stop sandbox
make sandbox-stop SANDBOX=diego-capacity-analyzer-docker

# Cleanup sandbox
make sandbox-cleanup SANDBOX=diego-capacity-analyzer-docker

# Verify sandbox is removed
make sandbox-list
```

**Step 2: Verify worktree was cleaned up**

Run: `ls ~/code/diego-capacity-analyzer-docker/`
Expected: Directory does not exist

Run: `git -C ~/code/diego-capacity-analyzer worktree list`
Expected: No worktree for the sandbox

**Step 3: Fix any issues found during the test**

If issues are found, fix them in the appropriate file and commit:

```bash
git commit -am "Fix: <description of issue>"
```
