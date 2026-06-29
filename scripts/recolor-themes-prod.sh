#!/usr/bin/env bash
# Run from a developer Mac: backfill accent_color on every themed
# (kind=1) collection in prod that doesn't already have one. Idempotent
# — re-running only touches still-uncolored rows.
#
# Why local: Claude is offshore-blocked from prod's IP, so the LLM call
# has to originate from a developer's machine. Same SSH-tunneled DB
# pattern as autotag-prod.sh.
#
# No flags. ANTHROPIC_API_KEY auto-loads from repo .env.
set -euo pipefail

: "${SSH_HOST:=root@139.224.49.94}"
: "${TUNNEL_PORT:=15432}"
: "${DB_PASSWORD:=wallpaper}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -f "${REPO_ROOT}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.env"
    set +a
fi
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "ERROR: ANTHROPIC_API_KEY is not set (neither in shell nor in ${REPO_ROOT}/.env)." >&2
    exit 1
fi

echo "==> Opening SSH tunnel localhost:${TUNNEL_PORT} → ${SSH_HOST}:5432"
ssh -N -L "${TUNNEL_PORT}:127.0.0.1:5432" "${SSH_HOST}" &
TUNNEL_PID=$!
trap 'echo "==> Closing tunnel"; kill "${TUNNEL_PID}" 2>/dev/null || true' EXIT

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

echo "==> Backfilling accent_color on uncolored themed collections"
cd "${REPO_ROOT}/backend"
DB_HOST=127.0.0.1 \
DB_PORT="${TUNNEL_PORT}" \
DB_USER=wallpaper \
DB_PASSWORD="${DB_PASSWORD}" \
DB_NAME=wallpaper \
DB_SSLMODE=disable \
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
go run ./cmd/recolor-themes
