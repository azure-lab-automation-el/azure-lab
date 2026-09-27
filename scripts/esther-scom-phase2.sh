#!/usr/bin/env bash
# Phase 2 of the SCOM lab: Esther -> normal Windows pricing (no Hybrid Benefit, user chose "רגיל"), resize to B2as_v2 (2 vCPU, 8 GB; Free Trial caps the region at 4 vCPUs), join esther.lab.
set -Eeuo pipefail; set +x
step=startup; trap 'printf "ERROR step=%s line=%s\n" "$step" "${BASH_LINENO[0]:-?}" >&2' ERR
: "${AZURE_SUBSCRIPTION_ID:?}" "${ESTHER_VM_ADMIN_PASSWORD:?}"
RG=rg-learning-monitoring; LOC=${LAB_LOCATION:-israelcentral}; P=${LAB_PREFIX:-esther}; NET=${LAB_NET_BASE:-10.77}; VM=$P-adaxes-01; DC=$P-dc-01; SIZE=Standard_B2as_v2
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
rc() { az vm run-command invoke -g "$RG" -n "$1" --command-id RunPowerShellScript "${@:2}" -o json | jq -r '.value[]?.message'; }
step=dc_running
az vm start -g "$RG" -n "$DC" -o none
[[ "$(az network vnet show -g "$RG" -n $P-lab-vnet --query 'dhcpOptions.dnsServers[0]' -o tsv)" == $NET.1.10 ]]
step=resize
cur=$(az vm show -g "$RG" -n "$VM" --query '[hardwareProfile.vmSize, licenseType]' -o tsv | tr '\t' ' ')
echo "before: $cur"
if [[ "$cur" != "$SIZE None" && "$cur" != "$SIZE " ]]; then
  az vm deallocate -g "$RG" -n "$VM" -o none
  az vm update -g "$RG" -n "$VM" --license-type None --set hardwareProfile.vmSize="$SIZE" -o none
fi
az vm show -g "$RG" -n "$VM" --query '{size:hardwareProfile.vmSize, license:licenseType}' -o json
# Nightly stop: DevTestLab auto-shutdown is not offered in israelcentral, so .github/workflows/esther-lab-power.yml stops the lab at 23:00.
step=start
az vm start -g "$RG" -n "$VM" -o none
step=join
out=
for a in 1 2 3 4 5 6; do
  out=$(rc "$VM" --scripts @scripts/scom/esther-join.ps1 --parameters "p=$ESTHER_VM_ADMIN_PASSWORD" 2>&1) && break
  echo "join invoke retry $a (VM busy: media preload or resize in flight)"; sleep 30
done
echo "$out" | grep -v '^$' | head -8
if grep -q '^STOP' <<<"$out"; then exit 3; fi
if grep -q 'joined-pending-reboot' <<<"$out"; then az vm restart -g "$RG" -n "$VM" -o none; fi
step=verify
for i in 1 2 3 4 5 6; do v=$(rc "$VM" --scripts @scripts/scom/esther-verify.ps1 2>&1 || true); grep -q 'domain=esther.lab' <<<"$v" && break; sleep 20; done
echo "$v" | grep -v '^$'
grep -q 'secureChannel=True' <<<"$v"
echo PHASE2_OK
