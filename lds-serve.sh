#!/bin/bash
# Headless Local DeepSeek (DwarfStar / DeepSeek V4 Flash) server for AionUi.
#
# Unlike lds.sh (which launches Claude Code), this just stands up the backend so
# a GUI client like AionUi can talk to local Flash over an Anthropic-compatible
# endpoint, then blocks until you Ctrl-C — at which point it shuts down whatever
# it started (ds4-server and/or the proxy).
#
# Wire into AionUi (Settings -> Models -> Add Model -> "New API"):
#   Base URL : http://127.0.0.1:8083
#   API Key  : freecc
#   Model    : whatever /v1/models prints below (protocol = anthropic)

DS4_DIR="/Users/tec/Code/Projects/antirez_DwarfStar4"
PROJECT_DIR="/Users/tec/Code/Projects/free-claude-code"
DS4_PORT=8000
PROXY_PORT=8083
# 127.0.0.1, NOT localhost: ds4-server binds IPv4 only, and Docker may squat on
# :8000 via IPv6 (::1) which would 404 the proxy.
DS4_BASE_URL="http://127.0.0.1:${DS4_PORT}/v1"
MODEL_REF="llamacpp/deepseek-v4-flash"
DS4_LOG="/tmp/ds4-server.log"
PROXY_LOG="/tmp/fcc-lds-serve-proxy.log"

DS4_STARTED=false
PROXY_STARTED=false
DS4_PID=""
PROXY_PID=""
CLEANED=false

port_in_use() { lsof -i ":$1" -sTCP:LISTEN &>/dev/null; }

cleanup() {
    [ "$CLEANED" = true ] && return
    CLEANED=true
    echo
    if [ "$PROXY_STARTED" = true ] && [ -n "$PROXY_PID" ]; then
        kill "$PROXY_PID" 2>/dev/null && echo "🛑 Proxy (:$PROXY_PORT) stopped"
    fi
    if [ "$DS4_STARTED" = true ] && [ -n "$DS4_PID" ]; then
        kill "$DS4_PID" 2>/dev/null && echo "🛑 DwarfStar server stopped"
    fi
}

start_dwarfstar() {
    # Detect by process name, not port: Docker also listens on :8000.
    if pgrep -f "ds4-server" >/dev/null; then
        echo "✅ DwarfStar already running (not managed by this session)"
        return
    fi
    echo "🚀 Starting DwarfStar (DeepSeek V4 Flash) server..."
    ( cd "$DS4_DIR" && exec ./ds4-server --ctx 100000 --kv-disk-dir /tmp/ds4-kv --kv-disk-space-mb 8192 ) >"$DS4_LOG" 2>&1 &
    DS4_PID=$!
    DS4_STARTED=true
    echo "   logs: $DS4_LOG (pid $DS4_PID)"
    # Loading the GGUF can take a while; wait up to ~300s, bail early if it dies.
    for i in $(seq 1 600); do
        if ! kill -0 "$DS4_PID" 2>/dev/null; then
            echo "❌ DwarfStar server exited during startup. See $DS4_LOG"; exit 1
        fi
        if curl -s "http://127.0.0.1:${DS4_PORT}/v1/models" &>/dev/null; then
            echo "✅ DwarfStar ready"; return
        fi
        [ $((i % 60)) -eq 0 ] && echo "   ...still loading model ($((i / 2))s)"
        sleep 0.5
    done
    echo "❌ DwarfStar did not become ready in time. See $DS4_LOG"; exit 1
}

start_proxy() {
    if port_in_use "$PROXY_PORT"; then
        echo "✅ Proxy already running on :$PROXY_PORT"; return
    fi
    echo "🚀 Starting Free Claude Code proxy on :$PROXY_PORT (pinned to local Flash)..."
    ( cd "$PROJECT_DIR" \
        && LLAMACPP_BASE_URL="$DS4_BASE_URL" \
           MODEL="$MODEL_REF" MODEL_OPUS="$MODEL_REF" MODEL_SONNET="$MODEL_REF" MODEL_HAIKU="$MODEL_REF" \
        exec uv run uvicorn server:app --host 127.0.0.1 --port "$PROXY_PORT" ) >"$PROXY_LOG" 2>&1 &
    PROXY_PID=$!
    PROXY_STARTED=true
    echo "   logs: $PROXY_LOG (pid $PROXY_PID)"
    for i in $(seq 1 60); do
        if curl -s "http://127.0.0.1:${PROXY_PORT}/v1/models" &>/dev/null; then
            echo "✅ Proxy ready"; return
        fi
        sleep 0.5
    done
    echo "❌ Proxy did not become ready in time. See $PROXY_LOG"; exit 1
}

trap cleanup EXIT INT TERM HUP
start_dwarfstar
start_proxy

echo
echo "================ AionUi: Local DwarfStar Flash ================"
echo "  Base URL : http://127.0.0.1:${PROXY_PORT}"
echo "  API Key  : freecc"
echo "  Models available at this endpoint:"
curl -s "http://127.0.0.1:${PROXY_PORT}/v1/models" -H "x-api-key: freecc" \
  | python3 -c "import sys,json;[print('    -',m['id']) for m in json.load(sys.stdin).get('data',[]) if 'flash' in m['id'].lower()]" 2>/dev/null \
  || echo "    (run: curl -s http://127.0.0.1:${PROXY_PORT}/v1/models -H 'x-api-key: freecc')"
echo "==============================================================="
echo "Serving local Flash. Press Ctrl-C to stop and tear down."
wait "$PROXY_PID"
