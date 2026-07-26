#!/bin/bash
# Persistent DeepSeek/GLM (Free Claude Code) proxy on :8082 for AionUi.
# Launched by launchd (com.freeclaudecode.proxy). Serves DeepSeek + GLM + any
# cloud model your .env keys unlock, via model/token routing; API key = freecc.
cd /Users/tec/Code/Projects/free-claude-code || exit 1
exec /opt/homebrew/bin/uv run uvicorn server:app --host 127.0.0.1 --port 8082
