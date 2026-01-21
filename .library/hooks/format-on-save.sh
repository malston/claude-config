#!/usr/bin/env bash
# ABOUTME: PostToolUse hook that auto-formats files after Claude edits them.
# ABOUTME: Runs gofmt for Go files and prettier for JS/TS/JSX/TSX files.

set -euo pipefail

# Read JSON input from stdin
input=$(cat)

# Extract file_path from tool_input
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# Exit silently if no file path (shouldn't happen, but be defensive)
if [[ -z "$file_path" ]]; then
    exit 0
fi

# Exit if file doesn't exist (might have been deleted)
if [[ ! -f "$file_path" ]]; then
    exit 0
fi

# Format Go files with gofmt
if [[ "$file_path" == *.go ]]; then
    if command -v gofmt &>/dev/null; then
        gofmt -w "$file_path" 2>/dev/null || true
    fi
    exit 0
fi

# Format JavaScript/TypeScript files with prettier
if [[ "$file_path" =~ \.(js|jsx|ts|tsx|json|css|scss|md|yaml|yml)$ ]]; then
    if command -v prettier &>/dev/null; then
        prettier --write "$file_path" 2>/dev/null || true
    elif command -v npx &>/dev/null; then
        # Fallback to npx if prettier not globally installed
        npx prettier --write "$file_path" 2>/dev/null || true
    fi
    exit 0
fi

exit 0
