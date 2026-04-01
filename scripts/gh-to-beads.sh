#!/usr/bin/env bash
# ABOUTME: Imports GitHub Issues into beads (bd) as work items.
# ABOUTME: Usage: gh-to-beads.sh <owner/repo> [--dry-run] [--state open|closed|all] [--limit N]
# ABOUTME: Requires: gh (GitHub CLI), jq, bd (beads)

set -euo pipefail

# --- Defaults ---
STATE="open"
LIMIT=500
DRY_RUN=false
DEFAULT_PRIORITY=2
LABEL_TYPE_MAP=""
LABEL_PRIORITY_MAP=""

usage() {
    cat <<'USAGE'
Usage: gh-to-beads.sh <owner/repo> [options]

Exports GitHub Issues and imports them into the local beads database.

Options:
  --state STATE        Issue state: open, closed, all (default: open)
  --limit N            Max issues to fetch (default: 500)
  --dry-run            Show what would be imported without importing
  --type-map LABEL=TYPE  Map a GitHub label to a beads issue type.
                         Can be repeated. Example: --type-map bug=bug --type-map enhancement=feature
  --priority-map LABEL=PRI  Map a GitHub label to a beads priority (0-4).
                             Can be repeated. Example: --priority-map critical=0 --priority-map backlog=4
  --default-priority N Fallback priority when no label matches (0-4, default: 2)
  -h, --help           Show this help

Examples:
  gh-to-beads.sh acme-corp/api-server
  gh-to-beads.sh acme-corp/api-server --state all --limit 100
  gh-to-beads.sh acme-corp/api-server --dry-run --type-map bug=bug --type-map enhancement=feature
  gh-to-beads.sh acme-corp/api-server --priority-map "P0"=0 --priority-map "P1"=1

Label Mapping:
  By default, issues with a "bug" label become type=bug, "feature" or
  "enhancement" labels become type=feature, and everything else is type=task.
  Default priority is 2 (medium). Use --type-map, --priority-map, and
  --default-priority to override.

Requirements:
  - gh (GitHub CLI) authenticated with access to the repo
  - jq for JSON transformation
  - bd (beads) initialized in the current directory (run bd init first)
USAGE
    exit 0
}

# --- Parse args ---
if [[ $# -lt 1 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    usage
fi

REPO="$1"
shift

while [[ $# -gt 0 ]]; do
    case "$1" in
        --state)
            STATE="$2"
            shift 2
            ;;
        --limit)
            LIMIT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --type-map)
            LABEL_TYPE_MAP="${LABEL_TYPE_MAP}${LABEL_TYPE_MAP:+,}$2"
            shift 2
            ;;
        --priority-map)
            LABEL_PRIORITY_MAP="${LABEL_PRIORITY_MAP}${LABEL_PRIORITY_MAP:+,}$2"
            shift 2
            ;;
        --default-priority)
            DEFAULT_PRIORITY="$2"
            if [[ ! "$DEFAULT_PRIORITY" =~ ^[0-4]$ ]]; then
                echo "Error: --default-priority must be 0-4" >&2
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# --- Dependency checks ---
for cmd in gh jq bd; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is not installed" >&2
        exit 1
    fi
done

if ! bd doctor --quiet 2>/dev/null; then
    echo "Error: beads not initialized in current directory. Run 'bd init' first." >&2
    exit 1
fi

# --- Build jq type-map object ---
TYPE_MAP_JQ='{"bug": "bug", "feature": "feature", "enhancement": "feature"}'
if [[ -n "$LABEL_TYPE_MAP" ]]; then
    # Convert "bug=bug,enhancement=feature" to jq object
    CUSTOM_MAP=$(echo "$LABEL_TYPE_MAP" | tr ',' '\n' | while IFS='=' read -r label type; do
        printf '%s\t%s\n' "$label" "$type"
    done | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add')
    TYPE_MAP_JQ=$(echo "$TYPE_MAP_JQ" "$CUSTOM_MAP" | jq -s 'add')
fi

# --- Build jq priority-map object ---
PRIORITY_MAP_JQ='{}'
if [[ -n "$LABEL_PRIORITY_MAP" ]]; then
    CUSTOM_PMAP=$(echo "$LABEL_PRIORITY_MAP" | tr ',' '\n' | while IFS='=' read -r label pri; do
        printf '%s\t%s\n' "$label" "$pri"
    done | jq -Rn '[inputs | split("\t") | {(.[0]): (.[1] | tonumber)}] | add')
    PRIORITY_MAP_JQ="$CUSTOM_PMAP"
fi

# --- Fetch from GitHub ---
echo "Fetching issues from $REPO (state=$STATE, limit=$LIMIT)..."

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

gh issue list \
    --repo "$REPO" \
    --state "$STATE" \
    --limit "$LIMIT" \
    --json number,title,body,labels,state,assignees,createdAt,closedAt,url \
    > "$TMPDIR/gh-issues.json"

ISSUE_COUNT=$(jq length "$TMPDIR/gh-issues.json")
echo "Fetched $ISSUE_COUNT issues"

if [[ "$ISSUE_COUNT" -eq 0 ]]; then
    echo "No issues to import."
    exit 0
fi

# --- Transform to beads JSONL ---
jq -c --argjson type_map "$TYPE_MAP_JQ" \
      --argjson pri_map "$PRIORITY_MAP_JQ" \
      --argjson default_pri "$DEFAULT_PRIORITY" '
.[] | {
  title: "#\(.number) \(.title)",
  description: (
    "Imported from GitHub: \(.url)\n\n" +
    (if .body then .body else "" end)
  ),
  status: (if .state == "OPEN" then "open" else "closed" end),
  issue_type: (
    [.labels[].name] as $names |
    ($names | map($type_map[.] // empty) | first) // "task"
  ),
  priority: (
    [.labels[].name] as $names |
    ($names | map($pri_map[.] // empty) | first) // $default_pri
  ),
  labels: ([.labels[].name] + ["github-import"]),
  created_at: .createdAt,
  closed_at: .closedAt
}' "$TMPDIR/gh-issues.json" > "$TMPDIR/import.jsonl"

TRANSFORM_COUNT=$(wc -l < "$TMPDIR/import.jsonl" | tr -d ' ')
echo "Transformed $TRANSFORM_COUNT issues to beads JSONL"

# --- Import ---
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "=== DRY RUN: $TRANSFORM_COUNT issues would be imported ==="
    echo ""
    printf "%-10s %-5s %-8s %-20s %s\n" "TYPE" "PRI" "STATUS" "LABELS" "TITLE"
    printf "%-10s %-5s %-8s %-20s %s\n" "----" "---" "------" "------" "-----"
    jq -r '[.issue_type, (.priority | tostring), .status, ([.labels[] | select(. != "github-import")] | join(",")), .title] | @tsv' \
        "$TMPDIR/import.jsonl" \
        | while IFS=$'\t' read -r type pri status labels title; do
            printf "%-10s %-5s %-8s %-20s %s\n" "$type" "$pri" "$status" "$labels" "$title"
        done
    echo ""
    echo "To import for real, run without --dry-run"
else
    echo ""
    bd import "$TMPDIR/import.jsonl"
    echo ""
    echo "Import complete. Run 'bd list --label github-import' to see imported issues."
    echo "Add dependencies with: bd dep add <issue> <depends-on>"
fi
