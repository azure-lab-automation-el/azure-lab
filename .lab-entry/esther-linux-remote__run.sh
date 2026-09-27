#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
ENTRY_FAILED=0
echo "== Quota request (Israel Central cores 4 -> 6) =="
if [ "${INPUT_MODE}" != "create" ]; then
{
set -uo pipefail; SUB=${AZURE_SUBSCRIPTION_ID}; S=/subscriptions/$SUB/providers/Microsoft.Compute/locations/israelcentral
az vm list-usage -l israelcentral --query "[?contains(name.value,'ores') || contains(name.value,'Basv2')].{n:name.value,cur:currentValue,lim:limit}" -o table
az provider register -n Microsoft.Quota --wait -o none 2>&1 | tail -2
az extension add -n quota -y --only-show-errors
for r in cores standardBasv2Family; do
  cur=$(az quota show --resource-name $r --scope $S --query properties.limit.value -o tsv 2>&1); echo "quota $r now=$cur"
done
fam=$(az quota show --resource-name standardBasv2Family --scope $S --query properties.limit.value -o tsv 2>/dev/null || echo 0)
echo "== request cores=6"; az quota update --resource-name cores --scope $S --limit-object value=6 --resource-type dedicated -o json 2>&1 | grep -iE '"(value|provisioningState|message|code)"|error' | head -10
if [ "${fam:-0}" -lt 6 ] 2>/dev/null; then echo "== request standardBasv2Family=6"; az quota update --resource-name standardBasv2Family --scope $S --limit-object value=6 --resource-type dedicated -o json 2>&1 | grep -iE '"(value|provisioningState|message|code)"|error' | head -10; fi
az quota request list --scope $S --query "[].{n:name,state:properties.provisioningState,msg:properties.message}" -o table 2>&1 | head -10
echo QUOTA_STEP_DONE
} || true
fi
echo "== Create Linux VM in another region =="
if [ "${INPUT_MODE}" != "quota" ]; then
set -euo pipefail
RG=rg-learning-monitoring; VM=esther-linux-01
echo "== location policies"; az policy assignment list -g $RG --query "[].{n:name,def:policyDefinitionId}" -o table || true
if az vm show -g $RG -n $VM -o none 2>/dev/null; then echo "vm exists: $(az vm show -g $RG -n $VM --query location -o tsv)"; exit 0; fi
LOC=""
for c in italynorth polandcentral swedencentral westeurope northeurope germanywestcentral; do
  r=$(az vm list-skus -l $c --size Standard_B2ats_v2 --query "[?name=='Standard_B2ats_v2'] | length(@)" -o tsv); rs=$(az vm list-skus -l $c --size Standard_B2ats_v2 --query "[?name=='Standard_B2ats_v2'].restrictions[].reasonCode" -o tsv)
  u=$(az vm list-usage -l $c --query "[?name.value=='cores'].[currentValue,limit]" -o tsv | tr '\t' ' ')
  img=$(az vm image list --location $c --publisher Canonical --offer ubuntu-24_04-lts --sku server --all --query "length(@)" -o tsv 2>/dev/null || echo 0)
  echo "cand $c sku=$r restr=[$rs] cores=[$u] img=$img"
  set -- $u; if [ "$r" = 1 ] && [ -z "$rs" ] && [ $(( $2 - $1 )) -ge 2 ] && [ "${img:-0}" -gt 0 ]; then LOC=$c; break; fi
done
[ -n "$LOC" ] || { echo "NO_REGION"; exit 1; }; echo "REGION=$LOC"
VNET=esther-linux-vnet; SUBN=linux-subnet; NSG=esther-linux-nsg
az network nsg create -g $RG -n $NSG -l $LOC -o none
az network nsg rule create -g $RG --nsg-name $NSG -n allow-lab-ssh-wsman --priority 100 --direction Inbound --access Allow --protocol Tcp --source-address-prefixes 10.77.0.0/16 --destination-port-ranges 22 1270 -o none
az network nsg rule create -g $RG --nsg-name $NSG -n deny-internet-in --priority 4000 --direction Inbound --access Deny --protocol '*' --source-address-prefixes Internet --destination-port-ranges '*' -o none
az network vnet create -g $RG -n $VNET -l $LOC --address-prefixes 10.78.0.0/24 --subnet-name $SUBN --subnet-prefixes 10.78.0.0/27 -o none
az network vnet subnet update -g $RG --vnet-name $VNET -n $SUBN --network-security-group $NSG --default-outbound-access false -o none
LAB=$(az network vnet show -g $RG -n esther-lab-vnet --query id -o tsv); LX=$(az network vnet show -g $RG -n $VNET --query id -o tsv)
az network vnet peering create -g $RG -n lab-to-linux --vnet-name esther-lab-vnet --remote-vnet $LX --allow-vnet-access -o none
az network vnet peering create -g $RG -n linux-to-lab --vnet-name $VNET --remote-vnet $LAB --allow-vnet-access -o none
# The stale Israel Central NIC (never attached, $0) is removed so the name is free.
az network nic delete -g $RG -n $VM-nic -o none 2>/dev/null || true
az network nic create -g $RG -n $VM-nic -l $LOC --vnet-name $VNET --subnet $SUBN --private-ip-address 10.78.0.10 -o none
[ -z "$(az network nic show -g $RG -n $VM-nic --query 'ipConfigurations[0].publicIPAddress' -o tsv)" ]
az vm create -g $RG -n $VM -l $LOC --image Canonical:ubuntu-24_04-lts:server:latest --size Standard_B2ats_v2 \
  --admin-username scomlab --ssh-key-values "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJOWebEQVYCGnjP+9YUfVvqteUy8OiADXZ+KfYdhiBQX scom-linux-lab" --authentication-type ssh \
  --nics $VM-nic --os-disk-name $VM-osdisk --os-disk-size-gb 64 --storage-sku Premium_LRS \
  --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true --only-show-errors -o none
az vm show -d -g $RG -n $VM --query "{loc:location,size:hardwareProfile.vmSize,power:powerState,priv:privateIps,pub:publicIps,img:storageProfile.imageReference.offer}" -o json
az disk show -g $RG -n $VM-osdisk --query "{gb:diskSizeGb,sku:sku.name,tier:tier}" -o json
az network vnet peering list -g $RG --vnet-name esther-lab-vnet --query "[].{n:name,state:peeringState}" -o table
az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts "hostnamectl | head -3; ip -4 addr show eth0 | grep inet; systemctl is-active ssh; timeout 3 bash -c '</dev/tcp/10.77.1.4/5723' && echo scom-port-reachable" --query "value[0].message" -o tsv
echo LINUX_VM_OK
fi
