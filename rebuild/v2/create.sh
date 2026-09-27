#!/usr/bin/env bash
# mivtza-eser create: network + DC + SCOM/SQL VM in parallel, CustomData bootstrap, build SKU, dry-run mode.
# DRYRUN=true (default): read-only validation (image, SKU, quota, plan). DRYRUN=false: creates.
set -Eeuo pipefail; set +x
: "${AZURE_SUBSCRIPTION_ID:?}"
DRYRUN=${DRYRUN:-true}; BUILD_SKU=${BUILD_SKU:-Standard_B2as_v2}
RG=rg-learning-monitoring; LOC=${LAB_LOCATION:-israelcentral}; P=${LAB_PREFIX:-esther}; NET=${LAB_NET_BASE:-10.77}; SUF=${LAB_NAME_SUFFIX:-}
DC=$P-dc-01; VM=$P-adaxes-01; VNET=$P-lab-vnet; SUBNET=$P-lab-subnet; NSG=$P-lab-nsg
DC_IP=$NET.1.10; VM_IP=$NET.1.4; ADMIN=estherlabadmin
DC_IMAGE='MicrosoftWindowsServer:WindowsServer:2022-datacenter-core-smalldisk-g2:latest'
SQL_IMAGE='MicrosoftSQLServer:sql2022-ws2022:sqldev-gen2:latest'
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
echo "== validations (always, read-only) =="
az vm image show -l "$LOC" --urn "$SQL_IMAGE" -o none && echo "sql image OK: $SQL_IMAGE ($(az vm image show -l "$LOC" --urn "$SQL_IMAGE" --query 'name' -o tsv))" || { echo "FAIL: $SQL_IMAGE not available in $LOC"; exit 1; }
az vm image list-skus -l "$LOC" -p MicrosoftSQLServer --offer sql2022-ws2022 --query "[].name" -o tsv | grep -qx 'sqldev-gen2' && echo "sku sqldev-gen2 confirmed in $LOC" || { echo "FAIL: sqldev-gen2 sku missing in $LOC"; exit 1; }
az vm image show -l "$LOC" --urn "$DC_IMAGE" -o none && echo "dc image OK"
for s in "$BUILD_SKU" Standard_B2ats_v2; do
  az vm list-skus -l "$LOC" --size "$s" --query "[].restrictions" -o json | grep -q '\[\]' && echo "sku $s OK" || { echo "FAIL: sku $s restricted in $LOC"; exit 1; }
done
q=$(az vm list-usage -l "$LOC" --query "[?name.value=='cores'].{used:currentValue,limit:limit}" -o json)
free=$(( $(jq -r '.[0].limit' <<<"$q") - $(jq -r '.[0].used' <<<"$q") ))
echo "regional cores free: $free (need 4 for 2x $BUILD_SKU)"
if [ "$free" -lt 4 ]; then
  echo "cores held by:"; az vm list -g $RG --query '[].name' -o tsv | sed 's/^/  /'
  if [ "$DRYRUN" = false ]; then echo "FAIL: not enough regional cores (run teardown first)"; exit 1;
  else echo "WARN: 0 free now = the existing lab the teardown removes; gate rechecked at real build"; fi
fi
echo "== plan =="
echo "network: $VNET $NET.0.0/16 + $SUBNET $NET.1.0/24, DNS=$DC_IP, NSG $NSG (no inbound)"
echo "dc:      $DC $BUILD_SKU, $(cut -d: -f2- <<<"$DC_IMAGE"), static $DC_IP, customdata=promote+accounts+djoin"
echo "vm:      $VM $BUILD_SKU, $(cut -d: -f2- <<<"$SQL_IMAGE"), static $VM_IP, customdata=prereq+media+join+scom"
[ "$DRYRUN" = false ] || { echo "DRYRUN_OK (nothing created)"; exit 0; }
: "${ESTHER_VM_ADMIN_PASSWORD:?required when DRYRUN=false}"
echo "== network =="
az network vnet show -g $RG -n $VNET -o none 2>/dev/null || { az network vnet create -g $RG -n $VNET -l $LOC --address-prefixes $NET.0.0/16 --subnet-name $SUBNET --subnet-prefixes $NET.1.0/24 -o none; az network vnet subnet update -g $RG --vnet-name $VNET -n $SUBNET --default-outbound-access false -o none; }
az network nsg show -g $RG -n $NSG -o none 2>/dev/null || az network nsg create -g $RG -n $NSG -l $LOC -o none
az network vnet update -g $RG -n $VNET --dns-servers "$DC_IP" -o none
echo "== NICs =="
az network nic show -g $RG -n $DC-nic$SUF -o none 2>/dev/null || az network nic create -g $RG -n $DC-nic$SUF -l $LOC --vnet-name $VNET --subnet $SUBNET --network-security-group $NSG --private-ip-address $DC_IP -o none
az network nic show -g $RG -n $VM-nic$SUF -o none 2>/dev/null || az network nic create -g $RG -n $VM-nic$SUF -l $LOC --vnet-name $VNET --subnet $SUBNET --network-security-group $NSG --private-ip-address $VM_IP -o none
# NICs may be parked backups on temp IPs - enforce the static lab IPs
for pair in "$DC-nic$SUF:$DC_IP" "$VM-nic$SUF:$VM_IP"; do n=${pair%%:*}; ip=${pair##*:}
  # free the lab IP from any backup NIC holding it (m2 migration NICs) - park intact on a temp IP
  for h in $(az network nic list -g $RG --query "[?ipConfigurations[0].privateIPAddress=='$ip' && name!='$n'].name" -o tsv); do
    for t in 250 249 248 247 246; do
      if [ -z "$(az network nic list -g $RG --query "[?ipConfigurations[0].privateIPAddress=='$NET.1.$t'].name" -o tsv)" ]; then
        az network nic ip-config update -g $RG --nic-name "$h" -n ipconfig1 --private-ip-address "$NET.1.$t" -o none
        echo "backup nic $h parked $ip -> $NET.1.$t (intact, reversible)"; break
      fi
    done
  done
  cur=$(az network nic show -g $RG -n "$n" --query 'ipConfigurations[0].privateIPAddress' -o tsv 2>/dev/null || true)
  if [ "$cur" != "$ip" ]; then az network nic ip-config update -g $RG --nic-name "$n" -n ipconfig1 --private-ip-address "$ip" -o none; echo "nic $n ip $cur -> $ip"; fi
done
echo "== VMs in parallel (customdata bootstrap) =="
umask 077; pf=$(mktemp); printf '%s' "$ESTHER_VM_ADMIN_PASSWORD" > "$pf"
# half-created shell from a failed deployment (no osDisk) is not a VM and not a backup - delete and recreate
for v in "$DC" "$VM"; do
  if az vm show -g $RG -n "$v" -o none 2>/dev/null; then
    ps=$(az vm show -g $RG -n "$v" --query '{prov:provisioningState,disk:storageProfile.osDisk.managedDisk.id}' -o json)
    if [ "$(jq -r .disk <<<"$ps")" = null ]; then
      echo "$v: failed shell without disk (provisioning=$(jq -r .prov <<<"$ps")) - deleting shell"
      az vm delete -g $RG -n "$v" --yes --force-deletion true --only-show-errors -o none
    fi
  fi
done
# new OS disks get a suffix so they NEVER collide with kept backup disks (boundary: backups intact until green)
DSUF=${LAB_NAME_SUFFIX:-r1}
( az vm show -g $RG -n $DC -o none 2>/dev/null || az vm create -g $RG -n $DC -l $LOC --image "$DC_IMAGE" --size "$BUILD_SKU" --computer-name ESTHERDC01 \
    --admin-username $ADMIN --admin-password @"$pf" --nics $DC-nic$SUF --os-disk-name $DC-osdisk$DSUF --os-disk-size-gb 64 --storage-sku Premium_LRS \
    --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true --custom-data rebuild/v2/dc-customdata.ps1 --only-show-errors -o none ) &
P1=$!
( az vm show -g $RG -n $VM -o none 2>/dev/null || az vm create -g $RG -n $VM -l $LOC --image "$SQL_IMAGE" --size "$BUILD_SKU" --computer-name ESTHERLAB \
    --admin-username $ADMIN --admin-password @"$pf" --nics $VM-nic$SUF --os-disk-name $VM-osdisk$DSUF --storage-sku Premium_LRS \
    --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true --custom-data rebuild/v2/vm-customdata.ps1 --only-show-errors -o none ) &
P2=$!
rc=0; wait $P1 || rc=1; wait $P2 || rc=1; rm -f "$pf"
if [ $rc -ne 0 ]; then echo "FAIL: one or both VM creates failed"; exit 1; fi
# success must be PROVEN by live existence, never by exit-code assumptions
az vm show -g $RG -n $DC -o none && az vm show -g $RG -n $VM -o none || { echo "FAIL: VM missing after create"; exit 1; }
az vm list -g $RG -d --query "[?starts_with(name,'$P-')].{vm:name,size:hardwareProfile.vmSize,power:powerState}" -o table
echo CREATE_V2_OK
