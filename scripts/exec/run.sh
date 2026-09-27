#!/usr/bin/env bash
# exec/run.sh - run one post-config script on a lab VM on any cloud.
# Usage: run.sh [--print] <azure|aws|gcp> <dc|esther|linux> <script.ps1|script.sh> [k=v ...]
# The same scripts/scom/*.ps1 and bash installers run everywhere; only the transport differs.
# --print shows the exact command without executing (validation mode, no cloud calls).
set -euo pipefail
PRINT=0; [ "${1:-}" = "--print" ] && { PRINT=1; shift; }
[ $# -ge 3 ] || { echo "usage: run.sh [--print] <azure|aws|gcp> <dc|esther|linux> <script> [k=v ...]" >&2; exit 64; }
CLOUD=$1; ROLE=$2; SCRIPT=$3; shift 3
ADAPTER="$(dirname "$0")/$CLOUD.sh"
[ -f "$ADAPTER" ] || { echo "unknown cloud: $CLOUD" >&2; exit 64; }
[ -f "$SCRIPT" ] || { echo "script not found: $SCRIPT" >&2; exit 66; }
if [ "$PRINT" = 1 ]; then PRINT=1 bash "$ADAPTER" "$ROLE" "$SCRIPT" "$@"; else bash "$ADAPTER" "$ROLE" "$SCRIPT" "$@"; fi
