#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Daily Rewards — Unified Startup Script
# 
# Usage:
#   ./start.sh                  # Start everything (backend + client)
#   ./start.sh backend          # Start only the API server
#   ./start.sh client           # Start only the LÖVE2D client  
#   ./start.sh docker-dev       # Start via Docker Compose dev mode
#   ./start.sh docker-prod      # Start via Docker Compose prod mode
#   ./start.sh test             # Run unit tests
#   ./start.sh clean            # Stop containers and processes
#   ./start.sh help             # Show this help message
# ═══════════════════════════════════════════════════════════

set -e

# ─── Colors & Formatting ────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()      { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR ]${NC} $*" >&2; }
header()  { printf "\n${CYAN}%0.s─" $(seq 1 50); echo ""; echo -e " ${BLUE}$*${NC}"; printf "%0.s─" $(seq 1 50); echo "";}

# ─── Paths ──────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR/backend"
CLIENT_DIR="$SCRIPT_DIR/client"
ENV_FILE="$SCRIPT_DIR/.env"
DB_CONTAINER_NAME="daily-rewards-db-local"
PID_FILE="$SCRIPT_DIR/.backend.pid"

# ─── Load Environment Variables ─────────────────────────────────
load_env() {
    if [ -f "$ENV_FILE" ]; then
        export $(grep -v '^#' "$ENV_FILE" | xargs)
        ok "Loaded .env file"
    else
        warn ".env not found — using defaults"
    fi
}

# ─── Dependency Checks ──────────────────────────────────────────
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error "Required '$1' not found in PATH"
        return 1
    fi
    ok "'$1' available ($(command -v "$1"))"
}

ensure_env_file() {
    [ -f "$ENV_FILE" ] || cp "$SCRIPT_DIR/.env.example" "$ENV_FILE" 2>/dev/null || true
    if [ ! -f "$BACKEND_DIR/.env" ]; then
        cp "$BACKEND_DIR/.env.example" "$BACKEND_DIR/.env" 2>/dev/null || true
    fi
}

# ─── Database Management ────────────────────────────────────────
start_database() {
    header "Starting PostgreSQL Database"
    
    local db_port="${DB_PORT:-5432}"
    local db_name="${POSTGRES_DB:-daily_rewards}"
    local db_user="${POSTGRES_USER:-dev}"
    local db_pass="${POSTGRES_PASSWORD:-dev}"
    
    # Remove any existing container with this name (running or stopped)
    if docker ps -a --format '{{.Names}}' | grep -qx "$DB_CONTAINER_NAME" 2>/dev/null; then
        info "Removing existing '$DB_CONTAINER_NAME' container..."
        docker rm -f "$DB_CONTAINER_NAME" 2>/dev/null || true
    fi
    
    # Check if port is already in use by any other container
    if docker ps --format '{{.Ports}}' | grep -q ":${db_port}->"; then
        error "Port ${db_port} is already in use by another container"
        docker ps --filter "publish=${db_port}" --format '{{.Names}}: {{.Ports}}'
        return 1
    fi
    
    info "Starting PostgreSQL in Docker..."
    
    # Create persistent volume if it doesn't exist
    docker volume create "$DB_CONTAINER_NAME-data" 2>/dev/null || true
    
    docker run -d \
        --name "$DB_CONTAINER_NAME" \
        -e POSTGRES_DB="$db_name" \
        -e POSTGRES_USER="$db_user" \
        -e POSTGRES_PASSWORD="$db_pass" \
        -p "${db_port}:5432" \
        -v "$DB_CONTAINER_NAME-data:/var/lib/postgresql/data" \
        --restart unless-stopped \
        postgres:16-alpine
    
    info "Waiting for PostgreSQL..."
    local max=30 attempt=0
    while [ $attempt -lt $max ]; do
        if docker exec "$DB_CONTAINER_NAME" pg_isready -U "$db_user" -d "$db_name" &>/dev/null; then
            ok "Database ready on port $db_port (attempt $((attempt + 1)))"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done
    
    error "Database failed to start after ${max} attempts"
    docker logs --tail 20 "$DB_CONTAINER_NAME"
    return 1
}

apply_migrations() {
    header "Applying Database Migrations"
    
    cd "$BACKEND_DIR"
    [ -d node_modules ] || npm install --silent 2>/dev/null
    
    export DATABASE_URL="postgresql://${POSTGRES_USER:-dev}:${POSTGRES_PASSWORD:-dev}@localhost:${DB_PORT:-5432}/${POSTGRES_DB:-daily_rewards}"
    
    if npx prisma migrate deploy --schema=./prisma/schema.prisma 2>&1; then
        ok "Migrations applied successfully"
        npx prisma generate --schema=./prisma/schema.prisma &>/dev/null || true
    else
        error "Migration failed"
        return 1
    fi
    
    cd "$SCRIPT_DIR"
}

# ─── Backend Management ────────────────────────────────────────
start_backend() {
    local daemonize="${1:-true}"
    
    header "Starting API Server (TypeScript + tsx)"
    
    cd "$BACKEND_DIR"
    [ -d node_modules ] || npm install --silent 2>/dev/null
    
    if [ "$daemonize" = true ]; then
        # Daemon mode: logs to file, returns immediately
        local log_file="$SCRIPT_DIR/.backend.log"
        
        npx tsx watch src/server.ts > "$log_file" 2>&1 &
        local pid=$!
        echo $pid > "$PID_FILE"
        
        # Wait for server readiness
        local max=30 attempt=0
        while [ $attempt -lt $max ]; do
            if curl -s http://localhost:${API_PORT:-3000}/health &>/dev/null; then
                ok "Backend running on port ${API_PORT:-3000} (PID: $pid)"
                echo "   Logs: $log_file"
                return 0
            fi
            sleep 1
            attempt=$((attempt + 1))
        done
        
        error "Server failed to start. Check logs:"
        cat "$log_file" | tail -20
        kill $pid 2>/dev/null || true
        rm -f "$PID_FILE"
        return 1
    else
        # Foreground mode: direct output, blocks until Ctrl+C
        info "Starting server on port ${API_PORT:-3000}... (Ctrl+C to stop)"
        echo ""
        npx tsx watch src/server.ts
    fi
}

stop_backend() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 $pid 2>/dev/null; then
            info "Stopping backend (PID: $pid)..."
            kill $pid 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
        ok "Backend stopped"
    else
        # Try to find and kill any running tsx server processes
        pkill -9 -f "tsx.*server.ts" 2>/dev/null && ok "Killed all backend processes" || true
    fi
}

# ─── Client Management ─────────────────────────────────────────
# ─── Client Management ─────────────────────────────────────────
start_client() {
    header "Starting LÖVE2D Client"
    
    cd "$CLIENT_DIR"
    if [ ! -f main.lua ]; then
        error "main.lua not found in client directory"
        return 1
    fi
    
    check_command love || return 1
    
    info "Opening game window..."
    echo ""
    love .
}

# ─── Tests ─────────────────────────────────────────────────────
run_tests() {
    header "Running Unit Tests"
    
    local lua_available=false
    if command -v lua &>/dev/null; then
        check_command lua || true
        lua_available=true
    else
        warn "Lua not found — skipping client tests (install lua5.3 or later)"
    fi
    
    echo ""
    info "Backend tests (TypeScript + Vitest)..."
    cd "$BACKEND_DIR"
    [ -d node_modules ] || npm install --silent 2>/dev/null
    npx vitest run --reporter=verbose 2>&1
    local backend_result=$?
    
    if [ $backend_result -ne 0 ]; then
        error "Backend tests failed"
    fi
    
    echo ""
    if [ "$lua_available" = true ]; then
        info "Client tests (Lua JSON library)..."
        cd "$CLIENT_DIR"
        
        # Run JSON unit tests
        lua tests/json_tests.lua
        local json_result=$?
        
        if [ $json_result -ne 0 ]; then
            error "JSON tests failed"
        fi
        
        echo ""
        info "Client API integration tests (requires running backend)..."
        curl -s http://localhost:${API_PORT:-3000}/health &>/dev/null
        if [ $? -eq 0 ]; then
            lua tests/api_tests.lua
            local api_result=$?
            
            if [ $api_result -ne 0 ]; then
                warn "API integration tests failed (backend may have changed behavior)"
            fi
        else
            warn "Backend not running — skipping API integration tests"
        fi
    fi
    
    header "Test Results"
    return $((backend_result))
}

# ─── Docker Mode ────────────────────────────────────────────────
docker_mode() {
    local mode="$1"
    
    check_command docker || return 1
    
    header "Docker ($mode) Mode"
    
    ensure_env_file
    
    local compose_file=""
    case "$mode" in
        dev)   info "Development (hot reload, mounted sources)" ;;
        prod)  info "Production (compiled TypeScript)" ;;
        *)     error "Unknown mode: $mode"; return 1 ;;
    esac
    
    local cf="$SCRIPT_DIR/docker-compose.${mode}.yml"
    if [ ! -f "$cf" ]; then
        error "File not found: $cf"
        return 1
    fi
    
    cd "$SCRIPT_DIR"
    
    info "Building API image..."
    docker-compose -f "$cf" build api 2>&1 | tail -3
    
    info "Starting containers..."
    echo ""
    docker-compose -f "$cf" up -d 2>&1
    
    ok "API available at http://localhost:${API_PORT:-3000}"
    
    read -p "Show live logs? [y/N] " -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        docker-compose -f "$cf" logs -f api 2>&1 | sed 's/^/[API] /'
    fi
}

# ─── Clean Up ──────────────────────────────────────────────────
clean_up() {
    header "Cleaning Up"
    
    stop_backend
    
    docker rm -f "$DB_CONTAINER_NAME" 2>/dev/null && ok "Removed DB container (data preserved in volume)" || warn "No DB container found"
    pkill -x love 2>/dev/null && ok "Stopped LÖVE client" || true
    
    rm -f "$PID_FILE" .backend.log .backend.pid
    docker-compose -f "$SCRIPT_DIR/docker-compose.dev.yml" down -v 2>/dev/null || true
    docker-compose -f "$SCRIPT_DIR/docker-compose.prod.yml" down -v 2>/dev/null || true
    
    ok "Cleanup complete"
}

# ─── Help ──────────────────────────────────────────────────────
show_help() {
    cat <<'HELP'
╔═══════════════════════════════════════════════════╗
║  Daily Rewards — Startup Script                  ║
╚═══════════════════════════════════════════════════╝

Usage: ./start.sh [command]

Commands:
  (none)        Start everything (DB + backend + client)
  backend       Start only the API server (daemon mode)
  frontend      Run LÖVE2D client
  docker-dev    Everything in Docker (development)
  docker-prod   Everything in Docker (production)
   test          Run unit tests (backend + client Lua)
  clean         Stop everything and remove containers
  help          Show this message

Examples:
  ./start.sh                  # Full start (DB + backend + client)
  ./start.sh backend          # API server only (for development)
  ./start.sh docker-dev       # Docker Compose dev mode
  ./start.sh test             # Run tests only

Environment (.env file):
  DB_PORT=5432          Database port
  API_PORT=3000         Server port  
  POSTGRES_DB=daily_rewards
  POSTGRES_USER=dev
  POSTGRES_PASSWORD=dev
  JWT_SECRET=<random>   Change in production!

HELP
}

# ─── Main ──────────────────────────────────────────────────────
main() {
    local cmd="${1:-all}"
    
    header "Daily Rewards Startup"
    load_env
    
    case "$cmd" in
        backend)
            start_database || exit 1
            apply_migrations || exit 1
            start_backend true
            ;;
        
        frontend|"client")
            check_command love || exit 1
            start_client
            ;;
            
        docker-dev|docker-prod)
            local mode="${cmd#docker-}"
            docker_mode "$mode"
            ;;
            
        test)
            run_tests || exit 1
            ;;
            
        clean)
            clean_up
            ;;
            
        help|--help|-h)
            show_help
            ;;
            
        all|"")
            local has_errors=0
            
            # Check dependencies
            header "Checking Dependencies"
            
            check_command docker || { warn "Docker unavailable — will try native"; HAS_DOCKER=false; }
            echo ""
            
            if ! command -v node &>/dev/null; then
                warn "Node.js not found — backend must use Docker or be started manually"
                HAS_NODE=false
            else
                check_command node || true
                HAS_NODE=true
            fi
            
            echo ""
            if ! command -v love &>/dev/null; then
                warn "LÖVE2D not installed — client requires manual start: love ."
                HAS_LOVE=false
            else
                ok "LÖVE2D available"
                HAS_LOVE=true
            fi
            
            # Always needed
            echo ""
            start_database || exit 1
            apply_migrations || exit 1
            
            # Start backend (background)
            if [ "$HAS_NODE" = true ]; then
                echo ""
                start_backend true
                
                # Start client if available
                if [ "$HAS_LOVE" = true ]; then
                    echo ""
                    start_client &
                    wait $! 2>/dev/null || true
                fi
            else
                warn "Skipping backend (Node.js not found)"
            fi
            
            header "All Systems Ready"
            info "API: http://localhost:${API_PORT:-3000}"
            
            # Keep alive for Ctrl+C handling
            trap 'echo -e "\n${YELLOW}Shutting down...${NC}"; stop_backend; docker stop "$DB_CONTAINER_NAME" 2>/dev/null || true; exit 0' INT TERM
            
            wait
            ;;
            
        *)
            error "Unknown command: $cmd"
            show_help
            return 1
            ;;
    esac
}

# Global Ctrl+C handler for daemon mode
trap 'echo -e "\n${YELLOW}Shutting down...${NC}"; stop_backend; docker stop "$DB_CONTAINER_NAME" 2>/dev/null || true; exit 0' INT TERM

main "$@"
