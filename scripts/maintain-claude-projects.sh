#!/usr/bin/env bash
# Maintenance script for ~/.claude/projects
# Cleans up build artifacts and stale session data

set -e

CLAUDE_PROJECTS="${HOME}/.claude/projects"
DRY_RUN=false
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Maintenance script for ~/.claude/projects cleanup

OPTIONS:
  -d, --dry-run       Show what would be deleted without actually deleting
  -v, --verbose       Show detailed information
  -h, --help          Show this help message

EXAMPLES:
  # Dry run to see what would be cleaned
  $(basename "$0") --dry-run

  # Actually clean up
  $(basename "$0")

  # Clean up with verbose output
  $(basename "$0") -v
EOF
  exit 0
}

log() {
  echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

log_success() {
  echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
  echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
  echo -e "${RED}✗${NC} $*" >&2
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      ;;
  esac
done

# Check if directory exists
if [[ ! -d "$CLAUDE_PROJECTS" ]]; then
  log_error "Directory not found: $CLAUDE_PROJECTS"
  exit 1
fi

log "Starting maintenance of $CLAUDE_PROJECTS"
[[ "$DRY_RUN" == true ]] && log_warning "DRY RUN MODE - no files will be deleted"

# Get initial size
INITIAL_SIZE=$(du -sh "$CLAUDE_PROJECTS" | cut -f1)
log "Initial size: $INITIAL_SIZE"
echo ""

# Array of build artifact patterns to clean
BUILD_ARTIFACTS=(
  "node_modules"
  ".next"
  ".nuxt"
  "dist"
  "build"
  "__pycache__"
  ".pytest_cache"
  ".venv"
  "venv"
  ".gradle"
  "target"
  ".m2"
  ".cache"
  ".tmp"
  "coverage"
  ".nyc_output"
  ".eslintcache"
)

FILES_DELETED=0

# Clean build artifacts
log "Cleaning build artifacts..."

for pattern in "${BUILD_ARTIFACTS[@]}"; do
  if [[ "$VERBOSE" == true ]]; then
    log "Looking for: $pattern"
  fi

  count=$(find "$CLAUDE_PROJECTS" -type d -name "$pattern" 2>/dev/null | wc -l)

  if [[ $count -gt 0 ]]; then
    # Calculate size before deletion
    size=$(find "$CLAUDE_PROJECTS" -type d -name "$pattern" -exec du -sh {} + 2>/dev/null | awk '{sum+=$1} END {print sum}')

    if [[ "$DRY_RUN" == true ]]; then
      log_warning "Would delete $count instance(s) of '$pattern' (~${size})"
      if [[ "$VERBOSE" == true ]]; then
        find "$CLAUDE_PROJECTS" -type d -name "$pattern" 2>/dev/null | while read -r dir; do
          echo "  → $dir"
        done
      fi
    else
      find "$CLAUDE_PROJECTS" -type d -name "$pattern" -exec rm -rf {} + 2>/dev/null || true
      log_success "Deleted $count instance(s) of '$pattern'"
      ((FILES_DELETED+=count))
    fi
  fi
done

echo ""

# Clean empty directories (directories with no files, only subdirs that are empty)
log "Cleaning empty directories..."

if [[ "$DRY_RUN" == true ]]; then
  empty_count=$(find "$CLAUDE_PROJECTS" -type d -empty 2>/dev/null | wc -l)
  if [[ $empty_count -gt 0 ]]; then
    log_warning "Would delete $empty_count empty directories"
  else
    log_success "No empty directories to clean"
  fi
else
  find "$CLAUDE_PROJECTS" -type d -empty -delete 2>/dev/null || true
  log_success "Cleaned empty directories"
fi

echo ""

# Final size
FINAL_SIZE=$(du -sh "$CLAUDE_PROJECTS" | cut -f1)
log "Final size: $FINAL_SIZE"

if [[ "$DRY_RUN" == false ]]; then
  log_success "Maintenance complete!"
  echo ""
  echo "Summary:"
  echo "  Files deleted: $FILES_DELETED"
  echo "  Initial size: $INITIAL_SIZE"
  echo "  Final size: $FINAL_SIZE"
  echo ""
  echo "Run periodically (monthly) to keep ~/.claude/projects clean."
else
  log_warning "This was a dry run. Run without --dry-run to actually delete files."
fi
