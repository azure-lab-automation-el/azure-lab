#!/usr/bin/env bash
# Phase 1 of the SCOM lab (approved plan 2026-09-23): tiny Windows Server 2022 Core DC on the free B2ats_v2 hours.
# No public IP. Static private IP 10.77.1.10 (10.77.1.4 is held by Esther). 64 GB Premium_LRS disk (2nd free P6). Normal Windows pricing (no Hybrid Benefit).
# Idempotent: each step skips what already exists.
set -Eeuo pipefail; set +x
step=startup; trap 'printf "ERROR step=%s line=%s\n" "$step" "${BASH_LINENO[0]:-?}" >&2' ERR
: "${AZURE_SUBSCRIPTION_ID:?}" "${ESTHER_VM_ADMIN_PASSWORD:?}" "${ESTHER_DSRM_PASSWORD:?}" "${ESTHER_SCOM_SVC_PASSWORD:?}"
RG=rg-learning-monitoring; LOC=${LAB_LOCATION:-israelcentral}; P=${LAB_PREFIX:-esther}; NET=${LAB_NET_BASE:-10.77}; SUF=${LAB_NAME_SUFFIX:-}; VM=$P-dc-01; NIC=$VM-nic$SUF; VNET=$P-lab-vnet; SUBNET=$P-lab-subnet; NSG=$P-lab-nsg
IP=$NET.1.10; SIZE=Standard_B2ats_v2; IMAGE='MicrosoftWindowsServer:WindowsServer:2022-datacenter-core-smalldisk-g2:latest'
DOMAIN=esther.lab; NETBIOS=ESTHER; ADMIN=estherlabadmin
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
rc() { az vm run-command invoke -g "$RG" -n "$VM" --command-id RunPowerShellScript "$@" -o json | jq -r '.value[]?.message' ; }

step=nic
if ! az network nic show -g "$RG" -n "$NIC" -o none 2>/dev/null; then
  az network nic create -g "$RG" -n "$NIC" -l "$LOC" --vnet-name "$VNET" --subnet "$SUBNET" --network-security-group "$NSG" --private-ip-address "$IP" --only-show-errors -o none
fi
[[ "$(az network nic show -g "$RG" -n "$NIC" --query 'ipConfigurations[0].publicIPAddress' -o tsv)" == '' ]]
[[ "$(az network nic show -g "$RG" -n "$NIC" --query 'ipConfigurations[0].privateIPAddress' -o tsv)" == "$IP" ]]

step=vm
if ! az vm show -g "$RG" -n "$VM" -o none 2>/dev/null; then
  az vm create -g "$RG" -n "$VM" -l "$LOC" --image "$IMAGE" --size "$SIZE" --computer-name ESTHERDC01 \
    --admin-username "$ADMIN" --admin-password "$ESTHER_VM_ADMIN_PASSWORD" --nics "$NIC" \
    --os-disk-name $VM-osdisk$SUF --os-disk-size-gb 64 --storage-sku Premium_LRS \
    --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true --only-show-errors -o none
fi
az vm start -g "$RG" -n "$VM" -o none
az vm show -d -g "$RG" -n "$VM" --query '{size:hardwareProfile.vmSize,license:licenseType,power:powerState,ip:privateIps,publicIp:publicIps,disk:storageProfile.osDisk.diskSizeGb}' -o json

# Nightly stop: DevTestLab auto-shutdown is not offered in israelcentral, so .github/workflows/esther-lab-power.yml stops the lab at 23:00.
step=promote
state=$(rc --scripts '(Get-CimInstance Win32_ComputerSystem).DomainRole' | tr -dc '0-9' | head -c1)
echo "domainRole=$state"
if [[ "$state" != 5 && "$state" != 4 ]]; then
  rc --scripts @scripts/scom/dc-promote.ps1 --parameters "p=$ESTHER_DSRM_PASSWORD" | tail -5
  az vm restart -g "$RG" -n "$VM" -o none
fi

step=accounts
ok=false
for i in $(seq 1 20); do
  out=$(rc --scripts @scripts/scom/dc-accounts.ps1 --parameters "p=$ESTHER_SCOM_SVC_PASSWORD" 2>&1 || true)
  if grep -q 'domain=esther.lab' <<<"$out"; then echo "$out" | grep -E '^(domain|users|SCOM-Admins)='; ok=true; break; fi
  echo "waiting for AD ($i)"; sleep 30
done
$ok

step=vnet_dns
az network vnet update -g "$RG" -n "$VNET" --dns-servers "$IP" -o none
az network vnet show -g "$RG" -n "$VNET" --query 'dhcpOptions.dnsServers' -o tsv

step=verify
rc --scripts @scripts/scom/dc-verify.ps1
az vm show -g "$RG" -n "$VM" --query licenseType -o tsv || true
echo PHASE1_OK
