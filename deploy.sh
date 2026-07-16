#!/usr/bin/env bash
# One-click backend deploy: ssh to the production host and run
# `./wallctl.sh deploy` (git pull + rebuild api/worker + restart).
#
# The web frontend is deployed separately by Cloudflare Pages from main.
# Run this script after `git push` only when backend code/config changed.
#
# Usage:
#   ./deploy.sh                       # api + worker
#   ./deploy.sh backend               # api + worker
#   SSH_HOST=root@1.2.3.4 ./deploy.sh # override host
set -euo pipefail

: "${SSH_HOST:=root@139.224.49.94}"
: "${SSH_DEPLOY_PATH:=/opt/app/wallpaper}"

if [[ "${1:-}" == "frontend" || "${1:-}" == "web" ]]; then
    echo "Frontend is deployed by Cloudflare Pages; there is no server frontend service." >&2
    exit 2
fi

if [ $# -gt 0 ]; then
    # Scoped deploy: pull the latest code first, then rebuild only the named
    # service(s). Without `git pull` the container rebuild would just bake
    # whatever was already on disk and silently drop your latest commits.
    echo "==> Deploying via $SSH_HOST → git pull + wallctl.sh restart $*"
    ssh "$SSH_HOST" "cd '$SSH_DEPLOY_PATH' && git pull --ff-only && ./wallctl.sh restart $*"
else
    echo "==> Deploying via $SSH_HOST → wallctl.sh deploy"
    ssh "$SSH_HOST" "cd '$SSH_DEPLOY_PATH' && ./wallctl.sh deploy"
fi
echo "==> Done."
