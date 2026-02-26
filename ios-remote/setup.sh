#!/bin/bash
# utsutsu-code iOS Remote - Setup Script
#
# Sets up the relay server and session logging for iOS remote viewing.
#
# Usage:
#   ./setup.sh          # Install dependencies + start server
#   ./setup.sh install   # Install dependencies only
#   ./setup.sh start     # Start relay server
#   ./setup.sh stop      # Stop relay server
#   ./setup.sh status    # Check server status

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$SCRIPT_DIR/server"
SIGNAL_DIR="$HOME/.claude/utsutsu-code"
PID_FILE="$SIGNAL_DIR/relay_server.pid"
LOG_FILE="$SIGNAL_DIR/relay_server.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

info()  { echo -e "${PURPLE}[ios-remote]${NC} $1"; }
ok()    { echo -e "${GREEN}[ios-remote]${NC} $1"; }
warn()  { echo -e "${YELLOW}[ios-remote]${NC} $1"; }
err()   { echo -e "${RED}[ios-remote]${NC} $1"; }

install_deps() {
    info "Installing Python dependencies..."
    pip3 install -r "$SERVER_DIR/requirements.txt" --quiet
    ok "Dependencies installed"

    # Optional: install zeroconf for Bonjour discovery
    pip3 install zeroconf --quiet 2>/dev/null && ok "Bonjour (zeroconf) installed" || warn "zeroconf not available (Bonjour discovery disabled)"

    # Ensure signal directory exists
    mkdir -p "$SIGNAL_DIR"
    ok "Signal directory ready: $SIGNAL_DIR"
}

start_server() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            warn "Relay server already running (PID $pid)"
            return
        fi
        rm -f "$PID_FILE"
    fi

    local port="${RELAY_PORT:-8765}"
    info "Starting relay server on port $port..."
    nohup python3 "$SERVER_DIR/relay_server.py" > "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"

    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        ok "Relay server started (PID $pid)"
        ok "WebSocket: ws://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'localhost'):$port"
        info "Log: $LOG_FILE"
    else
        err "Failed to start relay server. Check $LOG_FILE"
        return 1
    fi
}

stop_server() {
    if [ ! -f "$PID_FILE" ]; then
        warn "No relay server running"
        return
    fi

    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        rm -f "$PID_FILE"
        ok "Relay server stopped (PID $pid)"
    else
        rm -f "$PID_FILE"
        warn "Relay server was not running (stale PID file removed)"
    fi
}

status() {
    echo ""
    info "=== utsutsu-code iOS Remote Status ==="
    echo ""

    # Server
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            ok "Relay server: RUNNING (PID $pid)"
        else
            warn "Relay server: STOPPED (stale PID)"
        fi
    else
        warn "Relay server: NOT RUNNING"
    fi

    # Session log
    if [ -f "$SIGNAL_DIR/session.jsonl" ]; then
        local lines
        lines=$(wc -l < "$SIGNAL_DIR/session.jsonl")
        ok "Session log: $lines lines"
    else
        info "Session log: empty"
    fi

    # Network
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
    info "Connect iOS to: ws://$ip:${RELAY_PORT:-8765}"
    echo ""
}

case "${1:-}" in
    install)
        install_deps
        ;;
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    status)
        status
        ;;
    *)
        install_deps
        start_server
        status
        ;;
esac
