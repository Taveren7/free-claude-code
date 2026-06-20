#!/bin/bash
# Run Claude Code through the Free Claude Code proxy (normal mode)
ANTHROPIC_AUTH_TOKEN="freecc" ANTHROPIC_BASE_URL="http://localhost:8082" claude "$@"
