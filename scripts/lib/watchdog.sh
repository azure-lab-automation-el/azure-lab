#!/usr/bin/env bash
# Pre-timeout watchdog. Usage (first line of a step's run block):  source scripts/lib/watchdog.sh <step-limit-minutes> <label>
# At 80% of the limit it captures diagnostics to diag/ (uploaded by an `if: failure() || cancelled()` step) and prints a summary
# into the live log. The step's own `timeout-minutes` does the kill afterwards, so capture always happens before the kill.
WD_LIMIT=${1:?limit minutes}; WD_LABEL=${2:-step}; mkdir -p diag
(
  sleep $(( WD_LIMIT * 60 * 8 / 10 ))
  f="diag/watchdog-${WD_LABEL}.txt"
  {
    echo "== watchdog $WD_LABEL fired at 80% of ${WD_LIMIT}m: $(date -u +%FT%TZ)"
    echo "== process tree"; ps -eo pid,ppid,stat,etime,args --forest | grep -v ' ps -eo' | head -80
    echo "== processes waiting on a terminal/stdin (possible prompts)"; ps -eo pid,stat,tty,args | awk '$3!="?"' | head -20
    echo "== tcp connections"; ss -tnp 2>/dev/null | head -30
    if command -v az >/dev/null && az account show -o none 2>/dev/null; then
      for vm in $(az vm list -g "${RG:-rg-learning-monitoring}" --query "[].name" -o tsv 2>/dev/null); do
        echo "== $vm power + run-command extension"
        az vm get-instance-view -g "${RG:-rg-learning-monitoring}" -n "$vm" --query "{power:instanceView.statuses[?starts_with(code,'PowerState')].code|[0],runCommand:instanceView.extensions[?contains(name,'RunCommand')].{n:name,s:statuses[0].displayStatus,msg:statuses[0].message}}" -o json 2>&1 | head -c 1500; echo
      done
    fi
    echo "== recent files touched"; find . /tmp -maxdepth 3 -type f -newermt "-5 minutes" 2>/dev/null | grep -v '/proc/' | head -30
  } > "$f" 2>&1
  echo "::warning::watchdog $WD_LABEL: 80% of ${WD_LIMIT}m reached - diagnostics captured in $f"
  sed 's/^/[watchdog] /' "$f" | head -120
) &
disown 2>/dev/null || true
