#!/bin/bash
# DeepSeek via Free Claude Code — single command launcher (safe mode)
# Works from ANY directory.
PROJECT_DIR="/Users/tec/Code/Projects/free-claude-code"
PORT=8082
ORIGINAL_DIR="$(pwd)"

# Check if proxy is already running
if lsof -i :$PORT -sTCP:LISTEN &>/dev/null; then
    PROXY_ALREADY_RUNNING=true
else
    PROXY_ALREADY_RUNNING=false
    echo "🚀 Starting proxy server..."
    (cd "$PROJECT_DIR" && uv run uvicorn server:app --host 0.0.0.0 --port $PORT &>/dev/null) &
    PROXY_PID=$!

    # Wait for it to be ready (up to 15 seconds)
    for i in {1..30}; do
        if curl -s http://localhost:$PORT/v1/models &>/dev/null; then
            echo "✅ Proxy ready"
            break
        fi
        sleep 0.5
    done
fi

# Run Claude Code from wherever the user called this
cd "$ORIGINAL_DIR"
ANTHROPIC_AUTH_TOKEN="freecc" ANTHROPIC_BASE_URL="http://localhost:$PORT" claude "$@"

# Clean up proxy if we started it
if [ "$PROXY_ALREADY_RUNNING" = false ] && [ -n "$PROXY_PID" ]; then
    kill $PROXY_PID 2>/dev/null
    echo "🛑 Proxy stopped"
fi
