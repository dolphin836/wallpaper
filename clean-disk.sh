#!/usr/bin/env bash
# Reclaim disk on the prod host — the safe subset of what was done manually
# on 2026-05-27 when the disk hit 100% and took Kafka down.
#
# It ONLY removes things that regenerate or are pure logs:
#   - docker build cache         (docker builder prune -af)
#   - docker images with no container  (docker image prune -af)
#   - systemd journal over the size cap (journalctl --vacuum-size)
#
# It deliberately does NOT touch docker volumes. On this host the "dangling"
# volume list includes named volumes for other apps that just aren't running
# right now (word-game_mysql_data, dolphin_*, wallpaper_caddy_*); a
# `docker volume prune` would delete their data. MinIO's 13G of wallpapers
# lives in a volume too — never pruned here. Clean those by hand if ever
# needed.
#
# Usage:
#   ./clean-disk.sh            # show usage, ask to confirm, then clean
#   ./clean-disk.sh --check    # show usage only, change nothing
#   ./clean-disk.sh -y         # skip the confirmation prompt
#   SSH_HOST=root@1.2.3.4 ./clean-disk.sh
#   JOURNAL_KEEP=200M ./clean-disk.sh   # raise the journal size cap
set -euo pipefail

: "${SSH_HOST:=root@139.224.49.94}"
: "${JOURNAL_KEEP:=80M}"

CHECK_ONLY=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --check|-n) CHECK_ONLY=1 ;;
        --yes|-y)   ASSUME_YES=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

echo "==> Inspecting disk on $SSH_HOST"
ssh "$SSH_HOST" '
    echo "--- df / ---"
    df -h /
    echo "--- docker reclaimable ---"
    docker system df
    echo "--- journal ---"
    journalctl --disk-usage 2>/dev/null || true
'

if [ "$CHECK_ONLY" -eq 1 ]; then
    echo "==> --check: nothing changed."
    exit 0
fi

echo
echo "Will run on $SSH_HOST (volumes are NOT touched):"
echo "  - docker builder prune -af"
echo "  - docker image prune -af"
echo "  - journalctl --vacuum-size=$JOURNAL_KEEP"
echo

if [ "$ASSUME_YES" -ne 1 ]; then
    read -r -p "Proceed? [y/N] " ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *) echo "==> Aborted."; exit 0 ;;
    esac
fi

echo "==> Cleaning..."
ssh "$SSH_HOST" "
    set -e
    echo '--- docker builder prune ---'
    docker builder prune -af | tail -1
    echo '--- docker image prune ---'
    docker image prune -af | tail -1
    echo '--- journal vacuum ---'
    journalctl --vacuum-size=$JOURNAL_KEEP 2>&1 | tail -1
    echo '--- df / (after) ---'
    df -h /
"
echo "==> Done."
