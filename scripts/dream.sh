#!/usr/bin/env bash
# Run the dream/memory consolidation skill headlessly for a given project.
# Usage: dream.sh [project-dir]
#   project-dir defaults to the current working directory.

set -euo pipefail

project_dir="${1:-.}"
project_dir="$(cd "$project_dir" && pwd)"

if [ ! -d "$project_dir/.claude" ] && [ ! -f "$project_dir/CLAUDE.md" ]; then
  echo "Warning: $project_dir does not appear to be a Claude Code project" >&2
fi

memory_dir="$HOME/.claude/projects/$(echo "$project_dir" | sed 's|/|-|g')/memory"

if [ ! -d "$memory_dir" ]; then
  echo "No memory directory found at $memory_dir" >&2
  exit 1
fi

echo "Running dream consolidation for: $project_dir"
echo "Memory directory: $memory_dir"

cd "$project_dir"

cat <<EOF | claude -p \
  --model haiku \
  --max-budget-usd 0.50 \
  --permission-mode acceptEdits \
  --allowedTools "Read,Write,Edit,Glob,Grep,Bash(ls:*),Bash(git log:*),Bash(git diff:*)"
You are running headlessly to consolidate memory files. The project directory is: $project_dir

The memory directory is: $memory_dir

Run the dream consolidation process:

## Phase 1 -- Orient
1. ls the memory directory
2. Read MEMORY.md (the index)
3. Skim each topic file -- read frontmatter and first few lines
4. Note file count, approximate total size, last-modified dates

## Phase 2 -- Gather Recent Signal
1. git log --oneline -20 in the project directory
2. Check if any memory files reference things that have changed
3. Grep only for specific facts to verify
4. Do NOT do broad searches

## Phase 3 -- Consolidate
1. Merge duplicates into one file
2. Convert relative dates to absolute dates
3. Delete contradicted facts
4. Promote ephemeral session notes to durable knowledge
5. Update frontmatter to match content
6. Delete dead files

## Phase 4 -- Prune and Index
1. Rebuild MEMORY.md from scratch
2. Each entry: - [Title](file.md) -- one-line hook (under 150 chars)
3. Group by topic, not chronologically
4. Keep under 200 lines

Print a summary at the end: files read/created/updated/deleted, key changes, current file count.
EOF
