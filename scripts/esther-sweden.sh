#!/usr/bin/env bash
# User approved 2026-09-24 16:25 (WhatsApp, reply to the Sweden cost question): Linux lab VM in Sweden Central,
# B2ats_v2 (free Linux hours), Standard 32GB disk (~$1.5/mo from free credit), no public IP, peering to esther-lab-vnet.
set -Eeuo pipefail
: "${AZURE_SUBSCRIPTION_ID:?}"; : "${STAGE:?}"
RG=rg-learning-monitoring; LOC=${LAB_LOCATION_LINUX:-swedencentral}; P=${LAB_PREFIX:-esther}; SENET=${LAB_SE_NET_BASE:-10.78}; VM=$P-linux-01; VNET=$P-se-vnet; HUB=$P-lab-vnet; SESUB=$P-se-subnet; SENSG=$P-se-nsg
SCOPE="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${RG}"; API=2025-03-01
pa() { echo "https://management.azure.com${SCOPE}/providers/Microsoft.Authorization/policyAssignments/$1?api-version=${API}"; }
addvals() { # name key json-array-of-values
  local n="$1" k="$2" vals="$3" f; f=$(mktemp)
  az rest --only-show-errors --method get --url "$(pa $n)" > "$f.before"
  echo "BEFORE $n: $(jq -c ".properties.parameters.$k.value" "$f.before")"
  VALS="$vals" python3 - "$f.before" "$f.put" "$k" <<'PY'
import json, sys
src, dst, k = sys.argv[1], sys.argv[2], sys.argv[3]
add = json.loads(__import__('os').environ['VALS'])
doc = json.load(open(src))
cur = doc['properties']['parameters'][k]['value']
doc['properties']['parameters'][k]['value'] = sorted(set(cur) | set(add))
out = {'properties': doc['properties']}
if doc.get('identity'): out['identity'] = doc['identity']
if doc.get('location'): out['location'] = doc['location']
json.dump(out, open(dst, 'w'))
PY
  az rest --only-show-errors --method put --url "$(pa $n)" --headers 'Content-Type=application/json' --body "@$f.put" >/dev/null
  echo "AFTER $n: $(az rest --only-show-errors --method get --url "$(pa $n)" | jq -c ".properties.parameters.$k.value")"; }
for v in "${LINUX_SCX_PASSWORD:-}" "${ESTHER_VM_ADMIN_PASSWORD:-}"; do [ -n "$v" ] && echo "::add-mask::$v"; done
[ -n "${LINUX_SCX_SSH_KEY:-}" ] && while IFS= read -r l; do [ -n "$l" ] && echo "::add-mask::$l"; done <<< "$LINUX_SCX_SSH_KEY"
case "$STAGE" in
policy)
  addvals lab-locations listOfAllowedLocations '["'"$LOC"'"]'
  addvals lab-disks allowedDiskSizesGb '[32]'
  addvals lab-disks allowedDiskSkus '["Standard_LRS"]'
  addvals lab-types listOfAllowedResourceTypes '["Microsoft.Network/virtualNetworks/virtualNetworkPeerings","Microsoft.Network/virtualNetworks/remoteVirtualNetworkPeeringProxies"]'
  echo POLICY_OK ;;
network)
  az network vnet show -g $RG -n $HUB --query "{a:addressSpace.addressPrefixes,l:location}" -o json
  az network vnet show -g $RG -n $VNET -o none 2>/dev/null || az network vnet create -g $RG -n $VNET -l $LOC --address-prefixes $SENET.0.0/16 --subnet-name $SESUB --subnet-prefixes $SENET.1.0/24 --only-show-errors -o none
  az network nsg show -g $RG -n $SENSG -o none 2>/dev/null || az network nsg create -g $RG -n $SENSG -l $LOC --only-show-errors -o none
  az network vnet subnet update -g $RG --vnet-name $VNET -n $SESUB --network-security-group $SENSG -o none
  peer() { for i in $(seq 1 8); do "$@" && return 0; echo "peering retry $i (policy propagation)"; sleep 60; done; return 1; }
  az network vnet peering list -g $RG --vnet-name $HUB --query "[].{n:name,state:peeringState}" -o tsv || true
  az network vnet peering show -g $RG --vnet-name $HUB -n hub-to-se -o none 2>/dev/null || peer az network vnet peering create -g $RG --vnet-name $HUB -n hub-to-se --remote-vnet $VNET --allow-vnet-access --only-show-errors -o none
  az network vnet peering show -g $RG --vnet-name $VNET -n se-to-hub -o none 2>/dev/null || peer az network vnet peering create -g $RG --vnet-name $VNET -n se-to-hub --remote-vnet $HUB --allow-vnet-access --only-show-errors -o none
  st=$(az network vnet peering show -g $RG --vnet-name $HUB -n hub-to-se --query peeringState -o tsv)
  if [ "$st" != Connected ]; then echo "hub-to-se=$st -> recreate se-to-hub"
    az network vnet peering delete -g $RG --vnet-name $VNET -n se-to-hub -o none 2>/dev/null || true; sleep 20
    peer az network vnet peering create -g $RG --vnet-name $VNET -n se-to-hub --remote-vnet $HUB --allow-vnet-access --only-show-errors -o none
    sleep 20; az network vnet peering sync -g $RG --vnet-name $HUB -n hub-to-se -o none 2>/dev/null || true; fi
  for v in $HUB $VNET; do az network vnet peering list -g $RG --vnet-name $v --query "[].{n:name,state:peeringState,sync:peeringSyncLevel}" -o table; done
  [ "$(az network vnet peering show -g $RG --vnet-name $HUB -n hub-to-se --query peeringState -o tsv)" = Connected ] || { echo PEERING_NOT_CONNECTED; exit 1; }
  # DNS: use the DC so the Linux box resolves esther.lab
  dcip=$(az vm list-ip-addresses -g $RG -n $P-dc-01 --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv); echo "DC_IP=$dcip"
  az network vnet update -g $RG -n $VNET --dns-servers $dcip -o none
  echo NETWORK_OK ;;
vm)
  echo "old israel nic:"; az network nic show -g $RG -n $VM-nic --query "{loc:location,ip:ipConfigurations[0].privateIPAddress,vm:virtualMachine.id}" -o json 2>&1 | head -5
  if az vm show -g $RG -n $VM -o none 2>/dev/null; then echo "VM exists"; else
  SUB=$(az network vnet subnet show -g $RG --vnet-name $VNET -n $SESUB --query id -o tsv)
  SUF=${LAB_NAME_SUFFIX:-}
  az network nic show -g $RG -n $VM-se-nic$SUF -o none 2>/dev/null || az network nic create -g $RG -n $VM-se-nic$SUF -l $LOC --subnet "$SUB" --private-ip-address $SENET.1.20 --only-show-errors -o none
  [ -z "$(az network nic show -g $RG -n $VM-se-nic$SUF --query 'ipConfigurations[0].publicIPAddress' -o tsv)" ]
  NICID=$(az network nic show -g $RG -n $VM-se-nic$SUF --query id -o tsv); echo "nic=$NICID"; az network nic show --ids "$NICID" --query "{loc:location,ps:provisioningState,ip:ipConfigurations[0].privateIPAddress,subnet:ipConfigurations[0].subnet.id}" -o json
  NICLOC=$(az network nic show --ids "$NICID" --query location -o tsv); [ "$NICLOC" = "$LOC" ] || { echo "NIC_WRONG_REGION $NICLOC"; exit 1; }
  sleep 15
  az vm create -g $RG -n $VM -l $LOC --image Canonical:ubuntu-24_04-lts:server:latest --size Standard_B2ats_v2 \
    --admin-username scomlab --ssh-key-values "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJOWebEQVYCGnjP+9YUfVvqteUy8OiADXZ+KfYdhiBQX scom-linux-lab" --authentication-type ssh \
    --nics "$NICID" --os-disk-name $VM-osdisk$SUF --os-disk-size-gb 32 --storage-sku Standard_LRS \
    --security-type TrustedLaunch --enable-secure-boot true --enable-vtpm true --only-show-errors -o none || { az deployment operation group list -g $RG -n $(az deployment group list -g $RG --query "sort_by([?starts_with(name,'vm_deploy')],&properties.timestamp)[-1].name" -o tsv) --query "[].{t:properties.targetResource.resourceType,s:properties.provisioningState,m:properties.statusMessage}" -o json; exit 1; }; fi
  az vm show -d -g $RG -n $VM --query "{size:hardwareProfile.vmSize,loc:location,power:powerState,priv:privateIps,pub:publicIps}" -o json
  dcip=$(az vm list-ip-addresses -g $RG -n $P-dc-01 --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv); echo "DC_IP=$dcip"; [ -n "$dcip" ]
  az disk show -g $RG -n $VM-osdisk --query "{gb:diskSizeGb,sku:sku.name,tier:tier}" -o json
  az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts "hostnamectl | head -3; ip -4 addr show eth0 | grep inet; systemctl is-active ssh; resolvectl status | grep 'DNS Servers' | head -2; ping -c2 -W2 $dcip | tail -2" --query "value[0].message" -o tsv
  echo LINUX_VM_OK ;;
scom-probe)
  az vm list -d -g $RG --query "[].{n:name,p:powerState,l:location}" -o table
  az network nsg rule list -g $RG --nsg-name esther-se-nsg --query "[].{n:name,p:priority,src:sourceAddressPrefix,ports:destinationPortRanges}" -o table
  sed "s/10\.78\.1\.20/$SENET.1.20/g" scripts/scom/linux-probe.ps1 > /tmp/probe.ps1
  az vm run-command invoke -g $RG -n $P-adaxes-01 --command-id RunPowerShellScript --scripts @/tmp/probe.ps1 --query "value[].message" -o tsv
  echo PROBE_DONE ;;
scom-agent-winrm)
  # SCOM part only, over WinRM from the DC (the SCOM server's own run-command slot is never used).
  # SCOM accepts only PuTTY-format SSH keys. ROTATE_KEY=true makes a fresh scxmon key and replaces authorized_keys on Linux.
  # SCOM accepts only PuTTY-format keys. The converted key is kept as secret LINUX_SCX_PPK_B64, so putty-tools is installed and run only after a rotation or when that secret is missing.
  if [ "${ROTATE_KEY:-false}" = true ] || [ -z "${LINUX_SCX_SSH_KEY:-}" ] || [ -z "${LINUX_SCX_PPK_B64:-}" ]; then
    sudo apt-get install -y -qq putty-tools >/dev/null 2>&1 || { sudo apt-get update -qq && sudo apt-get install -y -qq putty-tools >/dev/null; }
    if [ "${ROTATE_KEY:-false}" = true ] || [ -z "${LINUX_SCX_SSH_KEY:-}" ]; then
      rm -f /tmp/scxkey*; ssh-keygen -q -t rsa -b 3072 -m PEM -N '' -C scxmon-scom -f /tmp/scxkey
      while IFS= read -r l; do [ -n "$l" ] && echo "::add-mask::$l"; done < /tmp/scxkey
      GH_TOKEN="$LAB_AGENT_PAT" gh secret set LINUX_SCX_SSH_KEY -R "$GITHUB_REPOSITORY" < /tmp/scxkey && echo "secret LINUX_SCX_SSH_KEY rotated"
      PUB=$(ssh-keygen -y -f /tmp/scxkey)
      az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts "printf '%s\n' '$PUB scxmon-scom' > /home/scxmon/.ssh/authorized_keys && chown scxmon:scxmon /home/scxmon/.ssh/authorized_keys && chmod 600 /home/scxmon/.ssh/authorized_keys && echo AUTHKEYS_REPLACED lines=\$(wc -l < /home/scxmon/.ssh/authorized_keys)" --query "value[].message" -o tsv
    else printf '%s\n' "$LINUX_SCX_SSH_KEY" > /tmp/scxkey; chmod 600 /tmp/scxkey; fi
    puttygen /tmp/scxkey -O private -o /tmp/scxkey.ppk --ppk-param version=2 && echo "ppk converted"
    while IFS= read -r l; do [ -n "$l" ] && echo "::add-mask::$l"; done < /tmp/scxkey.ppk
    SCXB64=$(base64 -w0 /tmp/scxkey.ppk); echo "::add-mask::$SCXB64"; rm -f /tmp/scxkey /tmp/scxkey.ppk /tmp/scxkey.pub
    printf '%s' "$SCXB64" | GH_TOKEN="$LAB_AGENT_PAT" gh secret set LINUX_SCX_PPK_B64 -R "$GITHUB_REPOSITORY" && echo "secret LINUX_SCX_PPK_B64 saved"
  else SCXB64="$LINUX_SCX_PPK_B64"; echo "::add-mask::$SCXB64"; echo "ppk from secret (no conversion)"; fi
  # Secrets go into the script body (self-deleting on the DC), never on a command line.
  PW="$ESTHER_VM_ADMIN_PASSWORD" SCXPW="$LINUX_SCX_PASSWORD" KEYB64="$SCXB64" bash scripts/scom/dc-wrap.sh <(sed "s/10\.78\.1\.20/$SENET.1.20/g" scripts/scom/linux-agent.ps1) 840 > /tmp/dc-agent.ps1
  t0=$(date +%s); ti=$(date +%s%3N)
  az vm run-command invoke -g $RG -n $P-dc-01 --command-id RunPowerShellScript --scripts @/tmp/dc-agent.ps1 --query "value[].message" -o tsv | tee /tmp/a.txt
  tr_=$(date +%s%3N); rm -f /tmp/dc-agent.ps1; echo "STAGE_SECONDS=$(( $(date +%s)-t0 ))"
  ds=$(tr -d "\r" < /tmp/a.txt | sed -n "s/^DC_START_EPOCH=//p" | head -1); de=$(tr -d "\r" < /tmp/a.txt | sed -n "s/^DC_END_EPOCH=//p" | head -1)
  [ -n "$ds" ] && [ -n "$de" ] && awk -v a="$ti" -v b="$ds" -v c="$de" -v d="$tr_" 'BEGIN{printf "RUNCMD_DISPATCH_S=%.1f DC_SCRIPT_S=%.1f RUNCMD_RETURN_S=%.1f\n",(b-a)/1000,(c-b)/1000,(d-c)/1000}'
  grep -q SCX_AGENT_OK /tmp/a.txt ;;
scom-status)
  # Light SCOM op over the same DC -> WinRM path: module load + read-only status. No SSH key needed.
  PW="$ESTHER_VM_ADMIN_PASSWORD" SCXPW="" KEYB64="" bash scripts/scom/dc-wrap.sh scripts/scom/status.ps1 300 > /tmp/dc-status.ps1
  t0=$(date +%s); ti=$(date +%s%3N)
  az vm run-command invoke -g $RG -n $P-dc-01 --command-id RunPowerShellScript --scripts @/tmp/dc-status.ps1 --query "value[].message" -o tsv | tee /tmp/a.txt
  tr_=$(date +%s%3N); rm -f /tmp/dc-status.ps1; echo "STAGE_SECONDS=$(( $(date +%s)-t0 ))"
  ds=$(tr -d "\r" < /tmp/a.txt | sed -n "s/^DC_START_EPOCH=//p" | head -1); de=$(tr -d "\r" < /tmp/a.txt | sed -n "s/^DC_END_EPOCH=//p" | head -1)
  [ -n "$ds" ] && [ -n "$de" ] && awk -v a="$ti" -v b="$ds" -v c="$de" -v d="$tr_" 'BEGIN{printf "RUNCMD_DISPATCH_S=%.1f DC_SCRIPT_S=%.1f RUNCMD_RETURN_S=%.1f\n",(b-a)/1000,(c-b)/1000,(d-c)/1000}'
  grep -q SCOM_STATUS_DONE /tmp/a.txt ;;
ui-prep)
  az vm boot-diagnostics get-boot-log-uris -g $RG -n $P-adaxes-01 -o json 2>&1 | sed -E 's/\?[^"]*"/?<sas>"/' | head -5
  az vm show -g $RG -n $P-adaxes-01 --query "diagnosticsProfile" -o json
  PW="$ESTHER_VM_ADMIN_PASSWORD" SCXPW="" KEYB64="" bash scripts/scom/dc-wrap.sh scripts/scom/ui-prep.ps1 240 > /tmp/dc-ui.ps1
  az vm run-command invoke -g $RG -n $P-dc-01 --command-id RunPowerShellScript --scripts @/tmp/dc-ui.ps1 --query "value[].message" -o tsv | tee /tmp/a.txt; rm -f /tmp/dc-ui.ps1
  grep -q UI_PREP_DONE /tmp/a.txt ;;
scom-inventory)
  PW="$ESTHER_VM_ADMIN_PASSWORD" SCXPW="" KEYB64="" bash scripts/scom/dc-wrap.sh scripts/scom/inventory.ps1 300 > /tmp/dc-inv.ps1
  az vm run-command invoke -g $RG -n $P-dc-01 --command-id RunPowerShellScript --scripts @/tmp/dc-inv.ps1 --query "value[].message" -o tsv | tee /tmp/a.txt; rm -f /tmp/dc-inv.ps1
  grep -q INVENTORY_DONE /tmp/a.txt || exit 1
  # Pull the zipped unsealed-MP export off the DC in pieces: run-command returns at most ~4 KB per stream, so each call sends one piece on stdout and one on stderr.
  n=$(sed -n 's/.*MPZIP saved on DC chars=\([0-9]*\).*/\1/p' /tmp/a.txt | head -1); sha=$(sed -n 's/.*SHA256=\([0-9A-F]*\).*/\1/p' /tmp/a.txt | head -1)
  [ -n "$n" ] || { echo "no MP export"; exit 1; }
  C=3900; : > /tmp/mp.b64; i=0
  while [ $((i*C)) -lt "$n" ]; do
    az vm run-command invoke -g $RG -n $P-dc-01 --command-id RunPowerShellScript --scripts "\$s=[IO.File]::ReadAllText('C:\\scom-export\\mp.b64'); \$a=$((i*C)); \$b=$(((i+1)*C)); if (\$a -lt \$s.Length) { [Console]::Out.Write('P:' + \$s.Substring(\$a, [Math]::Min($C, \$s.Length-\$a))) }; if (\$b -lt \$s.Length) { [Console]::Error.Write('P:' + \$s.Substring(\$b, [Math]::Min($C, \$s.Length-\$b))) }" -o json > /tmp/p.json
    jq -r '.value[0].message' /tmp/p.json | tr -d '\r\n' | sed -n 's/.*P://p' >> /tmp/mp.b64
    jq -r '.value[1].message' /tmp/p.json | tr -d '\r\n' | sed -n 's/.*P://p' >> /tmp/mp.b64
    i=$((i+2)); echo "fetched $(wc -c < /tmp/mp.b64)/$n"
  done
  mkdir -p diag/mp-export; base64 -d /tmp/mp.b64 > diag/mp-export.zip
  got=$(sha256sum diag/mp-export.zip | cut -d' ' -f1 | tr a-f A-F); echo "sha expected=$sha got=$got"; [ "$got" = "$sha" ] || exit 1
  (cd diag/mp-export && unzip -o -q ../mp-export.zip && ls -la) ;;
swap-add)
  # 1 GiB swap file on the Linux VM (free, reversible: swapoff /swapfile; rm /swapfile; drop the fstab line).
  az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts 'set -e; echo "before:"; free -m | sed -n 1,3p; swapon --show; df -h / | tail -1; if ! swapon --show | grep -q /swapfile; then [ -f /swapfile ] || fallocate -l 1G /swapfile; chmod 600 /swapfile; mkswap /swapfile >/dev/null; swapon /swapfile; fi; grep -q "^/swapfile " /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab; echo "after:"; free -m | sed -n 1,3p; swapon --show; grep swapfile /etc/fstab; echo SWAP_DONE' --query "value[].message" -o tsv | tee /tmp/s.txt
  grep -q SWAP_DONE /tmp/s.txt ;;
ssh-fix)
  # Ubuntu 24.04 starts sshd via ssh.socket, so ssh.service shows inactive and SCOM raises 'SSH daemon is not running'.
  # Switch to the classic always-on service (reversible: systemctl disable --now ssh; systemctl enable --now ssh.socket).
  az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts 'systemctl disable --now ssh.socket; systemctl enable --now ssh; sleep 2; systemctl is-active ssh; ss -ltn | grep -E ":22 "; echo SSH_FIX_DONE' --query "value[].message" -o tsv | tee /tmp/s.txt
  grep -q SSH_FIX_DONE /tmp/s.txt ;;
ssh-check)
  # Read-only: sshd state on the Linux VM (SCOM 'SSH daemon is not running' alert).
  az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts 'systemctl is-active ssh sshd 2>&1; systemctl status ssh --no-pager 2>&1 | sed -n 1,6p; uptime; echo SSH_CHECK_DONE' --query "value[].message" -o tsv | tee /tmp/s.txt
  grep -q SSH_CHECK_DONE /tmp/s.txt ;;
omi-check)
  # Read-only: OMI/SCX versions on the Linux VM and who can reach port 1270.
  az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts 'dpkg-query -W -f="\${Package} \${Version}\n" omi scx 2>/dev/null; rpm -q omi scx 2>/dev/null; /opt/omi/bin/omiserver --version 2>&1 | head -3; ss -ltnp 2>/dev/null | grep -E ":(1270|5985|5986)\b"; echo OMI_CHECK_DONE' --query "value[].message" -o tsv
  NIC=$(az vm show -g $RG -n $VM --query "networkProfile.networkInterfaces[0].id" -o tsv)
  az network nic show --ids "$NIC" --query "{nic:name,nsg:networkSecurityGroup.id,ip:ipConfigurations[0].privateIPAddress,pub:ipConfigurations[0].publicIPAddress.id,subnet:ipConfigurations[0].subnet.id}" -o json
  az network nic list-effective-nsg --ids "$NIC" --query "value[].effectiveSecurityRules[?direction=='Inbound' && access=='Allow'].{name:name,prio:priority,src:sourceAddressPrefix,srcs:join(',',expandedSourceAddressPrefix || \`[]\`),dst:destinationPortRange,dsts:join(',',destinationPortRanges || \`[]\`),proto:protocol}" -o table 2>&1 | head -30
  az network vnet subnet show --ids "$(az network nic show --ids "$NIC" --query ipConfigurations[0].subnet.id -o tsv)" --query "{subnet:name,nsg:networkSecurityGroup.id,defOut:defaultOutboundAccess}" -o json ;;
ui-grab)
  mkdir -p diag; u=$(az vm boot-diagnostics get-boot-log-uris -g $RG -n $P-adaxes-01 --query consoleScreenshotBlobUri -o tsv); echo "::add-mask::$u"
  curl -sS -f -o diag/scom-console.bmp "$u"; echo "curl_rc=$?"; ls -la diag/; [ -s diag/scom-console.bmp ] ;;
ui-shot)
  PW="$ESTHER_VM_ADMIN_PASSWORD" SCXPW="" KEYB64="" bash scripts/scom/dc-wrap.sh scripts/scom/ui-shot.ps1 300 > /tmp/dc-ui.ps1
  az vm run-command invoke -g $RG -n $P-dc-01 --command-id RunPowerShellScript --scripts @/tmp/dc-ui.ps1 --query "value[].message" -o tsv | tee /tmp/a.txt; rm -f /tmp/dc-ui.ps1
  # Boot-diagnostics console screenshot (short-lived SAS; masked, never printed).
  mkdir -p diag; u=$(az vm boot-diagnostics get-boot-log-uris -g $RG -n $P-adaxes-01 --query consoleScreenshotBlobUri -o tsv); echo "::add-mask::$u"
  curl -sS -f -o diag/scom-console.bmp "$u"; echo "curl_rc=$?"; ls -la diag/
  grep -q UI_SHOT_DONE /tmp/a.txt ;;
scx-cert-fix)
  # SCX agent cert CN must equal the FQDN SCOM connects to (esther-linux-01.esther.lab). Regenerate it with the right host/domain and restart only the SCX agent service.
  az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts 'c=/etc/opt/omi/ssl/omi-host-$(hostname).pem; [ -f "$c" ] || c=$(ls /etc/opt/omi/ssl/omi-host-*.pem | head -1); echo "before: $(openssl x509 -in "$c" -noout -subject -issuer 2>&1)"; /opt/microsoft/scx/bin/tools/scxsslconfig -f -h esther-linux-01 -d esther.lab 2>&1 | tail -2; /opt/microsoft/scx/bin/tools/scxadmin -restart 2>&1 | tail -2; c=$(ls -t /etc/opt/omi/ssl/omi-host-*.pem | head -1); echo "after: $(openssl x509 -in "$c" -noout -subject -issuer 2>&1)"; echo SCX_CERT_DONE' --query "value[].message" -o tsv | tee /tmp/c.txt
  grep -q SCX_CERT_DONE /tmp/c.txt ;;
netperf)
  az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts @scripts/netperf-linux.sh --query "value[].message" -o tsv
  az vm run-command invoke -g $RG -n $P-dc-01 --command-id RunPowerShellScript --scripts '$r=@(); 1..5 | ForEach-Object { $s=[Diagnostics.Stopwatch]::StartNew(); $c=New-Object Net.Sockets.TcpClient; $c.Connect("10.78.1.20",22); $s.Stop(); $c.Close(); $r+=[math]::Round($s.Elapsed.TotalMilliseconds,1) }; "dc->linux tcp22 ms: " + ($r -join " "); $s=[Diagnostics.Stopwatch]::StartNew(); $ProgressPreference="SilentlyContinue"; Invoke-WebRequest http://10.78.1.20:1270/np.bin -OutFile $env:TEMP\np.bin -UseBasicParsing; $s.Stop(); $b=(Get-Item $env:TEMP\np.bin).Length; Remove-Item $env:TEMP\np.bin; "sweden->israel http bytes=$b sec=" + [math]::Round($s.Elapsed.TotalSeconds,2) + " Mbps=" + [math]::Round($b*8/1e6/$s.Elapsed.TotalSeconds,1); $s=[Diagnostics.Stopwatch]::StartNew(); $null=Invoke-Command -ComputerName ESTHERLAB.esther.lab -ScriptBlock { 1 } -ErrorAction SilentlyContinue; "winrm dc->scom (no cred, SYSTEM) ms=" + [int]$s.Elapsed.TotalMilliseconds' --query "value[].message" -o tsv
  az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts 'pkill -f "http.server 1270"; rm -f /tmp/np.bin; echo cleaned' --query "value[].message" -o tsv ;;
winrm-probe|winrm-unstick|winrm-inspect)
  q_() { printf "%s" "$1" | sed "s/'/''/g"; }
  { printf "\$Mode = '%s'; \$Pw = '%s'\ntry {\n" "${STAGE#winrm-}" "$(q_ "$ESTHER_VM_ADMIN_PASSWORD")"; cat scripts/scom/winrm-remote.ps1; printf "\n} finally { if (\$PSCommandPath) { Remove-Item \$PSCommandPath -Force -ErrorAction SilentlyContinue } }\n"; } > /tmp/w.ps1
  az vm run-command invoke -g $RG -n $P-dc-01 --command-id RunPowerShellScript --scripts @/tmp/w.ps1 --query "value[].message" -o tsv | tee /tmp/w.txt; rm -f /tmp/w.ps1
  grep -q "WINRM_.*_DONE" /tmp/w.txt ;;
scom-unstick)
  # A managed run command (separate handler) kills a hung action-run-command script on the SCOM server.
  az vm run-command create -g $RG --vm-name $P-adaxes-01 --name unstick --location ${LAB_LOCATION:-israelcentral} --script "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { \$_.CommandLine -match 'RunCommandWindows.+Downloads.+script' } | ForEach-Object { 'kill ' + \$_.ProcessId + ' ' + \$_.CommandLine.Substring(0,[Math]::Min(160,\$_.CommandLine.Length)); Stop-Process -Id \$_.ProcessId -Force }; 'UNSTICK_DONE'" --timeout-in-seconds 300 --only-show-errors -o none
  az vm run-command show -g $RG --vm-name $P-adaxes-01 --name unstick --instance-view --query "instanceView.{s:executionState,o:output,e:error}" -o json
  az vm run-command delete -g $RG --vm-name $P-adaxes-01 --name unstick --yes -o none ;;
dc-unstick)
  # A managed run command (separate handler) kills a hung action-run-command script on the DC (e.g. left behind by a cancelled scom-inventory run).
  az vm run-command create -g $RG --vm-name $P-dc-01 --name unstick --location ${LAB_LOCATION:-israelcentral} --script "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | Where-Object { \$_.CommandLine -match 'RunCommandWindows.+Downloads.+script' } | ForEach-Object { 'kill ' + \$_.ProcessId + ' ' + \$_.CommandLine.Substring(0,[Math]::Min(160,\$_.CommandLine.Length)); Stop-Process -Id \$_.ProcessId -Force }; 'UNSTICK_DONE'" --timeout-in-seconds 300 --only-show-errors -o none
  az vm run-command show -g $RG --vm-name $P-dc-01 --name unstick --instance-view --query "instanceView.{s:executionState,o:output,e:error}" -o json
  az vm run-command delete -g $RG --vm-name $P-dc-01 --name unstick --yes -o none ;;
esac
