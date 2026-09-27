# mivtza-eser SCOM/SQL VM first-boot state machine. Transported via CustomData - NO SECRETS here.
# Secrets arrive at C:\lab-secrets\secrets.json (run-command drop). Runs as SYSTEM via scheduled task.
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
$w = 'C:\lab'; New-Item -ItemType Directory -Force $w | Out-Null
$log = "$w\state.log"; $sf = "$w\state.json"
$script:sec = $null; $script:hist = @{}
function L($m) { $t = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); Add-Content $log "$t $m" }
function Get-Phase { if (Test-Path $sf) { try { (Get-Content $sf -Raw | ConvertFrom-Json).phase } catch { 'start' } } else { 'start' } }
function Write-Table($pk, $rk, $data) {
  $u = "$($script:sec.tableBase)(PartitionKey='$pk',RowKey='$rk')?$($script:sec.tableSas)"
  $e = @{ PartitionKey = $pk; RowKey = $rk; data = $data } | ConvertTo-Json -Compress
  Invoke-WebRequest $u -Method Put -Body ([Text.Encoding]::UTF8.GetBytes($e)) -ContentType 'application/json' -Headers @{ 'x-ms-version' = '2019-02-02'; Accept = 'application/json;odata=nometadata' } -UseBasicParsing -TimeoutSec 30 | Out-Null
}
function Read-Table($pk, $rk) {
  $u = "$($script:sec.tableBase)(PartitionKey='$pk',RowKey='$rk')?$($script:sec.tableSas)"
  (Invoke-WebRequest $u -Headers @{ 'x-ms-version' = '2019-02-02'; Accept = 'application/json;odata=nometadata' } -UseBasicParsing -TimeoutSec 30).Content | ConvertFrom-Json
}
function Set-Phase($p) {
  $script:hist[$p] = (Get-Date).ToUniversalTime().ToString('o')
  @{ phase = $p; at = $script:hist[$p] } | ConvertTo-Json -Compress | Set-Content $sf; L "phase=$p"
  if ($script:sec) { try { Write-Table 'vm' 'state' (@{ phase = $p; hist = $script:hist } | ConvertTo-Json -Compress) } catch { L "table write failed: $($_.Exception.Message)" } }
  $p
}
function Fail($m) { L "FAIL: $m"; try { Write-Table 'vm' 'state' (@{ phase = 'failed'; error = $m; hist = $script:hist } | ConvertTo-Json -Compress) } catch {}; exit 1 }
L 'boot'
$phase = Get-Phase; $t0 = Get-Date
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
      if (Test-Path 'C:\lab-secrets\secrets.json') { $script:sec = Get-Content 'C:\lab-secrets\secrets.json' -Raw | ConvertFrom-Json; L 'secrets received'; $phase = Set-Phase 'prereq' }
      elseif (((Get-Date) - $t0).TotalMinutes -gt 12) { Fail 'secrets never arrived' } else { Start-Sleep 10 }
    }
    'prereq' {
      L 'IIS + ASP.NET prereqs for SCOM web console'
      $iis = 'Web-Server','Web-WebServer','Web-Common-Http','Web-Default-Doc','Web-Dir-Browsing','Web-Http-Errors','Web-Static-Content','Web-Health','Web-Http-Logging','Web-Request-Monitor','Web-Performance','Web-Stat-Compression','Web-Security','Web-Filtering','Web-Windows-Auth','Web-App-Dev','Web-Net-Ext45','Web-Asp-Net45','Web-ISAPI-Ext','Web-ISAPI-Filter','Web-Mgmt-Tools','Web-Mgmt-Console','Web-Mgmt-Compat','Web-Metabase','NET-WCF-HTTP-Activation45'
      $r = Install-WindowsFeature $iis -IncludeManagementTools
      L "iis success=$($r.Success) restart=$($r.RestartNeeded)"
      if (-not $r.Success) { Fail 'IIS prereq install failed' }
      $phase = Set-Phase 'media'
    }
    'media' {
      New-Item -ItemType Directory -Force 'C:\media', 'C:\scomlab' | Out-Null
      foreach ($f in @(@{n='scom-tree.7z'; sha=$script:sec.scomSha}, @{n='7zr.exe'; sha=$script:sec.szrSha})) {
        if (-not (Test-Path "C:\media\$($f.n)") -or (Get-FileHash "C:\media\$($f.n)" -Algorithm SHA256).Hash.ToLower() -ne $f.sha) {
          L "downloading $($f.n)"
          Invoke-WebRequest "$($script:sec.mediaBase)/$($f.n)?$($script:sec.mediaSas)" -OutFile "C:\media\$($f.n)" -UseBasicParsing -TimeoutSec 900
        }
        $h = (Get-FileHash "C:\media\$($f.n)" -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $f.sha) { Fail "$($f.n) sha256 mismatch: $h" }
        L "$($f.n) verified"
      }
      L 'extracting SCOM tree'
      & C:\media\7zr.exe x C:\media\scom-tree.7z -oC:\scomlab\scom -y | Out-Null
      if (-not (Test-Path 'C:\scomlab\scom\Setup.exe')) { Fail 'Setup.exe missing after extract' }
      $phase = Set-Phase 'await-domain'
    }
    'await-domain' {
      $ok = $false
      for ($i = 0; $i -lt 120; $i++) {
        try { $d = (Read-Table 'dc' 'state').data | ConvertFrom-Json; if ($d.phase -eq 'ready') { $ok = $true; break } } catch {}
        Start-Sleep 10
      }
      if (-not $ok) { Fail 'DC not ready after 20 min' }
      L 'DC ready; djoin offline join'
      $blob = (Read-Table 'lab' 'djoin-ESTHERLAB').data
      Set-Content "$w\djoin.txt" $blob -Encoding ASCII
      & djoin.exe /requestodj /loadfile "$w\djoin.txt" /windowspath $env:SystemRoot /localos | Out-Null
      Remove-Item "$w\djoin.txt" -Force
      Set-Phase 'postjoin' | Out-Null
      Restart-Computer -Force
      exit 0
    }
    'postjoin' {
      $d = (Get-CimInstance Win32_ComputerSystem).Domain
      if ($d -ne 'esther.lab') { Fail "not domain joined (domain=$d)" }
      L "joined $d"
      $phase = Set-Phase 'sql-config'
    }
    'sql-config' {
      $sq = (Get-ChildItem 'C:\Program Files\Microsoft SQL Server' -Recurse -Filter SQLCMD.EXE -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
      if (-not $sq) { Fail 'sqlcmd not found - SQL marketplace image missing?' }
      $h = $env:COMPUTERNAME
      $v = & $sq -E -S $h -h -1 -W -b -Q "SET NOCOUNT ON; SELECT CAST(SERVERPROPERTY('ProductVersion') AS varchar(32))+'|'+CAST(SERVERPROPERTY('Collation') AS varchar(64))+'|'+CAST(FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') AS varchar(1))+'|'+CAST(IS_SRVROLEMEMBER('sysadmin','NT AUTHORITY\SYSTEM') AS varchar(1))"
      L "sql: $v"
      $p = "$v" -split '\|'
      if ($p[1] -ne 'SQL_Latin1_General_CP1_CI_AS') { Fail "collation $($p[1]) - marketplace image not usable" }
      if ($p[2] -ne '1') { Fail 'FullText not installed - marketplace image not usable' }
      if ([version]$p[0] -lt [version]'16.0.4105.0') { Fail "SQL build $($p[0]) older than CU11" }
      if ($p[3] -eq '1') { L 'SYSTEM already sysadmin (marketplace image default)' }
      else {
        L 'granting SYSTEM sysadmin via one-time task as ESTHER\estherlabadmin'
        $sql = "SET NOCOUNT ON; IF SUSER_ID('NT AUTHORITY\SYSTEM') IS NULL CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS; ALTER SERVER ROLE sysadmin ADD MEMBER [NT AUTHORITY\SYSTEM]; SELECT CAST(IS_SRVROLEMEMBER('sysadmin','NT AUTHORITY\SYSTEM') AS varchar(1));"
        Set-Content "$w\grant.ps1" "& '$sq' -E -S $h -h -1 -W -b -Q `"$sql`" | Out-File $w\grant-out.txt; 'done' | Out-File $w\grant-done.txt"
        Remove-Item "$w\grant-out.txt", "$w\grant-done.txt" -ErrorAction SilentlyContinue
        $act = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -File $w\grant.ps1"
        Register-ScheduledTask -TaskName scom-grant -Action $act -User 'ESTHER\estherlabadmin' -Password $script:sec.admin -RunLevel Highest -Force | Out-Null
        Start-ScheduledTask scom-grant; $t = 0; while (-not (Test-Path "$w\grant-done.txt") -and $t -lt 180) { Start-Sleep 5; $t += 5 }
        Unregister-ScheduledTask scom-grant -Confirm:$false
        $chk = Get-Content "$w\grant-out.txt" -ErrorAction SilentlyContinue
        Remove-Item "$w\grant.ps1", "$w\grant-out.txt", "$w\grant-done.txt" -Force -ErrorAction SilentlyContinue
        if ("$chk" -notmatch '1') { Fail 'SYSTEM still not sysadmin after grant' }
      }
      $phase = Set-Phase 'scom'
    }
    'scom' {
      $p = $script:sec.svc; $h = $env:COMPUTERNAME
      $sa = @('/silent', '/install', '/components:OMServer,OMConsole', '/ManagementGroupName:ESTHER-MG',
        "/SqlServerInstance:$h", '/DatabaseName:OperationsManager', '/DatabaseSize:1000', "/DWSqlServerInstance:$h", '/DWDatabaseName:OperationsManagerDW', '/DWDatabaseSize:1000',
        '/ActionAccountUser:ESTHER\svc-scom-action', "/ActionAccountPassword:$p", '/DASAccountUser:ESTHER\svc-scom-sdk', "/DASAccountPassword:$p",
        '/DataReaderUser:ESTHER\svc-scom-dra', "/DataReaderPassword:$p", '/DataWriterUser:ESTHER\svc-scom-dwr', "/DataWriterPassword:$p",
        '/SendODRReports:0', '/EnableErrorReporting:Never', '/SendCEIPReports:0', '/UseMicrosoftUpdate:0', '/AcceptEndUserLicenseAgreement:1')
      L 'SCOM setup start (OMServer,OMConsole)'
      $pr = Start-Process 'C:\scomlab\scom\Setup.exe' -ArgumentList $sa -PassThru; $t = 0
      while (-not $pr.HasExited -and $t -lt 3600) { Start-Sleep 20; $t += 20 }
      if (-not $pr.HasExited) { $pr | Stop-Process -Force; Fail 'SCOM setup still running after 60 min' }
      L "setup exit=$($pr.ExitCode) min=$([math]::Round($t/60))"
      if ($pr.ExitCode -ne 0) { Fail "SCOM setup exit $($pr.ExitCode)" }
      if ((Get-Service OMSDK -ErrorAction SilentlyContinue).Status -ne 'Running') { Fail 'OMSDK not running after setup' }
      $phase = Set-Phase 'webconsole'
    }
    'webconsole' {
      $ic = 'HKLM:\Software\Microsoft\InetStp\Components'
      if ($null -eq (Get-ItemProperty $ic -ErrorAction SilentlyContinue).ASPNET) {
        L 'ASPNET marker via TrustedInstaller'
        $ti = (Get-Service TrustedInstaller).Path -replace '^.*\\(?=svchost)', ''
        & sc.exe config TrustedInstaller binPath= "$env:SystemRoot\servicing\TrustedInstaller.exe" | Out-Null
        Start-Service TrustedInstaller -ErrorAction SilentlyContinue
        $p = Start-Process reg.exe -ArgumentList "add $ic /v ASPNET /t REG_SZ /d 1 /f" -PassThru -Wait
        if ($p.ExitCode -ne 0) { L 'reg add direct failed; trying via service context' }
      }
      $h = $env:COMPUTERNAME
      $sa = @('/silent', '/install', '/components:OMWebConsole', "/ManagementServer:$h", '/WebSiteName:"Default Web Site"', '/WebConsoleAuthorizationMode:Mixed',
        '/SendCEIPReports:0', '/UseMicrosoftUpdate:0', '/AcceptEndUserLicenseAgreement:1')
      $pr = Start-Process 'C:\scomlab\scom\Setup.exe' -ArgumentList $sa -PassThru; $t = 0
      while (-not $pr.HasExited -and $t -lt 2400) { Start-Sleep 15; $t += 15 }
      if (-not $pr.HasExited) { $pr | Stop-Process -Force; Fail 'web console setup still running after 40 min' }
      L "webconsole exit=$($pr.ExitCode)"
      if (-not (Test-Path 'C:\Program Files\Microsoft System Center\Operations Manager\WebConsole')) { Fail 'web console folder missing after setup' }
      $phase = Set-Phase 'ready'
    }
    'ready' {
      Write-Table 'vm' 'state' (@{ phase = 'ready'; hist = $script:hist } | ConvertTo-Json -Compress)
      Remove-Item 'C:\lab-secrets\secrets.json' -Force -ErrorAction SilentlyContinue
      L 'done'; exit 0
    }
    default { Fail "unknown phase $phase" }
  }
}
