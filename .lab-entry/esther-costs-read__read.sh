#!/usr/bin/env bash
set -euo pipefail
ENTRY_FAILED=0
echo "== Read-only cost + inventory =="
bash scripts/05-read-azure-costs.sh
