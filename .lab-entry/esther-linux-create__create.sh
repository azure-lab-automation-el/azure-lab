#!/usr/bin/env bash
set -euo pipefail
export INPUT_SIZE="${INPUT_SIZE}"
ENTRY_FAILED=0
echo "== Create =="
set -euo pipefail
RG=rg-learning-monitoring; LOC=${LAB_LOCATION:-israelcentral}; VM=esther-linux-01
if az vm show -g $RG -n $VM -o none 2>/dev/null; then echo "exists"; else
SUB=$(az network vnet subnet show -g $RG --vnet-name esther-lab-vnet -n esther-lab-subnet --query id -o tsv)
az network nic show -g $RG -n $VM-nic -o none 2>/dev/null || az network nic create -g $RG -n $VM-nic -l $LOC --subnet "$SUB" --network-security-group esther-lab-nsg --private-ip-address 10.77.1.20 --only-show-errors -o none
[ -z "$(az network nic show -g $RG -n $VM-nic --query 'ipConfigurations[0].publicIPAddress' -o tsv)" ]
az vm image show --urn Canonical:ubuntu-24_04-lts:server:latest --query "{gen:hyperVGeneration,arch:architecture,features:features}" -o json || true
az vm list-skus -l $LOC --size ${INPUT_SIZE} --query "[].{name:name,restr:restrictions}" -o json || true
az vm create -g $RG -n $VM -l $LOC --image Canonical:ubuntu-24_04-lts:server:latest --size ${INPUT_SIZE} \
  --admin-username scomlab --ssh-key-values "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJOWebEQVYCGnjP+9YUfVvqteUy8OiADXZ+KfYdhiBQX scom-linux-lab" --authentication-type ssh \
  --nics $VM-nic \
  --os-disk-name $VM-osdisk --os-disk-size-gb 64 --storage-sku Premium_LRS \
  --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true --only-show-errors -o none --debug 2>/tmp/vmdebug.txt || { echo VM_CREATE_FAILED; set +e +o pipefail; grep -iE 'preflight|quota|OperationNotAllowed|"code"|"message"|Response status' /tmp/vmdebug.txt | grep -viE 'authorization|token|x-ms-client' | cut -c1-700 | tail -25; az vm list-usage -l $LOC --query "[?contains(name.value,'ores')].{n:name.value,cur:currentValue,lim:limit}" -o table; az monitor activity-log list -g $RG --offset 10m --query "[?status.value=='Failed'].{op:operationName.value,msg:properties.statusMessage}" -o json | head -c 3000; exit 1; }; fi
az vm show -d -g $RG -n $VM --query "{size:hardwareProfile.vmSize,power:powerState,priv:privateIps,pub:publicIps,img:storageProfile.imageReference.offer}" -o json
az disk show -g $RG -n $VM-osdisk --query "{gb:diskSizeGb,sku:sku.name,tier:tier}" -o json
az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts "hostnamectl; ip -4 addr show eth0 | grep inet; systemctl is-active ssh" --query "value[0].message" -o tsv
echo LINUX_VM_OK
