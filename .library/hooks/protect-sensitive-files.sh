#!/usr/bin/env bash
# ABOUTME: PreToolUse hook that blocks edits to sensitive files.
# ABOUTME: Exits with code 2 to block, 0 to allow.

set -uo pipefail

# Read JSON input from stdin
input=$(cat)

# Extract file_path from tool_input
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Exit silently if no file path
if [[ -z "$file_path" ]]; then
    exit 0
fi

# Sensitive file patterns to protect
# Exact matches
protected_exact=(
    ".env"
    ".env.local"
    ".env.production"
    ".env.development"
    "go.sum"
    "package-lock.json"
    "yarn.lock"
    "pnpm-lock.yaml"
    "bun.lockb"
    "Gemfile.lock"
    "poetry.lock"
    "Cargo.lock"
)

# Pattern matches (checked with grep -E)
protected_patterns=(
    '\.env\.'
    '/\.git/'
    'node_modules/'
    'vendor/'
    '\.vscode/settings\.json'
    '\.idea/'
    'id_rsa'
    'id_ed25519'
    '\.pem$'
    '\.key$'
    'credentials\.json'
    'secrets\.yaml'
    'secrets\.yml'
)

# Get just the filename for exact matching
filename=$(basename "$file_path")

# Check exact matches
for protected in "${protected_exact[@]}"; do
    if [[ "$filename" == "$protected" ]]; then
        echo "BLOCKED: Cannot edit protected file: $protected" >&2
        echo "This file should be edited manually for safety." >&2
        exit 2
    fi
done

# Check pattern matches against full path
for pattern in "${protected_patterns[@]}"; do
    if echo "$file_path" | grep -qE "$pattern"; then
        echo "BLOCKED: Cannot edit file matching protected pattern: $pattern" >&2
        echo "Path: $file_path" >&2
        exit 2
    fi
done

# Allow the edit
exit 0
