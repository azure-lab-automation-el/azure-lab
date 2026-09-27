#!/usr/bin/env bash
# Lab fixes on the DC for open SCOM alerts. Reversible: previous DNS list saved to C:\scomlab\dns-before.txt; SPNs removed with setspn -D.
# Sourced from esther-scom-phase5.sh (needs RG).
DC=${LAB_PREFIX:-esther}-dc-01
out=$(az vm run-command invoke -g "$RG" -n $DC --command-id RunPowerShellScript --scripts '
$ErrorActionPreference="Continue"; New-Item -ItemType Directory -Force C:\scomlab | Out-Null
$a = Get-NetAdapter | Where-Object Status -eq Up | Select-Object -First 1
$cur = (Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4).ServerAddresses
"dns-before=" + ($cur -join ",")
$ip = (Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4).IPAddress; "ip=$ip"
$want = @($ip, "127.0.0.1")
if (($cur -join ",") -ne ($want -join ",")) { ($cur -join ",") | Out-File C:\scomlab\dns-before.txt; Set-DnsClientServerAddress -InterfaceIndex $a.ifIndex -ServerAddresses $want; "dns-after=" + ((Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4).ServerAddresses -join ",") } else { "dns already recommended" }
"resolve=" + ((Resolve-DnsName esther.lab -Type A -ErrorAction SilentlyContinue | Select-Object -First 1).IPAddress)
"forwarders=" + ((Get-DnsServerForwarder).IPAddress -join ",")
foreach ($s in "MSOMSdkSvc/ESTHERLAB", "MSOMSdkSvc/ESTHERLAB.esther.lab") { $r = setspn -S $s ESTHER\svc-scom-sdk 2>&1 | Out-String; "spn $s -> " + ($r -replace "\s+"," ").Trim() }
"spns=" + ((setspn -L ESTHER\svc-scom-sdk | Select-Object -Skip 1 | % { $_.Trim() }) -join ",")
"DC_FIXES_DONE"' -o json | jq -r '.value[]?.message' | grep -v '^\s*$')
echo "$out" | tail -30
grep -q DC_FIXES_DONE <<<"$out" || { echo "STAGE_FAIL dc-fixes"; exit 1; }
