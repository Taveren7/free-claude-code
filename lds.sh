#!/bin/bash
# Local DeepSeek (DwarfStar / DeepSeek V4 Flash) via Free Claude Code — skip permissions.
# Boots the local ds4-server + a dedicated proxy, runs Claude Code, and shuts
# both down on exit (including when the terminal is closed).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LDS_SAFE=false
source "$SCRIPT_DIR/lds-common.sh"
launch_lds "$@"
