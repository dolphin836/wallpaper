#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
PROJECT_NAME="wallpaper"

INFRA_SERVICES="postgres redis minio kafka"
APP_SERVICES="api worker frontend caddy"

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
            log_info "Restarting all services..."
            compose down
            compose up -d --build
            ;;
        backend)
            log_info "Rebuilding and restarting backend (api + worker)..."
            compose up -d --build --no-deps api worker
            ;;
        frontend)
            log_info "Rebuilding and restarting frontend..."
            compose up -d --build --no-deps frontend
            ;;
        *)
            log_info "Restarting service: $target"
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
        health=$(docker inspect --format='{{.State.Health.Status}}' "${PROJECT_NAME}-${svc}-1" 2>/dev/null || echo "not running")
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
        backend)
            log_info "Building backend images..."
            compose build api worker
            ;;
        frontend)
            log_info "Building frontend image..."
            compose build frontend
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
    git -C "$SCRIPT_DIR" pull --ff-only

    log_info "Rebuilding and restarting app services..."
    compose up -d --build api worker frontend
    compose restart caddy

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

cmd_db_shell() {
    compose exec postgres psql -U wallpaper -d wallpaper
}

cmd_help() {
    cat <<EOF
${CYAN}wallctl.sh${NC} - WallShare Application Manager

${YELLOW}Usage:${NC}
  ./wallctl.sh <command> [args]

${YELLOW}Commands:${NC}
  ${GREEN}start${NC}                   Start all services
  ${GREEN}stop${NC}                    Stop all services
  ${GREEN}restart${NC}  [target]       Restart services (all|backend|frontend|<service>)
  ${GREEN}status${NC}                  Show service status and health
  ${GREEN}logs${NC}     [service] [n]  Tail logs (default: all, last 100 lines)
  ${GREEN}build${NC}    [target]       Build images (all|backend|frontend|<service>)
  ${GREEN}deploy${NC}                  Git pull + rebuild + restart app services
  ${GREEN}clean${NC}                   Remove all containers, images, and volumes
  ${GREEN}db-shell${NC}                Open psql shell to the database
  ${GREEN}help${NC}                    Show this help message

${YELLOW}Examples:${NC}
  ./wallctl.sh start                 # Start everything
  ./wallctl.sh restart backend       # Rebuild & restart api + worker
  ./wallctl.sh restart frontend      # Rebuild & restart frontend only
  ./wallctl.sh logs api 200          # Tail last 200 lines of api logs
  ./wallctl.sh deploy                # Pull + rebuild + restart

${YELLOW}Environment:${NC}
  SITE_DOMAIN    Set domain for HTTPS (default: localhost)
                 Example: SITE_DOMAIN=wall.example.com ./wallctl.sh start
EOF
}

case "${1:-help}" in
    start)    cmd_start ;;
    stop)     cmd_stop ;;
    restart)  cmd_restart "${2:-all}" ;;
    status)   cmd_status ;;
    logs)     cmd_logs "${2:-}" "${3:-100}" ;;
    build)    cmd_build "${2:-all}" ;;
    deploy)   cmd_deploy ;;
    clean)    cmd_clean ;;
    db-shell) cmd_db_shell ;;
    help|*)   cmd_help ;;
esac
