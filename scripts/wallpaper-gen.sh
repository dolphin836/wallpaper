#!/usr/bin/env bash
# wallpaper-gen.sh — local AI wallpaper generation wrapper.
#
# Usage:
#   ./scripts/wallpaper-gen.sh "<vague idea>"
#       generate a cheap 1024x1024 preview from your idea (Chinese OK)
#
#   ./scripts/wallpaper-gen.sh --finalize <id>
#       render the matching 4K final and move the entry to approved/
#
#   ./scripts/wallpaper-gen.sh --reject <id>
#       discard a pending preview
#
#   ./scripts/wallpaper-gen.sh --list
#       show pending / approved / uploaded buckets
#
# All generated files live under ai-wallpapers/ (gitignored). Approved
# entries stay there until you push them to the site with
# scripts/wallpaper-publish.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Load .env so OPENAI_API_KEY + ANTHROPIC_API_KEY are visible without
# the user having to export them in their shell.
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    . .env
    set +a
fi

# llm_usage logging needs a DB connection. Default to a local SSH tunnel
# into prod Postgres on :15432; the user can override DB_HOST / DB_PORT
# in their shell environment if they're running it differently.
export DB_HOST="${DB_HOST:-127.0.0.1}"
export DB_PORT="${DB_PORT:-15432}"
export DB_USER="${DB_USER:-wallpaper}"
export DB_PASSWORD="${DB_PASSWORD:-wallpaper}"
export DB_NAME="${DB_NAME:-wallpaper}"

case "${1:-}" in
    "" | -h | --help)
        exec go run ./backend/cmd/aigen
        ;;
    --finalize)
        shift
        exec go run ./backend/cmd/aigen finalize "$@"
        ;;
    --reject)
        shift
        exec go run ./backend/cmd/aigen reject "$@"
        ;;
    --list)
        shift
        exec go run ./backend/cmd/aigen list "$@"
        ;;
    *)
        # Default: first positional arg is treated as the idea. Quote it
        # in the shell to keep spaces intact, otherwise aigen will join
        # the remaining args with spaces (which is fine for idiomatic
        # multi-word prompts too).
        exec go run ./backend/cmd/aigen preview "$@"
        ;;
esac
