#!/usr/bin/env bash
# wallpaper-publish.sh — push approved AI wallpapers to the live site.
#
# Usage:
#   ./scripts/wallpaper-publish.sh                publish ALL approved
#   ./scripts/wallpaper-publish.sh <id>           publish one specific
#   ./scripts/wallpaper-publish.sh --all          (same as no arg)
#
# Requires WPE_ADMIN_TOKEN in .env (your admin JWT — extract once from
# the web app's localStorage after logging in).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    . .env
    set +a
fi

if [ -z "${WPE_ADMIN_TOKEN:-}" ]; then
    cat <<'MSG' >&2
WPE_ADMIN_TOKEN is not set.

Get one by:
  1. Open https://wallpaperexchange.com in your browser, log in as admin.
  2. DevTools → Application → Local Storage → key "token" → copy.
  3. Add to .env (gitignored):
       WPE_ADMIN_TOKEN=ey...
MSG
    exit 1
fi

# llm_usage logging is optional here (publish doesn't make LLM calls
# itself), but keep the same DB defaults as wallpaper-gen.sh so users
# only have to set up the SSH tunnel once.
export DB_HOST="${DB_HOST:-127.0.0.1}"
export DB_PORT="${DB_PORT:-15432}"
export DB_USER="${DB_USER:-wallpaper}"
export DB_PASSWORD="${DB_PASSWORD:-wallpaper}"
export DB_NAME="${DB_NAME:-wallpaper}"

exec go run ./backend/cmd/aigen publish "$@"
