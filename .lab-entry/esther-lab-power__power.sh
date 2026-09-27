#!/usr/bin/env bash
set -euo pipefail
export GH_TOKEN="${GH_TOKEN}"
ENTRY_FAILED=0
echo "== Power =="
if [ "$GITHUB_EVENT_NAME" = "schedule" ]; then export ACTION=stop; else export ACTION="$INPUT_ACTION"; fi
export GH_TOKEN="${GH_TOKEN}"
set -euo pipefail
# The nightly stop never kills a running install: skip if any SCOM phase workflow is still running.
if [ "${GITHUB_EVENT_NAME}" = schedule ]; then
  busy=$(gh run list -R ${GITHUB_REPOSITORY} -s in_progress --json workflowName -q '[.[]|select(.workflowName|startswith("esther-scom-phase"))]|length')
  if [ "$busy" != 0 ]; then echo "SCOM install running - skipping tonight's stop"; ACTION=status; fi
fi
RG=rg-learning-monitoring
have() { az vm show -g $RG -n "$1" -o none 2>/dev/null; }
# Disk tiering (user approved via WhatsApp 2026-09-24 00:32 IDT, "סבבה hdd", replying to the HDD-tiering proposal): off = deallocate -> Standard HDD, on = Premium SSD -> start.
# Azure allows only 2 type changes per disk per day; a refused change never blocks power actions.
setsku() { local d="$1-osdisk" want="$2" cur
  cur=$(az disk show -g $RG -n "$d" --query sku.name -o tsv)
  if [ "$cur" = "$want" ]; then echo "DISK_OK $d already $want"; return 0; fi
  if az disk update -g $RG -n "$d" --sku "$want" -o none 2>err.txt; then echo "DISK_CONVERTED $d $cur->$want"
  else echo "DISK_SKIPPED $d stays $cur: $(head -c 300 err.txt)"; fi; }
case "$ACTION" in
  start) for v in esther-dc-01 esther-adaxes-01; do have $v || continue
           [ "$v" = esther-linux-01 ] || setsku $v Premium_LRS; az vm start -g $RG -n $v -o none && sleep 60; done ;;
  stop)  for v in esther-linux-01 esther-adaxes-01 esther-dc-01; do have $v || continue
           az vm deallocate -g $RG -n $v -o none
           st=$(az vm get-instance-view -g $RG -n $v --query "instanceView.statuses[?starts_with(code,'PowerState')].code" -o tsv)
           if [ "$st" = PowerState/deallocated ]; then [ "$v" = esther-linux-01 ] || setsku $v Standard_LRS; else echo "DISK_SKIPPED $v not deallocated ($st)"; fi; done ;;
  linux-on) have esther-linux-01 && az vm start -g $RG -n esther-linux-01 -o none ;;
  linux-off) have esther-linux-01 && az vm deallocate -g $RG -n esther-linux-01 -o none ;;
  linux-idle) if have esther-linux-01; then
      read -r st since < <(az vm get-instance-view -g $RG -n esther-linux-01 --query "[instanceView.statuses[?starts_with(code,'PowerState')].code | [0], instanceView.statuses[?starts_with(code,'ProvisioningState')].time | [0]]" -o tsv | tr '\n' ' ') || true
      age=$(( ( $(date +%s) - $(date -d "${since:-now}" +%s) ) / 60 )); echo "linux $st for ${age}m"
      if [ "$st" = PowerState/running ] && [ "$age" -ge 55 ]; then az vm deallocate -g $RG -n esther-linux-01 -o none && echo LINUX_AUTO_STOPPED; fi; fi ;;
esac
az vm list -g $RG -d --query "[].{vm:name,size:hardwareProfile.vmSize,power:powerState}" -o table
az disk list -g $RG --query "[].{disk:name,sku:sku.name,gb:diskSizeGb,state:diskState}" -o table
