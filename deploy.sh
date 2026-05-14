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

REMOTE_ARGS=("deploy")
if [ $# -gt 0 ]; then
    # `wallctl.sh deploy` doesn't take args today; treat extra args as a
    # `restart <service>` shortcut so `./deploy.sh frontend` Just Works after
    # a pure-frontend change without redeploying everything.
    REMOTE_ARGS=("restart" "$@")
fi

echo "==> Deploying via $SSH_HOST → wallctl.sh ${REMOTE_ARGS[*]}"
ssh "$SSH_HOST" "cd '$SSH_DEPLOY_PATH' && ./wallctl.sh ${REMOTE_ARGS[*]}"
echo "==> Done."
