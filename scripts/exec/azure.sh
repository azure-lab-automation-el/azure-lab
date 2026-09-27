#!/usr/bin/env bash
# Azure adapter: az vm run-command (the transport the live engine uses today).
set -euo pipefail
ROLE=$1; SCRIPT=$2; shift 2
RG=${RG:-rg-learning-monitoring}
case $ROLE in
  dc)     VM=esther-dc-01;;
  esther) VM=esther-adaxes-01;;
  linux)  VM=esther-linux-01;;
  *) echo "unknown role: $ROLE" >&2; exit 64;;
esac
if [[ $SCRIPT == *.ps1 ]]; then CMD=RunPowerShellScript; else CMD=RunShellScript; fi
PARAMS=(); for kv in "$@"; do PARAMS+=(--parameters "$kv"); done
if [ "${PRINT:-0}" = 1 ]; then
  echo "az vm run-command invoke -g $RG -n $VM --command-id $CMD --scripts @$SCRIPT ${PARAMS[*]:-}"
  exit 0
fi
az vm run-command invoke -g "$RG" -n "$VM" --command-id "$CMD" --scripts @"$SCRIPT" "${PARAMS[@]}" \
  -o json | jq -r '.value[]?.message'
