#!/usr/bin/env bash
# One-shot wallpaper moderation pass from your local mac.
#
# What it does, in order:
#   1. Opens an SSH tunnel to the prod postgres (localhost:15432 → :5432).
#   2. Runs ./cmd/qcheck against unassessed wallpapers — Claude vision
#      assigns each one a quality_flag. Flagged rows have their device
#      variants removed from the DB.
#   3. Calls scripts/sweep-orphan-variants.sh on the prod host to clean
#      up the MinIO objects that the local DB cleanup couldn't reach
#      (qcheck can't talk to the internal :9000 MinIO endpoint from
#      outside the docker network).
#
# Usage:
#   ./scripts/qcheck-local.sh                # dry-run: assess but don't write
#   ./scripts/qcheck-local.sh --commit       # write to DB + clean MinIO
#   ./scripts/qcheck-local.sh --commit --limit 5   # canary first
#
# Required env (export before running, or put in scripts/.qcheck.env which
# is .gitignored):
#   ANTHROPIC_API_KEY  — Claude API key
#   SSH_HOST           — defaults to root@139.224.49.94
#   DB_USER / DB_PASSWORD — defaults to wallpaper / wallpaper
#
# After the run, open admin → Wallpapers → quality filter "⚑ 已标记" to
# review the new flags and decide approve / unpublish / hard-delete per
# row.

set -euo pipefail
cd "$(dirname "$0")/.."

# Pull persistent secrets from scripts/.qcheck.env if present. The file
# is gitignored — keep your API key + db creds there so you don't have
# to re-export them on every shell.
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

commit=0
extra_args=()
for arg in "$@"; do
    case "$arg" in
        --commit) commit=1 ;;
        *)        extra_args+=("$arg") ;;
    esac
done

# ── Step 1: SSH tunnel ────────────────────────────────────────────────
echo "==> Opening SSH tunnel to ${SSH_HOST} (localhost:${TUNNEL_PORT} → :5432)..."
# Kill any stale tunnel on the same local port, then open a fresh one in
# the background. ExitOnForwardFailure makes ssh exit (not silently
# proceed) if the forward can't bind.
pkill -f "ssh.*${TUNNEL_PORT}:127\\.0\\.0\\.1:5432.*${SSH_HOST}" 2>/dev/null || true
sleep 1
ssh -fNL "${TUNNEL_PORT}:127.0.0.1:5432" "$SSH_HOST" -o ExitOnForwardFailure=yes
trap 'pkill -f "ssh.*'${TUNNEL_PORT}':127\\.0\\.0\\.1:5432.*'${SSH_HOST}'" 2>/dev/null || true' EXIT
# Give the tunnel a beat to come up.
for _ in 1 2 3 4 5; do
    nc -z 127.0.0.1 "$TUNNEL_PORT" 2>/dev/null && break
    sleep 1
done

# ── Step 2: qcheck ────────────────────────────────────────────────────
echo "==> Running qcheck..."
qcheck_args=("--pause" "300ms")
if [ "$commit" -eq 1 ]; then
    qcheck_args+=("--commit" "--cleanup-flagged")
fi
qcheck_args+=("${extra_args[@]}")

env \
    DB_HOST=127.0.0.1 \
    DB_PORT="$TUNNEL_PORT" \
    DB_USER="$DB_USER" \
    DB_PASSWORD="$DB_PASSWORD" \
    DB_NAME="$DB_NAME" \
    DB_SSLMODE=disable \
    ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
    go -C backend run ./cmd/qcheck "${qcheck_args[@]}"

# ── Step 3: orphan sweep on prod (only when we actually wrote) ───────
if [ "$commit" -eq 1 ]; then
    echo "==> Sweeping orphan variant objects from MinIO (on prod host)..."
    ssh "$SSH_HOST" "cd /opt/app/wallpaper && bash scripts/sweep-orphan-variants.sh --apply"
fi

echo "==> Done. Review the admin moderation queue if any rows were flagged."
