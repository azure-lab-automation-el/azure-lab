#!/usr/bin/env bash
# SCOM server VM (esther-adaxes-01 / ESTHERLAB) - idempotent rebuild step 1 of the SCOM chain.
# MODE=plan (default): read-only. Shows what exists, what would be created, and how the live VM compares to this spec.
# MODE=apply: creates only what is missing (VNet/subnet, NSG, NIC with static 10.77.1.4, VM). Never deletes or changes existing resources.
# Spec = the live VM after phase 2: Windows Server 2022 Azure Edition (smalldisk image) on a 64 GB Premium_LRS OS disk, Standard_B2as_v2,
# Trusted Launch, no Hybrid Benefit, no public IP, NSG with no inbound rules. The VM is deallocated after create (costs start only when phase 2 starts it).
# v1 (retired) created the VM but failed its readback: az vm show reports osDisk.diskSizeGb as null, so disk size is now read from the disk.
set -Euo pipefail
: "${AZURE_SUBSCRIPTION_ID:?required}"; MODE=${MODE:-plan}
RG=rg-learning-monitoring; LOC=${LAB_LOCATION:-israelcentral}; P=${LAB_PREFIX:-esther}; NET=${LAB_NET_BASE:-10.77}; VM=$P-adaxes-01; VNET=$P-lab-vnet; SUBNET=$P-lab-subnet
NSG=$P-lab-nsg; SUF=${LAB_NAME_SUFFIX:-}; NIC=$VM-nic$SUF; IP=$NET.1.4; ADMIN=estherlabadmin; DISK=$VM-osdisk$SUF
IMAGE='MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition-smalldisk:latest'; SIZE=Standard_B2as_v2
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
exists() { case "$1" in
  */virtualNetworks) az network vnet show -g $RG -n "$2" --query id -o tsv >/dev/null 2>&1;;
  */networkSecurityGroups) az network nsg show -g $RG -n "$2" --query id -o tsv >/dev/null 2>&1;;
  */networkInterfaces) az network nic show -g $RG -n "$2" --query id -o tsv >/dev/null 2>&1;;
  */virtualMachines) az vm show -g $RG -n "$2" --query id -o tsv >/dev/null 2>&1;; esac; }
todo=0; say() { printf '%-8s %s\n' "$1" "$2"; }
exists Microsoft.Network/virtualNetworks $VNET && say exists "vnet $VNET" || { say create "vnet $VNET $NET.0.0/16 + $SUBNET $NET.1.0/24 (defaultOutboundAccess=false)"; todo=1; }
exists Microsoft.Network/networkSecurityGroups $NSG && say exists "nsg $NSG" || { say create "nsg $NSG (no inbound rules)"; todo=1; }
exists Microsoft.Network/networkInterfaces $NIC && say exists "nic $NIC" || { say create "nic $NIC static $IP, no public IP"; todo=1; }
exists Microsoft.Compute/virtualMachines $VM && say exists "vm $VM" || { say create "vm $VM $SIZE, $IMAGE, 64 GB Premium_LRS, Trusted Launch, then deallocate"; todo=1; }
if exists Microsoft.Compute/virtualMachines $VM; then
  echo "== live vs spec"; az network vnet list -g $RG --query "[].{vnet:name,subnets:subnets[].name}" -o json; az network nsg list -g $RG --query "[].name" -o tsv
  az vm show -g $RG -n $VM --query "{size:hardwareProfile.vmSize,license:licenseType,sku:storageProfile.imageReference.sku,disk:storageProfile.osDisk.name,sec:securityProfile.securityType,nic:networkProfile.networkInterfaces[0].id}" -o json
  d=$(az vm show -g $RG -n $VM --query storageProfile.osDisk.managedDisk.id -o tsv); az disk show --ids "$d" --query "{diskGb:diskSizeGB,sku:sku.name}" -o json
  exists Microsoft.Network/networkInterfaces $NIC && az network nic show -g $RG -n $NIC --query "{ip:ipConfigurations[0].privateIPAddress,alloc:ipConfigurations[0].privateIPAllocationMethod,pub:ipConfigurations[0].publicIPAddress.id,nsg:networkSecurityGroup.id,subnet:ipConfigurations[0].subnet.id}" -o json
fi
echo "PLAN todo=$todo mode=$MODE"
[ "$MODE" = apply ] || [ "$MODE" = network ] || [ "$MODE" = vm ] || exit 0
[ "$todo" = 1 ] || { echo "nothing to create"; exit 0; }
: "${ESTHER_VM_ADMIN_PASSWORD:?required for apply}"
set -e
if [ "$MODE" != vm ]; then
exists Microsoft.Network/virtualNetworks $VNET || { az network vnet create -g $RG -n $VNET -l $LOC --address-prefixes $NET.0.0/16 --subnet-name $SUBNET --subnet-prefixes $NET.1.0/24 -o none; az network vnet subnet update -g $RG --vnet-name $VNET -n $SUBNET --default-outbound-access false -o none; }
exists Microsoft.Network/networkSecurityGroups $NSG || az network nsg create -g $RG -n $NSG -l $LOC -o none
fi
[ "$MODE" = network ] && { echo NETWORK_ONLY_DONE; exit 0; }
exists Microsoft.Network/networkInterfaces $NIC || az network nic create -g $RG -n $NIC -l $LOC --vnet-name $VNET --subnet $SUBNET --network-security-group $NSG --private-ip-address $IP -o none
if ! exists Microsoft.Compute/virtualMachines $VM; then
  # Password via a 0600 parameters file, not on the command line.
  umask 077; pf=$(mktemp); printf '%s' "$ESTHER_VM_ADMIN_PASSWORD" > "$pf"
  az vm create -g $RG -n $VM -l $LOC --image "$IMAGE" --size $SIZE --computer-name ESTHERLAB --admin-username $ADMIN --admin-password @"$pf" \
    --nics $NIC --os-disk-name $DISK --os-disk-size-gb 64 --storage-sku Premium_LRS --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true \
    --license-type None -o none; rm -f "$pf"
  az vm deallocate -g $RG -n $VM -o none
fi
d=$(az vm show -g $RG -n $VM --query storageProfile.osDisk.managedDisk.id -o tsv)
[ "$(az disk show --ids "$d" --query diskSizeGB -o tsv)" -ge 64 ] && [ -z "$(az network nic show -g $RG -n $NIC --query ipConfigurations[0].publicIPAddress.id -o tsv)" ] && echo VM_CREATE_VERIFIED
