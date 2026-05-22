#!/usr/bin/env bash
# Run from a developer Mac every Friday: generates the current ISO week's
# Home-page artifacts in one shot —
#   - a 10-wallpaper "Weekly Picks" slate (writes weekly_picks rows)
#   - a themed editor collection (kind=1) with 10 wallpapers, theme chosen
#     by Claude from recently published rows.
#
# Why local: Claude picks the theme, and Anthropic geo-blocks the prod IP
# (403 "Request not allowed"). This is the canonical "offshore API + prod
# DB" pattern — same shape as scripts/autotag-prod.sh.
#
# No flags. Default mode is --commit (writes everything). Re-running for
# the same ISO week is fine — the picks generator replaces existing rows
# and the collection upsert is keyed on (year, week, kind=1).
#
# Requires: ANTHROPIC_API_KEY (auto-loaded from repo .env if not set in
# your shell), SSH access to the prod host.
set -euo pipefail

: "${SSH_HOST:=root@139.224.49.94}"
: "${TUNNEL_PORT:=15432}"
: "${DB_PASSWORD:=wallpaper}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Pull ANTHROPIC_API_KEY (and any other future offshore-API keys) from
# the repo's .env so the developer doesn't have to `source .env` first.
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

echo "==> Generating this week's picks + themed collection"
cd "${REPO_ROOT}/backend"
DB_HOST=127.0.0.1 \
DB_PORT="${TUNNEL_PORT}" \
DB_USER=wallpaper \
DB_PASSWORD="${DB_PASSWORD}" \
DB_NAME=wallpaper \
DB_SSLMODE=disable \
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
go run ./cmd/weekly-drop --commit
