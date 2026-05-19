#!/usr/bin/env bash
# Find and delete MinIO variant objects that no longer have a matching
# wallpaper_variants row. Runs entirely on the prod host inside the
# docker network — the qcheck CLI's --cleanup-flagged path can leave
# orphans behind when it's run from outside-China (the MinIO SDK can't
# reach the internal :9000 endpoint), so this is the catch-up.
#
# Usage (on prod):
#   ./scripts/sweep-orphan-variants.sh           # dry-run: just list
#   ./scripts/sweep-orphan-variants.sh --apply   # actually delete
set -euo pipefail

cd "$(dirname "$0")/.."
set -a; source .env; set +a
NETWORK="${DOCKER_NETWORK:-wallpaper_default}"
BUCKET="${MINIO_BUCKET:-wallpapers}"

apply=0
if [ "${1:-}" = "--apply" ]; then apply=1; fi

# 1. Dump every CURRENT variant key from DB.
docker compose exec -T postgres psql -U "${POSTGRES_USER:-wallpaper}" -d "${POSTGRES_DB:-wallpaper}" -At -c "
  SELECT regexp_replace(url, '.*/${BUCKET}/', '') FROM wallpaper_variants WHERE url <> '';
" | sort -u > /tmp/db-keys.txt
echo "db has $(wc -l < /tmp/db-keys.txt) variant keys"

# 2. List every MinIO variant object.
docker run --rm --network "$NETWORK" --entrypoint sh minio/mc -c \
  "mc alias set local http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD > /dev/null && mc ls --recursive local/$BUCKET/variants 2>&1" \
  | awk '{print $NF}' | sed 's|^|variants/|' | sort -u > /tmp/minio-keys.txt
echo "minio has $(wc -l < /tmp/minio-keys.txt) variant objects"

# 3. Orphans = in minio, not in db.
comm -23 /tmp/minio-keys.txt /tmp/db-keys.txt > /tmp/orphan-keys.txt
orphan_count=$(wc -l < /tmp/orphan-keys.txt)
echo "orphans: $orphan_count"

if [ "$orphan_count" -eq 0 ]; then
  echo "nothing to do."
  exit 0
fi

if [ "$apply" -eq 0 ]; then
  echo "dry-run — pass --apply to delete. First 5 candidates:"
  head -5 /tmp/orphan-keys.txt
  exit 0
fi

echo "deleting $orphan_count orphan objects..."
docker run --rm -i --network "$NETWORK" -v /tmp/orphan-keys.txt:/tmp/keys.txt --entrypoint sh minio/mc -c "
  mc alias set local http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD > /dev/null
  while read key; do
    mc rm local/$BUCKET/\"\$key\" > /dev/null 2>&1 || echo FAIL: \$key
  done < /tmp/keys.txt
  echo done
"
echo "after cleanup:"
docker run --rm --network "$NETWORK" --entrypoint sh minio/mc -c \
  "mc alias set local http://minio:9000 $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD > /dev/null && mc du --depth 1 local/$BUCKET/variants"
