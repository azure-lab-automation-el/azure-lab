# mivtza-eser DC first-boot state machine. Transported via CustomData - NO SECRETS in this file.
# Secrets arrive separately at C:\lab-secrets\secrets.json (run-command drop). Runs as SYSTEM via scheduled task.
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
$w = 'C:\lab'; New-Item -ItemType Directory -Force $w | Out-Null
$log = "$w\state.log"; $sf = "$w\state.json"
function L($m) { $t = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); Add-Content $log "$t $m" }
function Get-Phase { if (Test-Path $sf) { try { (Get-Content $sf -Raw | ConvertFrom-Json).phase } catch { 'start' } } else { 'start' } }
function Set-Phase($p) { @{ phase = $p; at = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress | Set-Content $sf; L "phase=$p"; $p }
function Write-Table($tb, $sas, $pk, $rk, $data) {
  $u = "$tb(PartitionKey='$pk',RowKey='$rk')?$sas"
  $e = @{ PartitionKey = $pk; RowKey = $rk; data = $data } | ConvertTo-Json -Compress
  Invoke-WebRequest $u -Method Put -Body ([Text.Encoding]::UTF8.GetBytes($e)) -ContentType 'application/json' -Headers @{ 'x-ms-version' = '2019-02-02'; Accept = 'application/json;odata=nometadata' } -UseBasicParsing -TimeoutSec 30 | Out-Null
}
L 'boot'
$sec = $null; $t0 = Get-Date
$phase = Get-Phase
while ($true) {
  switch ($phase) {
    'start' {
      L 'harden: defender exclusions (build-only) + WU manual + servermanager off'
      Add-MpPreference -ExclusionPath @('C:\lab', 'C:\scomlab', 'C:\media', 'C:\Program Files\Microsoft SQL Server', 'C:\Program Files\Microsoft System Center') -ErrorAction SilentlyContinue
      Set-Service wuauserv -StartupType Manual -ErrorAction SilentlyContinue; Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
      Disable-ScheduledTask -TaskPath '\Microsoft\Windows\Server Manager\' -TaskName 'ServerManager' -ErrorAction SilentlyContinue | Out-Null
      $phase = Set-Phase 'await-secrets'
    }
    'await-secrets' {
      if (Test-Path 'C:\lab-secrets\secrets.json') { $sec = Get-Content 'C:\lab-secrets\secrets.json' -Raw | ConvertFrom-Json; L 'secrets received'; $phase = Set-Phase 'features' }
      elseif (((Get-Date) - $t0).TotalMinutes -gt 12) { L 'FAIL: secrets never arrived'; exit 1 } else { Start-Sleep 10 }
    }
    'features' {
      L 'install AD-Domain-Services + DNS'
      Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
      $phase = Set-Phase 'promo'
    }
    'promo' {
      L 'Install-ADDSForest esther.lab'
      Import-Module ADDSDeployment
      $r = Install-ADDSForest -DomainName 'esther.lab' -DomainNetbiosName 'ESTHER' -InstallDns -SafeModeAdministratorPassword (ConvertTo-SecureString $sec.dsrm -AsPlainText -Force) -NoRebootOnCompletion -Force -WarningAction SilentlyContinue
      L "promo status=$($r.Status)"
      Set-Phase 'postpromo' | Out-Null
      Restart-Computer -Force
      exit 0
    }
    'postpromo' {
      $ok = $false
      for ($i = 0; $i -lt 60; $i++) { if (Get-Service ADWS -ErrorAction SilentlyContinue | Where-Object Status -eq 'Running') { $ok = $true; break }; Start-Sleep 10 }
      if (-not $ok) { L 'FAIL: ADWS not running after 10 min'; exit 1 }
      L 'ADWS up; DNS forwarder -> Azure DNS'
      $f = @(Get-DnsServerForwarder).IPAddress.IPAddressToString
      if ($f -notcontains '168.63.129.16') { Set-DnsServerForwarder -IPAddress 168.63.129.16 -Confirm:$false | Out-Null }
      Clear-DnsServerCache -Confirm:$false
      L 'single-shot accounts: OU + 5 svc users + SCOM-Admins'
      Import-Module ActiveDirectory
      $d = Get-ADDomain; $ou = "OU=SCOM,$($d.DistinguishedName)"
      if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'SCOM'")) { New-ADOrganizationalUnit -Name 'SCOM' -Path $d.DistinguishedName }
      $s = ConvertTo-SecureString $sec.svc -AsPlainText -Force
      foreach ($n in 'svc-scom-action', 'svc-scom-sdk', 'svc-scom-dra', 'svc-scom-dwr', 'svc-sql') {
        if (-not (Get-ADUser -Filter "SamAccountName -eq '$n'")) {
          New-ADUser -Name $n -SamAccountName $n -UserPrincipalName "$n@$($d.DNSRoot)" -Path $ou -AccountPassword $s -Enabled $true -PasswordNeverExpires $true -CannotChangePassword $true
        }
      }
      if (-not (Get-ADUser -Filter "SamAccountName -eq 'estherlabadmin'")) {
        New-ADUser -Name 'estherlabadmin' -SamAccountName 'estherlabadmin' -UserPrincipalName "estherlabadmin@$($d.DNSRoot)" -Path $d.UsersContainer -AccountPassword (ConvertTo-SecureString $sec.admin -AsPlainText -Force) -Enabled $true -PasswordNeverExpires $true
        Add-ADGroupMember 'Domain Admins' -Members 'estherlabadmin'
      }
      if (-not (Get-ADGroup -Filter "Name -eq 'SCOM-Admins'")) { New-ADGroup -Name 'SCOM-Admins' -GroupScope Global -Path $ou }
      Add-ADGroupMember 'SCOM-Admins' -Members 'svc-scom-sdk', 'svc-scom-dra', 'estherlabadmin'
      L 'djoin provision ESTHERLAB -> table row'
      & djoin.exe /provision /domain 'esther.lab' /machine 'ESTHERLAB' /savefile "$w\djoin-estherlab.txt" | Out-Null
      $blob = Get-Content "$w\djoin-estherlab.txt" -Raw
      Write-Table $sec.tableBase $sec.tableSas 'lab' 'djoin-ESTHERLAB' $blob
      Remove-Item "$w\djoin-estherlab.txt" -Force
      Write-Table $sec.tableBase $sec.tableSas 'dc' 'state' (@{ phase = 'ready'; at = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress)
      $phase = Set-Phase 'ready'
    }
    'ready' { L 'done'; Remove-Item 'C:\lab-secrets\secrets.json' -Force -ErrorAction SilentlyContinue; exit 0 }
    default { L "FAIL: unknown phase $phase"; exit 1 }
  }
}
