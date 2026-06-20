#!/bin/bash
# Shared logic for the Local DeepSeek (DwarfStar / DeepSeek V4 Flash) launchers.
# Sourced by lds.sh (skip permissions) and lds-safe.sh (safe mode).
#
# Flow: boot the local ds4-server (if down) -> boot a dedicated Free Claude Code
# proxy on its own port pointed at ds4-server -> run Claude Code -> shut down
# whatever this script started on exit (including terminal close / SIGHUP).

DS4_DIR="/Users/tec/Code/Projects/antirez_DwarfStar4"
PROJECT_DIR="/Users/tec/Code/Projects/free-claude-code"
DS4_PORT=8000                                   # ds4-server default port
PROXY_PORT=8083                                 # dedicated proxy (8082 is the generic ds/glm proxy)
# Use 127.0.0.1, NOT localhost: ds4-server binds IPv4 only, but localhost resolves
# to IPv6 ::1 first on this box where Docker squats on :8000 (would 404 the proxy).
DS4_BASE_URL="http://127.0.0.1:${DS4_PORT}/v1"  # DwarfStar Anthropic endpoint lives at /v1/messages
MODEL_REF="llamacpp/deepseek-v4-flash"          # local provider (anthropic_messages transport) + model id
DS4_LOG="/tmp/ds4-server.log"
PROXY_LOG="/tmp/fcc-lds-proxy.log"

DS4_STARTED=false
PROXY_STARTED=false
DS4_PID=""
PROXY_PID=""
CLEANED=false

port_in_use() { lsof -i ":$1" -sTCP:LISTEN &>/dev/null; }

cleanup() {
    [ "$CLEANED" = true ] && return
    CLEANED=true
    if [ "$PROXY_STARTED" = true ] && [ -n "$PROXY_PID" ]; then
        kill "$PROXY_PID" 2>/dev/null && echo "🛑 Proxy stopped"
    fi
    if [ "$DS4_STARTED" = true ] && [ -n "$DS4_PID" ]; then
        kill "$DS4_PID" 2>/dev/null && echo "🛑 DwarfStar server stopped"
    fi
}

start_dwarfstar() {
    # Detect by process name, not by port: Docker also listens on :8000, so a
    # port check would falsely report DwarfStar as already up.
    if pgrep -f "ds4-server" >/dev/null; then
        echo "✅ DwarfStar already running (not managed by this session)"
        return
    fi
    echo "🚀 Starting DwarfStar (DeepSeek V4 Flash) server..."
    ( cd "$DS4_DIR" && exec ./ds4-server --ctx 100000 --kv-disk-dir /tmp/ds4-kv --kv-disk-space-mb 8192 ) >"$DS4_LOG" 2>&1 &
    DS4_PID=$!
    DS4_STARTED=true
    echo "   logs: $DS4_LOG (pid $DS4_PID)"
    # Loading the GGUF can take a while; wait up to ~300s, bailing early if it dies.
    for i in $(seq 1 600); do
        if ! kill -0 "$DS4_PID" 2>/dev/null; then
            echo "❌ DwarfStar server exited during startup. See $DS4_LOG"
            exit 1
        fi
        if curl -s "http://127.0.0.1:${DS4_PORT}/v1/models" &>/dev/null; then
            echo "✅ DwarfStar ready"
            return
        fi
        if [ $((i % 60)) -eq 0 ]; then
            echo "   ...still loading model ($((i / 2))s)"
        fi
        sleep 0.5
    done
    echo "❌ DwarfStar did not become ready in time. See $DS4_LOG"
    exit 1
}

start_proxy() {
    if port_in_use "$PROXY_PORT"; then
        echo "✅ Proxy already running on :$PROXY_PORT"
        return
    fi
    echo "🚀 Starting Free Claude Code proxy on :$PROXY_PORT..."
    # Pin every model slot to the local ref so this proxy only ever validates/serves
    # DwarfStar — independent of whatever MODEL_* mappings the shared .env carries.
    ( cd "$PROJECT_DIR" \
        && LLAMACPP_BASE_URL="$DS4_BASE_URL" \
           MODEL="$MODEL_REF" MODEL_OPUS="$MODEL_REF" MODEL_SONNET="$MODEL_REF" MODEL_HAIKU="$MODEL_REF" \
        exec uv run uvicorn server:app --host 127.0.0.1 --port "$PROXY_PORT" ) >"$PROXY_LOG" 2>&1 &
    PROXY_PID=$!
    PROXY_STARTED=true
    echo "   logs: $PROXY_LOG (pid $PROXY_PID)"
    for i in $(seq 1 60); do
        if curl -s "http://127.0.0.1:${PROXY_PORT}/v1/models" &>/dev/null; then
            echo "✅ Proxy ready"
            return
        fi
        sleep 0.5
    done
    echo "❌ Proxy did not become ready in time. See $PROXY_LOG"
    exit 1
}

launch_lds() {
    local original_dir
    original_dir="$(pwd)"
    # Tear down on normal exit AND on terminal close (HUP) so the heavy local
    # server never lingers and wastes energy.
    trap cleanup EXIT INT TERM HUP
    start_dwarfstar
    start_proxy
    cd "$original_dir"
    echo "🤖 Launching Claude Code on local DeepSeek V4 Flash (type /exit or Ctrl-D to quit & shut down)"
    if [ "${LDS_SAFE:-false}" = true ]; then
        ANTHROPIC_AUTH_TOKEN="freecc:${MODEL_REF}" ANTHROPIC_BASE_URL="http://127.0.0.1:${PROXY_PORT}" claude "$@"
    else
        ANTHROPIC_AUTH_TOKEN="freecc:${MODEL_REF}" ANTHROPIC_BASE_URL="http://127.0.0.1:${PROXY_PORT}" claude --dangerously-skip-permissions "$@"
    fi
}
