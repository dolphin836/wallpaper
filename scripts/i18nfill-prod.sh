#!/usr/bin/env bash
# Run from a developer Mac: backfills the *_i18n translation columns
# (tag names + public collection titles/descriptions) in the prod DB via
# Claude batch translation. Idempotent — re-running picks up only rows
# still missing one of the four UI languages, so run it after content
# accumulates (new uploads create tags, users create collections).
#
# Why local: Anthropic blocks the prod IP (403 "Request not allowed"),
# same as autotag — translation never runs on the api/worker containers.
#
# Usage: scripts/i18nfill-prod.sh [extra i18nfill flags]
#   scripts/i18nfill-prod.sh                       # dry-run
#   scripts/i18nfill-prod.sh --commit              # translate everything missing
#   scripts/i18nfill-prod.sh --commit --limit 20   # canary
#
# Requires: ANTHROPIC_API_KEY in env, SSH access to the prod host.
set -euo pipefail

: "${SSH_HOST:=root@139.224.49.94}"
: "${TUNNEL_PORT:=15432}"
: "${DB_PASSWORD:=wallpaper}"

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
    echo "ERROR: ANTHROPIC_API_KEY is not set. i18nfill needs it to call Claude." >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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

echo "==> Backfilling tag / collection translations"
cd "${REPO_ROOT}/backend"
DB_HOST=127.0.0.1 \
DB_PORT="${TUNNEL_PORT}" \
DB_USER=wallpaper \
DB_PASSWORD="${DB_PASSWORD}" \
DB_NAME=wallpaper \
DB_SSLMODE=disable \
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
go run ./cmd/i18nfill "$@"
