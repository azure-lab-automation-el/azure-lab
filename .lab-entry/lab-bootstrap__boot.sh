#!/usr/bin/env bash
set -euo pipefail
bash rebuild/v2/bootstrap-fresh-sub.sh
if [ "${MODE:-export}" = export ]; then
  echo "== POLICY_DUMP_BEGIN =="
  for f in policy/*.json; do echo "@@FILE:$f"; cat "$f"; echo; done
  echo "== POLICY_DUMP_END =="
fi
