#!/bin/bash
# Start the Free Claude Code proxy server
cd "$(dirname "$0")"
echo "🚀 Starting Free Claude Code proxy on port 8082..."
uv run uvicorn server:app --host 0.0.0.0 --port 8082
