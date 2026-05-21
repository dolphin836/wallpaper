#!/usr/bin/env bash
# wallpaper-publish.sh — push approved AI wallpapers to the live site.
#
# Usage:
#   ./scripts/wallpaper-publish.sh                publish ALL approved
#   ./scripts/wallpaper-publish.sh <id>           publish one specific
#   ./scripts/wallpaper-publish.sh --all          (same as no arg)
#
# Auth: this script SSHes into the prod host using the same key
# deploy.sh uses (root@139.224.49.94 by default) and runs
# /bin/wallpaper-import inside the api container — no admin JWT needed.
# Override SSH_HOST in your shell env if the prod address changes.
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

# Default to the same prod address deploy.sh uses. The user can
# override SSH_HOST in their environment to point at a staging box.
export SSH_HOST="${SSH_HOST:-root@139.224.49.94}"

# llm_usage logging is optional here (publish doesn't make LLM calls
# itself), but keep the same DB defaults as wallpaper-gen.sh so users
# only have to set up the SSH tunnel once.
export DB_HOST="${DB_HOST:-127.0.0.1}"
export DB_PORT="${DB_PORT:-15432}"
export DB_USER="${DB_USER:-wallpaper}"
export DB_PASSWORD="${DB_PASSWORD:-wallpaper}"
export DB_NAME="${DB_NAME:-wallpaper}"

exec go -C backend run ./cmd/aigen publish "$@"
