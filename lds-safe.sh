#!/bin/bash
# Local DeepSeek (DwarfStar / DeepSeek V4 Flash) via Free Claude Code — safe mode.
# Same as lds.sh but keeps Claude Code's permission prompts on.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LDS_SAFE=true
source "$SCRIPT_DIR/lds-common.sh"
launch_lds "$@"
