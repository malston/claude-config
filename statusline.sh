#!/usr/bin/env bash
# ABOUTME: Enhanced status line for Claude Code
# ABOUTME: Displays foundation, directory, git info, kubernetes context, and command duration

set -euo pipefail

# Read JSON input from stdin
INPUT=$(cat)

# Extract values from JSON
CWD=$(echo "$INPUT" | jq -r '.workspace.current_dir // .cwd // ""')
[ -z "$CWD" ] && CWD=$(pwd)

OUTPUT=""

# Foundation environment (🪐)
if [ -n "${FOUNDATION:-}" ]; then
    OUTPUT+=$(printf '\033[1;32m🪐 %s\033[0m ' "$FOUNDATION")
fi

# Current directory
if [ -n "$CWD" ]; then
    OUTPUT+=$(printf '\033[1;36m%s\033[0m ' "$(basename "$CWD")")

    # Git information (🌱)
    if [ -d "$CWD/.git" ] || git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
        BRANCH=$(git -C "$CWD" --no-optional-locks branch --show-current 2>/dev/null || true)

        if [ -n "$BRANCH" ]; then
            # Get remote tracking branch
            REMOTE=$(git -C "$CWD" --no-optional-locks rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null | cut -d'/' -f2- || true)

            if [ -n "$REMOTE" ] && [ "$REMOTE" != "$BRANCH" ]; then
                OUTPUT+=$(printf '\033[1;35m🌱 %s:%s\033[0m ' "$BRANCH" "$REMOTE")
            else
                OUTPUT+=$(printf '\033[1;35m🌱 %s\033[0m ' "$BRANCH")
            fi

            # Git status indicators
            STATUS=""
            # Check for modifications (±)
            if ! git -C "$CWD" --no-optional-locks diff-index --quiet HEAD -- 2>/dev/null; then
                STATUS+="±"
            fi
            # Check for untracked files (?)
            UNTRACKED=$(git -C "$CWD" --no-optional-locks ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
            if [ "$UNTRACKED" -gt 0 ]; then
                STATUS+="?"
            fi

            if [ -n "$STATUS" ]; then
                OUTPUT+=$(printf '\033[1;33m[%s]\033[0m ' "$STATUS")
            fi
        fi
    fi
fi

# Kubernetes context (⎈)
if command -v kubectl &>/dev/null; then
    K8S_CONTEXT=$(kubectl config current-context 2>/dev/null || true)
    if [ -n "$K8S_CONTEXT" ]; then
        K8S_NS=$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || true)
        [ -z "$K8S_NS" ] && K8S_NS="default"
        OUTPUT+=$(printf '\033[1;36m⎈ %s (%s)\033[0m ' "$K8S_CONTEXT" "$K8S_NS")
    fi
fi

# Context window usage percentage
USAGE=$(echo "$INPUT" | jq '.context_window.current_usage')
if [ "$USAGE" != "null" ]; then
    CURRENT=$(echo "$USAGE" | jq '.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens')
    SIZE=$(echo "$INPUT" | jq '.context_window.context_window_size')
    PCT=$((CURRENT * 100 / SIZE))

    # Color code based on usage: green < 50%, yellow < 80%, red >= 80%
    if [ "$PCT" -lt 50 ]; then
        COLOR='\033[32m'  # Green
    elif [ "$PCT" -lt 80 ]; then
        COLOR='\033[33m'  # Yellow
    else
        COLOR='\033[31m'  # Red
    fi

    OUTPUT+=$(printf '%b[ctx %d%%]\033[0m ' "$COLOR" "$PCT")
fi

# Output (trim trailing space)
echo -n "${OUTPUT% }"
