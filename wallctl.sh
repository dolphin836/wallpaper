#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
PROJECT_NAME="wallpaper"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

compose() {
    docker compose -f "$COMPOSE_FILE" -p "$PROJECT_NAME" "$@"
}

cmd_start() {
    log_info "Starting all services..."
    compose up -d --build
    log_info "Waiting for health checks..."
    sleep 5
    cmd_status
    log_info "All services started."
}

cmd_stop() {
    log_info "Stopping all services..."
    compose down
    log_info "All services stopped."
}

cmd_restart() {
    local target="${1:-all}"
    case "$target" in
        all)
            log_info "Rebuilding and restarting all services..."
            compose up -d --build
            ;;
        backend|api+worker)
            log_info "Rebuilding and restarting backend (api + worker)..."
            compose up -d --build --no-deps api worker
            ;;
        frontend|web)
            log_error "Frontend is deployed by Cloudflare Pages; no server service exists."
            return 2
            ;;
        app)
            log_info "Rebuilding and restarting app services (api + worker)..."
            compose up -d --build --no-deps api worker
            ;;
        *)
            log_info "Rebuilding and restarting: $target"
            compose up -d --build --no-deps "$target"
            ;;
    esac
    sleep 3
    cmd_status
}

cmd_status() {
    echo ""
    echo -e "${CYAN}=== Service Status ===${NC}"
    echo ""
    compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    echo ""

    echo -e "${CYAN}=== Health Checks ===${NC}"
    echo ""
    for svc in postgres redis minio kafka; do
        local health
        health=$(docker inspect --format='{{.State.Health.Status}}' "${PROJECT_NAME}-${svc}-1" 2>/dev/null \
            || docker inspect --format='{{.State.Health.Status}}' "${PROJECT_NAME}_${svc}" 2>/dev/null \
            || echo "not running")
        case "$health" in
            healthy)   echo -e "  ${svc}: ${GREEN}${health}${NC}" ;;
            unhealthy) echo -e "  ${svc}: ${RED}${health}${NC}" ;;
            *)         echo -e "  ${svc}: ${YELLOW}${health}${NC}" ;;
        esac
    done
    echo ""
}

cmd_logs() {
    local target="${1:-}"
    local lines="${2:-100}"
    if [ -z "$target" ]; then
        compose logs -f --tail="$lines"
    else
        compose logs -f --tail="$lines" "$target"
    fi
}

cmd_build() {
    local target="${1:-all}"
    case "$target" in
        all)
            log_info "Building all images..."
            compose build
            ;;
        backend|api+worker)
            log_info "Building backend images..."
            compose build api worker
            ;;
        frontend|web)
            log_error "Frontend is built and deployed by Cloudflare Pages."
            return 2
            ;;
        *)
            log_info "Building: $target"
            compose build "$target"
            ;;
    esac
    log_info "Build complete."
}

cmd_deploy() {
    log_info "Deploying (pull latest + rebuild + restart)..."

    log_info "Pulling latest code..."
    (cd "$SCRIPT_DIR" && git pull --ff-only)

    # Trim the docker build cache before rebuilding. The cache otherwise
    # grows to 15-20GB and twice now has filled the 40GB root volume
    # mid-build with "no space left on device". Keeping a 4GB working
    # set means most layers still hit cache, just not ancient ones.
    log_info "Pruning docker build cache (keeping 4GB)..."
    docker builder prune -f --keep-storage=4GB >/dev/null 2>&1 || true

    log_info "Rebuilding and restarting backend services..."
    compose up -d --build api worker

    log_info "Ensuring the Cloudflare origin tunnel is running..."
    compose up -d cloudflared

    sleep 3
    cmd_status
    log_info "Deploy complete."
}

cmd_clean() {
    log_warn "This will remove all containers, images, and volumes."
    read -rp "Are you sure? [y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        compose down -v --rmi local
        log_info "Cleaned up."
    else
        log_info "Cancelled."
    fi
}

cmd_reset_data() {
    log_warn "This will DELETE all data EXCEPT user accounts (users table)."
    log_warn "Includes: wallpapers, variants, uploads (MinIO), collections, likes, favorites, downloads, coins, etc."
    read -rp "Are you sure? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Cancelled."
        return
    fi

    local DB_USER="${POSTGRES_USER:-wallpaper}"
    local DB_NAME="${POSTGRES_DB:-wallpaper}"
    local MINIO_BUCKET="${MINIO_BUCKET:-wallpapers}"

    log_info "Truncating database tables (keeping users)..."
    compose exec -T postgres psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
TRUNCATE TABLE wallpaper_events       CASCADE;
TRUNCATE TABLE wallpaper_variants     CASCADE;
TRUNCATE TABLE wallpaper_tags         CASCADE;
TRUNCATE TABLE collection_wallpapers  CASCADE;
TRUNCATE TABLE collection_likes       CASCADE;
TRUNCATE TABLE collections            CASCADE;
TRUNCATE TABLE user_likes             CASCADE;
TRUNCATE TABLE user_favorites         CASCADE;
TRUNCATE TABLE user_downloads         CASCADE;
TRUNCATE TABLE coin_transactions      CASCADE;
TRUNCATE TABLE wallpapers             CASCADE;
TRUNCATE TABLE tags                   CASCADE;
UPDATE users SET coins = 10 WHERE id > 0;
COMMIT;
SQL
    log_info "Database tables truncated."

    log_info "Clearing MinIO bucket: ${MINIO_BUCKET}..."
    compose exec minio sh -c "
        mc alias set local http://localhost:9000 \${MINIO_ROOT_USER} \${MINIO_ROOT_PASSWORD} --api S3v4 2>/dev/null
        mc rm --recursive --force local/${MINIO_BUCKET}/ 2>/dev/null || true
    "
    log_info "MinIO bucket cleared."

    log_info "Flushing Redis cache..."
    local REDIS_PW="${REDIS_PASSWORD:-}"
    if [ -n "$REDIS_PW" ]; then
        compose exec redis redis-cli -a "$REDIS_PW" FLUSHALL
    else
        compose exec redis redis-cli FLUSHALL
    fi
    log_info "Redis flushed."

    log_info "Stopping worker to reset Kafka offsets..."
    compose stop worker 2>/dev/null || true
    sleep 2

    log_info "Resetting Kafka consumer group offsets..."
    compose exec kafka /opt/kafka/bin/kafka-consumer-groups.sh \
        --bootstrap-server localhost:9092 \
        --group image-worker --topic wallpaper.uploaded \
        --reset-offsets --to-latest --execute 2>/dev/null || true
    compose exec kafka /opt/kafka/bin/kafka-consumer-groups.sh \
        --bootstrap-server localhost:9092 \
        --group stats-worker --topic wallpaper.stats \
        --reset-offsets --to-latest --execute 2>/dev/null || true

    log_info "Restarting worker..."
    compose start worker 2>/dev/null || true
    log_info "Kafka offsets reset."

    log_info "Restarting worker to re-establish Kafka consumers..."
    compose restart worker
    log_info "Worker restarted."

    log_info "Data reset complete. User accounts preserved (coins reset to 10)."
}

cmd_db_shell() {
    compose exec postgres psql -U wallpaper -d wallpaper
}

cmd_db_migrate() {
    log_info "Running database migration..."
    compose exec -T postgres psql -U wallpaper -d wallpaper < "${SCRIPT_DIR}/deployments/init.sql"
    log_info "Migration complete."
}

cmd_sluggen() {
    local flag="${1:-}"
    log_info "Regenerating slugs for wallpapers and collections..."
    if [ "$flag" = "--force" ]; then
        log_warn "Force mode: ALL slugs will be regenerated."
        compose exec api /bin/sluggen --force
    else
        compose exec api /bin/sluggen
    fi
    log_info "Slug generation complete."
}

cmd_autotag() {
    # Runs Claude vision over published wallpapers to fill category_id +
    # tags + (optionally) titles. Defaults to dry-run; pass --commit (and
    # optionally --limit N for a canary batch) to actually write.
    log_info "Autotag: classifying wallpapers via Claude vision..."
    compose exec api /bin/autotag "$@"
}

cmd_aicheck() {
    # Detect clearly AI-generated wallpapers from preview_url bytes only.
    # Defaults to dry-run; use --commit to persist true classifications.
    log_info "AI check: assessing locally-downloaded preview images..."
    compose exec api /bin/aicheck "$@"
}

cmd_recompress() {
    # Re-queues published wallpapers through the image worker so they pick
    # up new variant encoding defaults. Defaults to dry-run; pass --commit
    # (and optionally --limit N for a canary batch) to actually publish.
    log_info "Recompress: re-queueing wallpapers through the image worker..."
    compose exec api /bin/recompress "$@"
}

cmd_phashgen() {
    log_info "Backfilling pHash for published wallpapers..."
    # Pass through every arg so caller can tune --timeout / --concurrency /
    # --force / --report-dupes without us having to enumerate combinations.
    compose exec api /bin/phashgen "$@"
    log_info "pHash backfill complete."
}

cmd_setadmin() {
    # Toggle the is_admin flag on a user. Pass-through to /bin/setadmin inside
    # the api container so we don't have to wire up another DB connection here.
    if [ "$#" -eq 0 ]; then
        log_warn "Usage: ./wallctl.sh setadmin -username <name>|-email <addr> -on|-off"
        exit 2
    fi
    compose exec api /bin/setadmin "$@"
}

cmd_variantgc() {
    # Reclaim lazily-generated device variants that have gone cold. Variants
    # are produced on first download and cached under derived/; this deletes
    # the MinIO object + DB row for any not served within the TTL (default
    # 30d). Cron-friendly. Pass --dry-run to preview, --days N to tune.
    log_info "Reclaiming cold on-demand variants..."
    compose exec api /bin/variantgc "$@"
}

cmd_help() {
    cat <<EOF
${CYAN}wallctl.sh${NC} - WallShare Application Manager

${YELLOW}Usage:${NC}
  ./wallctl.sh <command> [args]

${YELLOW}Commands:${NC}
  ${GREEN}start${NC}                   Start all services (build + start)
  ${GREEN}stop${NC}                    Stop all services
  ${GREEN}restart${NC}  [target]       Rebuild and restart services
  ${GREEN}status${NC}                  Show service status and health
  ${GREEN}logs${NC}     [service] [n]  Tail logs (default: all, last 100 lines)
  ${GREEN}build${NC}    [target]       Build images only (no restart)
  ${GREEN}deploy${NC}                  Git pull + rebuild + restart app services
  ${GREEN}clean${NC}                   Remove all containers, images, and volumes
  ${GREEN}reset-data${NC}              Delete all data except user accounts
  ${GREEN}db-shell${NC}                Open psql shell to the database
  ${GREEN}db-migrate${NC}              Run deployments/init.sql on the database
  ${GREEN}sluggen${NC}   [--force]     Regenerate URL slugs (--force = all, default = empty only)
  ${GREEN}phashgen${NC}  [flag]        Backfill pHash for old wallpapers (--force | --report-dupes)
  ${GREEN}recompress${NC}[flags]       Re-queue wallpapers to rebuild variants (--commit, --limit N)
  ${GREEN}autotag${NC}   [flags]       Classify wallpapers via Claude vision (--commit, --limit N)
  ${GREEN}aicheck${NC}   [flags]       Detect AI-generated wallpapers from previews (--commit, --limit N)
  ${GREEN}setadmin${NC}  [args]        Toggle is_admin on a user (e.g. -username eric -on)
  ${GREEN}help${NC}                    Show this help message

${YELLOW}Restart targets:${NC}
  ${GREEN}all${NC}                     All services (default)
  ${GREEN}backend${NC}                 api + worker
  ${GREEN}app${NC}                     api + worker
  ${GREEN}<service>${NC}               Any single service (e.g. api, worker, minio)

${YELLOW}Examples:${NC}
  ./wallctl.sh restart                 # Rebuild & restart everything
  ./wallctl.sh restart backend         # Rebuild & restart api + worker
  ./wallctl.sh restart worker          # Rebuild & restart worker only
  ./wallctl.sh logs api 200            # Tail last 200 lines of api logs
  ./wallctl.sh deploy                  # Git pull + rebuild + restart
  ./wallctl.sh db-migrate              # Apply DB schema changes
EOF
}

case "${1:-help}" in
    start)      cmd_start ;;
    stop)       cmd_stop ;;
    restart)    cmd_restart "${2:-all}" ;;
    status)     cmd_status ;;
    logs)       cmd_logs "${2:-}" "${3:-100}" ;;
    build)      cmd_build "${2:-all}" ;;
    deploy)     cmd_deploy ;;
    clean)      cmd_clean ;;
    reset-data) cmd_reset_data ;;
    db-shell)   cmd_db_shell ;;
    db-migrate) cmd_db_migrate ;;
    sluggen)    cmd_sluggen "${2:-}" ;;
    phashgen)   shift; cmd_phashgen "$@" ;;
    recompress) shift; cmd_recompress "$@" ;;
    autotag)    shift; cmd_autotag "$@" ;;
    aicheck)    shift; cmd_aicheck "$@" ;;
    setadmin)   shift; cmd_setadmin "$@" ;;
    variantgc)  shift; cmd_variantgc "$@" ;;
    help|*)     cmd_help ;;
esac
