#!/usr/bin/env bash
# One-click prod deploy: ssh to the production host and run `./wallctl.sh deploy`
# (git pull + rebuild api/worker/frontend + restart).
#
# Replaces the old .github/workflows/deploy.yml — push no longer auto-deploys;
# run this locally after `git push` when you actually want prod to update.
#
# Usage:
#   ./deploy.sh                       # full stack: api, worker, frontend
#   ./deploy.sh backend               # only api+worker
#   ./deploy.sh frontend              # only the SPA container
#   SSH_HOST=root@1.2.3.4 ./deploy.sh # override host
set -euo pipefail

: "${SSH_HOST:=root@139.224.49.94}"
: "${SSH_DEPLOY_PATH:=/opt/app/wallpaper}"

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
