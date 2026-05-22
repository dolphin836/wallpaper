#!/usr/bin/env bash
# Run backend/cmd/autotag against the prod database from a local Mac via
# an SSH-tunneled DB connection.
#
# Why this exists: the worker auto-classifies wallpapers inline (image
# worker → llm.Classify → Claude), but the prod host's IP is blocked by
# Anthropic (403 "Request not allowed"). Worker logs show every recent
# upload failing classification, leaving rows with category_id=0, no
# title, and no tags. Until we either run worker traffic through a
# proxy or swap LLMs, a developer with Anthropic access can backfill
# from their own machine using this script.
#
# Usage:
#   ./scripts/autotag-prod.sh                          # dry-run (no DB writes)
#   ./scripts/autotag-prod.sh --commit                 # write classifications
#   ./scripts/autotag-prod.sh --commit --limit 5       # canary first
#   ./scripts/autotag-prod.sh --commit --update-title  # also fill empty titles
#   ./scripts/autotag-prod.sh --commit --force         # reclassify even tagged rows
#
# Requires:
#   ANTHROPIC_API_KEY in env, SSH access to the prod host.
set -euo pipefail

: "${SSH_HOST:=root@139.224.49.94}"
: "${TUNNEL_PORT:=15432}"
: "${DB_PASSWORD:=wallpaper}"

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "ERROR: ANTHROPIC_API_KEY is not set. autotag needs it to call Claude." >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Opening SSH tunnel localhost:${TUNNEL_PORT} → ${SSH_HOST}:5432"
ssh -N -L "${TUNNEL_PORT}:127.0.0.1:5432" "${SSH_HOST}" &
TUNNEL_PID=$!
trap 'echo "==> Closing tunnel"; kill "${TUNNEL_PID}" 2>/dev/null || true' EXIT

# Poll until the local end of the tunnel accepts connections. Faster and
# more reliable than a fixed sleep — ssh exits non-zero on its own if it
# fails to bind, which we'll detect via nc timing out.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if nc -z 127.0.0.1 "${TUNNEL_PORT}" 2>/dev/null; then
        break
    fi
    sleep 0.5
done
if ! nc -z 127.0.0.1 "${TUNNEL_PORT}" 2>/dev/null; then
    echo "ERROR: tunnel never came up on port ${TUNNEL_PORT}" >&2
    exit 1
fi

echo "==> Tunnel up. Running ./backend/cmd/autotag $*"
cd "${REPO_ROOT}/backend"
DB_HOST=127.0.0.1 \
DB_PORT="${TUNNEL_PORT}" \
DB_USER=wallpaper \
DB_PASSWORD="${DB_PASSWORD}" \
DB_NAME=wallpaper \
DB_SSLMODE=disable \
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
go run ./cmd/autotag "$@"
