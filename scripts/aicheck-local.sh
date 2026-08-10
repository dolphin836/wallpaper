#!/usr/bin/env bash
# Detect clearly AI-generated wallpapers from a developer Mac.
#
# The Go task queries preview_url only, downloads each preview into local
# memory, and sends those bytes to Claude. It never queries or downloads the
# original image. High-confidence matches are persisted as
# is_ai_generated=true when --commit is present.
#
# Usage:
#   ./scripts/aicheck-local.sh
#   ./scripts/aicheck-local.sh --commit --limit 10
#   ./scripts/aicheck-local.sh --commit \
#     --created-after 2026-08-09T15:00:00Z \
#     --created-before 2026-08-10T15:00:00Z

set -euo pipefail
cd "$(dirname "$0")/.."

if [ -f scripts/.qcheck.env ]; then
    # shellcheck disable=SC1091
    set -a; source scripts/.qcheck.env; set +a
fi

: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is required — export it or put it in scripts/.qcheck.env}"
: "${SSH_HOST:=root@139.224.49.94}"
: "${DB_USER:=wallpaper}"
: "${DB_PASSWORD:=wallpaper}"
: "${DB_NAME:=wallpaper}"
TUNNEL_PORT=15432

echo "==> Opening SSH tunnel to ${SSH_HOST} (localhost:${TUNNEL_PORT} → :5432)..."
pkill -f "ssh.*${TUNNEL_PORT}:127\\.0\\.0\\.1:5432.*${SSH_HOST}" 2>/dev/null || true
sleep 1
ssh -fNL "${TUNNEL_PORT}:127.0.0.1:5432" "$SSH_HOST" -o ExitOnForwardFailure=yes
trap 'pkill -f "ssh.*'${TUNNEL_PORT}':127\\.0\\.0\\.1:5432.*'${SSH_HOST}'" 2>/dev/null || true' EXIT
for _ in 1 2 3 4 5; do
    nc -z 127.0.0.1 "$TUNNEL_PORT" 2>/dev/null && break
    sleep 1
done

echo "==> Running AI detection from preview images only..."
env \
    DB_HOST=127.0.0.1 \
    DB_PORT="$TUNNEL_PORT" \
    DB_USER="$DB_USER" \
    DB_PASSWORD="$DB_PASSWORD" \
    DB_NAME="$DB_NAME" \
    DB_SSLMODE=disable \
    ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
    go -C backend run ./cmd/aicheck "$@"

echo "==> Done. AI matches are available in admin → Wallpapers → type filter AI."
