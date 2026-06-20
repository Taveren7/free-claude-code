#!/bin/bash
# Kill switch for the Local DeepSeek (DwarfStar) stack — works no matter who or
# where started it. Stops the dedicated lds proxy (port 8083) and the ds4-server
# process (matched by name, NOT by port: Docker also squats on port 8000).
#
# Usage: lds-stop
PROXY_PORT=8083
SERVER_PATTERN="ds4-server"

# --- DwarfStar server: match by name so we never touch Docker on :8000 ---------
server_pids="$(pgrep -f "$SERVER_PATTERN")"
if [ -z "$server_pids" ]; then
    echo "ℹ️  DwarfStar (ds4-server) not running"
else
    echo "🛑 Stopping DwarfStar (ds4-server) pid: $server_pids"
    # shellcheck disable=SC2086
    kill -TERM $server_pids 2>/dev/null
    # Give it a moment to flush KV state, then force-kill any stragglers.
    for _ in 1 2 3 4 5 6; do
        pgrep -f "$SERVER_PATTERN" >/dev/null || break
        sleep 0.5
    done
    if pgrep -f "$SERVER_PATTERN" >/dev/null; then
        echo "   still alive — sending SIGKILL"
        pkill -KILL -f "$SERVER_PATTERN" 2>/dev/null
    fi
    echo "✅ DwarfStar stopped"
fi

# --- lds proxy: port 8083 is uniquely ours, so port-match is safe here ---------
proxy_pids="$(lsof -ti ":$PROXY_PORT" -sTCP:LISTEN 2>/dev/null)"
if [ -z "$proxy_pids" ]; then
    echo "ℹ️  lds proxy not running on :$PROXY_PORT"
else
    echo "🛑 Stopping lds proxy on :$PROXY_PORT pid: $proxy_pids"
    # shellcheck disable=SC2086
    kill $proxy_pids 2>/dev/null
    echo "✅ Proxy stopped"
fi
