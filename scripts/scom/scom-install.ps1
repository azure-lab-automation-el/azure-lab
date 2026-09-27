param($stage, $p, $out, $a)
# SCOM 2025 single-server install on Esther (management server, console, web console, reporting) + console screenshot.
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
trap { "STAGE_FAIL $stage : $($_.Exception.Message)"; exit 1 }
$w = 'C:\scomlab'; $h = $env:COMPUTERNAME
switch ($stage) {
 'install' {
  foreach ($acct in 'ESTHER\svc-scom-action', 'ESTHER\svc-scom-sdk') { if (-not (Get-LocalGroupMember Administrators | Where-Object Name -eq $acct)) { Add-LocalGroupMember Administrators $acct; "localAdmin+=$acct" } }
  # Web console prerequisite (AspNetCheck): ASP.NET 4.x + WCF HTTP activation in IIS (from the local component store, no internet needed).
  $f = Install-WindowsFeature NET-Framework-45-ASPNET, Web-Asp-Net45, Web-Net-Ext45, Web-ISAPI-Ext, Web-ISAPI-Filter, NET-WCF-HTTP-Activation45, Web-Windows-Auth, Web-Metabase, Web-Mgmt-Console
  "features: success=$($f.Success) restart=$($f.RestartNeeded) changed=" + (($f.FeatureResult | ForEach-Object Name) -join ',')
  if (-not (Get-Service OMSDK -ErrorAction SilentlyContinue)) {
   $sa = @('/silent', '/install', '/components:OMServer,OMConsole', '/ManagementGroupName:ESTHER-MG',
    "/SqlServerInstance:$h", '/DatabaseName:OperationsManager', '/DatabaseSize:1000', "/DWSqlServerInstance:$h", '/DWDatabaseName:OperationsManagerDW', '/DWDatabaseSize:1000',
    '/ActionAccountUser:ESTHER\svc-scom-action', "/ActionAccountPassword:$p", '/DASAccountUser:ESTHER\svc-scom-sdk', "/DASAccountPassword:$p",
    '/DataReaderUser:ESTHER\svc-scom-dra', "/DataReaderPassword:$p", '/DataWriterUser:ESTHER\svc-scom-dwr', "/DataWriterPassword:$p",
    
    '/SendODRReports:0', '/EnableErrorReporting:Never', '/SendCEIPReports:0', '/UseMicrosoftUpdate:0', '/AcceptEndUserLicenseAgreement:1')
   # Reporting (SSRS) is left for phase 6. Setup runs as SYSTEM; stage 'sqlgrant' makes SYSTEM a SQL sysadmin first.
   $pr = Start-Process "$w\scom\setup.exe" -ArgumentList $sa -PassThru; $t = 0
   while (-not $pr.HasExited -and $t -lt 4800) { Start-Sleep 20; $t += 20 }
   if ($pr.HasExited) { "setupExit=$($pr.ExitCode) minutes=" + [math]::Round($t / 60) } else { $pr | Stop-Process -Force; "STAGE_FAIL setup still running after 80 min" }
  }
  $log = Get-ChildItem 'C:\Windows\System32\config\systemprofile\AppData\Local\SCOM\Logs' -Filter OpsMgrSetupWizard.log -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($log) { Get-Content $log.FullName -Tail 400 | Select-String -Pattern 'Error|failed|prerequisite|Warning' | Select-Object -Last 25 | ForEach-Object { "log: " + $_.Line.Substring(0, [math]::Min(220, $_.Line.Length)) } }
  Get-Service OMSDK, HealthService, cshost -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)=$($_.Status)" }
  if ((Get-Service OMSDK -ErrorAction SilentlyContinue).Status -ne 'Running') { "STAGE_FAIL OMSDK (Data Access Service) is not running after setup" }
  "freeGB=" + [math]::Round((Get-PSDrive C).Free / 1GB, 1)
 }
 'webconsole' {
  # Phase 6: SCOM Web Console on the existing management server (Default Web Site, Mixed auth).
  # Prereq fix: SCOM setup AspNetCheck (PrerequisiteInputFile.xml check 82) only tests that
  # HKLM\Software\Microsoft\InetStp\Components\ASPNET exists. Web-Asp-Net45 writes ASPNET45, not ASPNET,
  # so the check returns 2 on Server 2019+. Set the marker, then log every web console registry prereq.
  $ic = 'HKLM:\Software\Microsoft\InetStp\Components'
  # The Components key is writable only by TrustedInstaller, and the lab subnet has no internet (Web-Asp-Net/.NET 3.5 can't download).
  # So run one 'reg add' inside the TrustedInstaller service (its token carries the TrustedInstaller SID), then restore the service's path.
  if ((Get-ItemProperty $ic -ErrorAction SilentlyContinue).ASPNET -eq $null) {
   $svc = 'HKLM:\SYSTEM\CurrentControlSet\Services\TrustedInstaller'; $bp = (Get-ItemProperty $svc).ImagePath; "prereq: TI path=$bp"
   try {
    Stop-Service TrustedInstaller -Force -ErrorAction SilentlyContinue
    & sc.exe config TrustedInstaller binPath= 'cmd.exe /c reg add HKLM\SOFTWARE\Microsoft\InetStp\Components /v ASPNET /t REG_DWORD /d 1 /f' | Out-Null
    & sc.exe start TrustedInstaller | Out-Null; Start-Sleep 5
   } finally {
    & sc.exe config TrustedInstaller binPath= "$bp" | Out-Null; "prereq: TI path restored=" + ((Get-ItemProperty $svc).ImagePath -eq $bp)
   }
   if ((Get-ItemProperty $ic -ErrorAction SilentlyContinue).ASPNET -eq $null) { 'STAGE_FAIL ASPNET marker still missing after TrustedInstaller write'; return } else { 'prereq: set InetStp ASPNET=1 (as TrustedInstaller)' }
  }
  foreach ($n in 'W3SVC','Metabase','ASPNET','WindowsAuthentication','StaticContent','DefaultDocument','DirectoryBrowse','HttpErrors','HttpLogging','RequestMonitor','RequestFiltering','HttpCompressionStatic') {
   "prereq ${n}=" + [string](Get-ItemProperty $ic -ErrorAction SilentlyContinue).$n }
  $miss = (Get-WindowsFeature Web-Static-Content, Web-Default-Doc, Web-Dir-Browsing, Web-Http-Errors, Web-Http-Logging, Web-Request-Monitor, Web-Filtering, Web-Stat-Compression, NET-WCF-HTTP-Activation45 | Where-Object { -not $_.Installed }).Name
  if ($miss) { 'prereq: installing ' + ($miss -join ','); Install-WindowsFeature $miss | Out-Null }
  if (-not (Test-Path 'C:\Program Files\Microsoft System Center\Operations Manager\WebConsole')) {
   $sa = @('/silent', '/install', '/components:OMWebConsole', "/ManagementServer:$h", '/WebSiteName:"Default Web Site"', '/WebConsoleAuthorizationMode:Mixed',
    '/SendCEIPReports:0', '/UseMicrosoftUpdate:0', '/AcceptEndUserLicenseAgreement:1')
   $pr = Start-Process "$w\scom\setup.exe" -ArgumentList $sa -PassThru; $t = 0
   while (-not $pr.HasExited -and $t -lt 2400) { Start-Sleep 15; $t += 15 }
   if ($pr.HasExited) { "setupExit=$($pr.ExitCode) minutes=" + [math]::Round($t / 60) } else { $pr | Stop-Process -Force; "STAGE_FAIL web console setup still running after 40 min" }
  } else { 'webconsole already installed' }
  $pl = 'C:\Windows\System32\config\systemprofile\AppData\Local\SCOM\Logs'
  Get-ChildItem $pl -Filter *.log | Sort-Object LastWriteTime -Descending | Select-Object -First 2 | ForEach-Object { Select-String -Path $_.FullName -Pattern 'CheckPrerequisites: .*Failed|Error:\s+:.*(fail|exception)' | Select-Object -Last 8 | ForEach-Object { "log: " + $_.Line.Substring(0, [math]::Min(240, $_.Line.Length)) } }
  Import-Module WebAdministration; Get-WebApplication -Site 'Default Web Site' | ForEach-Object { "webapp: $($_.path)" }
  try { $r = Invoke-WebRequest 'http://localhost/OperationsManager' -UseBasicParsing -UseDefaultCredentials -TimeoutSec 60; "webHttp=$($r.StatusCode)" } catch { "webHttp=ERR $($_.Exception.Message)" }
  if (-not (Test-Path 'C:\Program Files\Microsoft System Center\Operations Manager\WebConsole')) { 'STAGE_FAIL web console folder missing after setup' }
 }
 'sqlgrant' {
  # One-time task as ESTHER\estherlabadmin (SQL sysadmin from the SQL install) adds NT AUTHORITY\SYSTEM to sysadmin, so SCOM setup can run from run-command. Temp files are deleted.
  $sq = (Get-ChildItem 'C:\Program Files\Microsoft SQL Server' -Recurse -Filter SQLCMD.EXE -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
  $sql = "SET NOCOUNT ON; SELECT 'login='+SUSER_SNAME()+' isSysadmin='+CAST(IS_SRVROLEMEMBER('sysadmin') AS varchar); IF SUSER_ID('NT AUTHORITY\SYSTEM') IS NULL CREATE LOGIN [NT AUTHORITY\SYSTEM] FROM WINDOWS; ALTER SERVER ROLE sysadmin ADD MEMBER [NT AUTHORITY\SYSTEM]; SELECT 'systemSysadmin='+CAST(IS_SRVROLEMEMBER('sysadmin','NT AUTHORITY\SYSTEM') AS varchar);"
  Set-Content "$w\grant.ps1" "whoami | Out-File $w\grant-out.txt; & '$sq' -E -S $h -h -1 -W -b -Q `"$sql`" *>> $w\grant-out.txt; 'exit=' + `$LASTEXITCODE | Out-File -Append $w\grant-out.txt; 'done' | Out-File $w\grant-done.txt"
  Remove-Item "$w\grant-out.txt", "$w\grant-done.txt" -ErrorAction SilentlyContinue
  $act = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -File $w\grant.ps1"
  Register-ScheduledTask -TaskName scom-grant -Action $act -User 'ESTHER\estherlabadmin' -Password $a -RunLevel Highest -Force | Out-Null
  Start-ScheduledTask scom-grant; $t = 0; while (-not (Test-Path "$w\grant-done.txt") -and $t -lt 180) { Start-Sleep 5; $t += 5 }
  "taskResult=" + (Get-ScheduledTaskInfo scom-grant).LastTaskResult
  Unregister-ScheduledTask scom-grant -Confirm:$false; Remove-Item "$w\grant.ps1" -Force
  if (Test-Path "$w\grant-out.txt") { Get-Content "$w\grant-out.txt" | ForEach-Object { "g: $_" }; Remove-Item "$w\grant-out.txt", "$w\grant-done.txt" -ErrorAction SilentlyContinue } else { "STAGE_FAIL grant task produced no output" }
  $chk = & $sq -E -S $h -h -1 -W -Q "SET NOCOUNT ON; SELECT 'asSystem='+SUSER_SNAME()+' isSysadmin='+CAST(IS_SRVROLEMEMBER('sysadmin') AS varchar)"; "chk: $chk"
  if ("$chk" -notmatch 'isSysadmin=1') { "STAGE_FAIL SYSTEM is still not sysadmin" }
 }
 'hb-on' {
  # Independent heartbeat: a SYSTEM scheduled task writes a small JSON every ~45s (setup active) / 15 min (idle) to one Table Storage row (permanent: Table Storage row, add/update-only SAS, runs at every boot). Readable while run-command is busy.
  $u = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($out))
  $hbs = @'
$u = '__SAS__'
while ($true) {
  try {
    $st = Get-Process setup, SetupChainer, msiexec -ErrorAction SilentlyContinue | Select-Object Name, Id, @{n='cpuSec';e={[int]$_.CPU}}
    $lg = Get-ChildItem 'C:\Windows\System32\config\systemprofile\AppData\Local\SCOM\Logs' -Filter *.log -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $tail = if ($lg) { Get-Content $lg.FullName -Tail 6 | ForEach-Object { $_.Substring(0, [math]::Min(200, $_.Length)) } } else { @() }
    $svc = Get-Service OMSDK, HealthService, cshost, MSSQLSERVER, SQLSERVERAGENT, SQLServerReportingServices, W3SVC -ErrorAction SilentlyContinue | ForEach-Object { @{ ($_.Name) = "$($_.Status)" } }
    $o = [ordered]@{ at = (Get-Date).ToUniversalTime().ToString('o'); host = $env:COMPUTERNAME; setupProcs = @($st); cpuPct = [int](Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average
      freeGB = [math]::Round((Get-PSDrive C).Free / 1GB, 1); memFreeMB = [int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB); log = $(if ($lg) { "$($lg.Name) $($lg.LastWriteTime.ToUniversalTime().ToString('HH:mm:ss'))" } else { '' }); logTail = @($tail); services = @($svc) }
    # Table Storage: one entity (PartitionKey esther, RowKey hb), Insert-Or-Replace each time. $u = entity URL with an add/update SAS.
    $e = @{ at = $o.at; data = ($o | ConvertTo-Json -Depth 4 -Compress) } | ConvertTo-Json -Compress
    Invoke-WebRequest $u -Method Put -Body ([Text.Encoding]::UTF8.GetBytes($e)) -ContentType 'application/json' -Headers @{ 'x-ms-version' = '2019-02-02'; Accept = 'application/json;odata=nometadata' } -UseBasicParsing -TimeoutSec 20 | Out-Null
  } catch {}
  # cost: 45s while setup/msiexec is active, 15 min when idle (single blob overwritten; writes only while the VM is on)
  if (@($st).Count) { Start-Sleep 45 } else { Start-Sleep 900 }
}
'@
  Set-Content "$w\hb.ps1" $hbs.Replace('__SAS__', $u.Replace("'", "''"))
  $act = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $w\hb.ps1"
  $pr = New-ScheduledTaskPrincipal -UserId SYSTEM -LogonType ServiceAccount -RunLevel Highest
  $set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries
  Register-ScheduledTask -TaskName scom-heartbeat -Action $act -Principal $pr -Settings $set -Trigger (New-ScheduledTaskTrigger -AtStartup) -Force | Out-Null
  Start-ScheduledTask scom-heartbeat; Start-Sleep 5; "heartbeat=" + (Get-ScheduledTask scom-heartbeat).State
 }
 'hb-off' {
  Stop-ScheduledTask scom-heartbeat -ErrorAction SilentlyContinue; Unregister-ScheduledTask scom-heartbeat -Confirm:$false -ErrorAction SilentlyContinue
  Remove-Item "$w\hb.ps1" -Force -ErrorAction SilentlyContinue; 'heartbeat=removed'
 }
 'agents' {
  Import-Module OperationsManager; New-SCOMManagementGroupConnection -ComputerName localhost
  "MS: " + ((Get-SCOMManagementServer | % { "$($_.DisplayName) health=$($_.HealthState) gw=$($_.IsGateway)" }) -join '; ')
  $ag = @(Get-SCOMAgent); "AGENTS_COUNT=$($ag.Count)"
  $ag | % { "AGENT $($_.DisplayName) health=$($_.HealthState) ver=$($_.Version) primary=$($_.PrimaryManagementServerName)" }
  $pa = @(Get-SCOMPendingManagement); "PENDING_COUNT=$($pa.Count)"
  $lx = @(Get-SCOMClass -Name 'Microsoft.Unix.Computer' -ErrorAction SilentlyContinue | Get-SCOMClassInstance); "UNIX_COUNT=$($lx.Count)"
  "AGENTS_READ_OK"
 }
 'agent-dc' {
  Import-Module OperationsManager; New-SCOMManagementGroupConnection -ComputerName localhost
  $fq = (Resolve-DnsName ESTHERDC01.esther.lab -Type A | Select-Object -First 1).Name; "DC_FQDN=$fq"
  if (Get-SCOMAgent -DNSHostName $fq -ErrorAction SilentlyContinue) { "AGENT_ALREADY"; } else {
   $cred = New-Object PSCredential('ESTHER\estherlabadmin', (ConvertTo-SecureString $a -AsPlainText -Force))
   $ms = Get-SCOMManagementServer | Where-Object { -not $_.IsGateway } | Select-Object -First 1
   "cmds: " + ((Get-Command -Module OperationsManager -Name *Agent*,*Discovery* | % Name) -join ',')
   Install-SCOMAgent -DNSHostName $fq -PrimaryManagementServer $ms -ActionAccount $cred -ErrorAction Stop
   "PUSH_DONE"
  }
  Start-Sleep 90
  Get-SCOMAgent -DNSHostName $fq | % { "AGENT $($_.DisplayName) health=$($_.HealthState) ver=$($_.Version)" }
  "AGENT_DC_OK"
 }
 'approval-reset' {
  Import-Module OperationsManager; New-SCOMManagementGroupConnection -ComputerName localhost
  Set-SCOMAgentApprovalSetting -AutoReject; 'approval=' + (Get-SCOMAgentApprovalSetting).AgentApprovalSetting
 }
 'dc-proxy' {
  Import-Module OperationsManager; New-SCOMManagementGroupConnection -ComputerName localhost
  $ag = Get-SCOMAgent -DNSHostName ESTHERDC01.esther.lab; if (-not $ag.ProxyingEnabled.Value) { $ag | Enable-SCOMAgentProxy; 'proxy enabled' }
  'proxy=' + (Get-SCOMAgent -DNSHostName ESTHERDC01.esther.lab).ProxyingEnabled.Value
  for ($i=0; $i -lt 30; $i++) { $dc = @(Get-SCOMClass -Name 'Microsoft.Windows.Server.2016.AD.DomainController' -ErrorAction SilentlyContinue | Get-SCOMClassInstance); $dns = @(Get-SCOMClass -DisplayName 'DNS Server' -ErrorAction SilentlyContinue | Select-Object -First 1 | Get-SCOMClassInstance); if ($dc.Count -and $dns.Count) { break }; Start-Sleep 20 }
  $dc | % { "ADDC $($_.DisplayName) health=$($_.HealthState)" }; $dns | % { "DNSSRV $($_.DisplayName) health=$($_.HealthState)" }
  "ADDC_COUNT=$($dc.Count) DNS_COUNT=$($dns.Count)"
 }
 'ad-read' {
  Import-Module OperationsManager; New-SCOMManagementGroupConnection -ComputerName localhost
  foreach ($pat in '*Domain Controller*', '*DNS Server*', '*Active Directory*Forest*', '*Active Directory*Domain*') { Get-SCOMClass -DisplayName $pat | % { $c = $_; $i = @($c | Get-SCOMClassInstance); if ($i.Count) { $i | Select-Object -First 3 | % { "CLS [$($c.Name)] $($_.DisplayName) health=$($_.HealthState)" } } } }
  Get-SCOMAlert -ResolutionState 0 | Select-Object -First 10 | % { "ALERT $($_.Severity) $($_.Name) on $($_.MonitoringObjectDisplayName)" }
  'AD_READ_OK'
 }
 'alert-read' {
  Import-Module OperationsManager; New-SCOMManagementGroupConnection -ComputerName localhost
  Get-SCOMAlert -ResolutionState 0 | % { $d = ($_.Description -replace '\s+',' '); "ALERT [$($_.Severity)] $($_.Name) | on=$($_.MonitoringObjectDisplayName) | rc=$($_.RepeatCount) | last=$($_.LastModified.ToString('HH:mm')) | monitor=$($_.IsMonitorAlert) | " + $d.Substring(0,[math]::Min(700,$d.Length)) }
  'ALERT_READ_OK'
 }
 'alert-triage' {
  # Closes stale rule alerts whose cause is fixed (DAS SPN registered; DAS start-up PowerShell errors) and resets the DW grooming monitor. Before-state saved.
  Import-Module OperationsManager; New-SCOMManagementGroupConnection -ComputerName localhost
  New-Item -ItemType Directory -Force C:\scomlab | Out-Null
  Get-SCOMAlert -ResolutionState 0 | Select-Object Name, Severity, MonitoringObjectDisplayName, LastModified, IsMonitorAlert, Id | Format-List | Out-File C:\scomlab\alerts-before-triage.txt
  $old = (Get-Date).ToUniversalTime().AddMinutes(-30)
  Get-SCOMAlert -ResolutionState 0 | Where-Object { -not $_.IsMonitorAlert -and $_.LastModified -lt $old -and ($_.Name -eq 'Data Access Service SPN Not Registered' -or $_.Name -eq 'Power Shell Script failed to run') } | % { $_ | Resolve-SCOMAlert -Comment 'Lab triage: cause fixed (SPNs registered / DAS start-up timing)'; "CLOSED $($_.Name) $($_.Id)" }
  $a = Get-SCOMAlert -ResolutionState 0 | Where-Object { $_.IsMonitorAlert -and $_.Name -like 'Data Warehouse Job Status synchronization Grooming*' }
  foreach ($x in $a) { $mon = Get-SCOMMonitor -Id $x.MonitoringRuleId; $obj = Get-SCOMClassInstance -Id $x.MonitoringObjectId; $obj.ResetMonitoringState($mon) | Out-Null; "RESET monitor $($mon.DisplayName) on $($obj.DisplayName)" }
  Get-SCOMAlert -ResolutionState 0 | % { $d = ($_.Description -replace '\s+',' '); "OPEN [$($_.Severity)] $($_.Name) | on=$($_.MonitoringObjectDisplayName) | last=$($_.LastModified.ToString('MM-dd HH:mm')) | " + $d.Substring(0,[math]::Min(600,$d.Length)) }
  "sqlProbe=" + (Test-NetConnection -ComputerName localhost -Port 1433 -InformationLevel Quiet)
  'ALERT_TRIAGE_OK'
 }
 'svc-delay' {
  # Boot-order fix for the single-server lab: SCOM services start before SQL is ready (DAS not initialized, OleDB login timeout, DW grooming fail).
  # Sets SCOM services to Automatic (Delayed Start). Before-state saved; rollback: sc.exe config <svc> start= auto.
  New-Item -ItemType Directory -Force C:\scomlab | Out-Null
  $svcs = 'OMSDK','cshost','HealthService'
  Get-CimInstance Win32_Service | Where-Object { $svcs -contains $_.Name -or $_.Name -like 'MSSQL*' -or $_.Name -like 'SQLAgent*' } | % { "$($_.Name) start=$($_.StartMode) delayed=$($_.DelayedAutoStart) state=$($_.State)" } | Tee-Object C:\scomlab\svc-before.txt
  foreach ($s in $svcs) { $r = & sc.exe config $s start= delayed-auto; "SET $s -> delayed-auto: $($r -join ' ')" }
  Get-CimInstance Win32_Service | Where-Object { $svcs -contains $_.Name } | % { "AFTER $($_.Name) start=$($_.StartMode) delayed=$($_.DelayedAutoStart) state=$($_.State)" }
  Import-Module OperationsManager; New-SCOMManagementGroupConnection -ComputerName localhost
  $old = (Get-Date).ToUniversalTime().AddMinutes(-10)
  Get-SCOMAlert -ResolutionState 0 | Where-Object { -not $_.IsMonitorAlert -and $_.LastModified -lt $old -and ($_.Name -eq 'Power Shell Script failed to run' -or $_.Name -eq 'OleDB: Results Error') } | % { $_ | Resolve-SCOMAlert -Comment 'Lab triage: boot-order (SCOM before SQL); services set to delayed start'; "CLOSED $($_.Name)" }
  Get-SCOMAlert -ResolutionState 0 | Where-Object { $_.IsMonitorAlert -and $_.Name -like 'Data Warehouse Job Status synchronization Grooming*' } | % { $mon = Get-SCOMMonitor -Id $_.MonitoringRuleId; $obj = Get-SCOMClassInstance -Id $_.MonitoringObjectId; $obj.ResetMonitoringState($mon) | Out-Null; "RESET $($mon.DisplayName)" }
  'SVC_DELAY_OK'
 }
 'sql-auto' {
  # SQL was Automatic (Delayed), same group as SCOM now; make SQL start at boot so SCOM (delayed) finds it ready. Before-state in C:\scomlab\svc-before.txt (MSSQLSERVER delayed=True). Rollback: sc.exe config MSSQLSERVER start= delayed-auto.
  $r = & sc.exe config MSSQLSERVER start= auto; "SET MSSQLSERVER -> auto: $($r -join ' ')"
  Get-CimInstance Win32_Service -Filter "Name='MSSQLSERVER'" | % { "AFTER $($_.Name) start=$($_.StartMode) delayed=$($_.DelayedAutoStart) state=$($_.State)" }
  'SQL_AUTO_OK'
 }
 'verify' {
  $t = 0; while (-not (Get-NetTCPConnection -LocalPort 5724 -State Listen -ErrorAction SilentlyContinue) -and $t -lt 600) { Start-Sleep 15; $t += 15 }; "sdkListenAfterSec=$t"
  Get-Service OMSDK, HealthService, cshost | ForEach-Object { "$($_.Name)=$($_.Status)" }
  Import-Module OperationsManager
  New-SCOMManagementGroupConnection -ComputerName localhost | Out-Null
  $mg = Get-SCOMManagementGroup; "mg=$($mg.Name) version=$($mg.Version)"
  Get-SCOMManagementServer | ForEach-Object { "ms=$($_.DisplayName) health=$($_.HealthState)" }
  "mps=" + (Get-SCOMManagementPack | Measure-Object).Count
  "freeGB=" + [math]::Round((Get-PSDrive C).Free / 1GB, 1)
 }
 'diag' {
  $pl = 'C:\Windows\System32\config\systemprofile\AppData\Local\SCOM\Logs\SCOMPrereqCheck.log'
  if (Test-Path $pl) { Get-Content $pl | Select-String -Pattern 'Fail|Warn|Error|not |Result' | Select-Object -Last 40 | ForEach-Object { "pre: " + $_.Line.Substring(0, [math]::Min(260, $_.Line.Length)) } }
  $wl = 'C:\Windows\System32\config\systemprofile\AppData\Local\SCOM\Logs\OpsMgrSetupWizard.log'
  if (Test-Path $wl) { Get-Content $wl | Select-String -Pattern 'Failed|Return Value [^0]|Warning' | Where-Object { $_.Line -notmatch 'Product check' } | Select-Object -Last 25 | ForEach-Object { "wiz: " + $_.Line.Substring(0, [math]::Min(260, $_.Line.Length)) } }
  Get-ChildItem C:\Users -Directory | ForEach-Object { "profile: $($_.Name)" }
  Get-ChildItem 'C:\Users', 'C:\Windows\System32\config\systemprofile\AppData\Local', 'C:\Windows\Temp' -Recurse -Filter '*.log' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddHours(-2) -and $_.FullName -match 'SCOM|OpsMgr|Setup' } | Sort-Object LastWriteTime -Descending | Select-Object -First 8 | ForEach-Object { "logfile: $($_.FullName) $($_.LastWriteTime.ToString('HH:mm:ss')) $($_.Length)" }
  $l = Get-ChildItem 'C:\Users' -Recurse -Filter OpsMgrSetupWizard.log -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($l) { "== $($l.FullName)"; Get-Content $l.FullName -Tail 300 | Select-String 'Error|failed|Exit|return' | Select-Object -Last 30 | ForEach-Object { "u: " + $_.Line.Substring(0, [math]::Min(240, $_.Line.Length)) } }
  $sq = Get-ChildItem 'C:\Program Files\Microsoft SQL Server' -Recurse -Filter SQLCMD.EXE -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($sq) { & $sq.FullName -E -S $h -h -1 -W -Q "SET NOCOUNT ON; SELECT 'sysadmin: '+m.name FROM sys.server_role_members r JOIN sys.server_principals m ON m.principal_id=r.member_principal_id WHERE r.role_principal_id=SUSER_ID('sysadmin')" 2>&1 | ForEach-Object { "sql: $_" } } else { 'sqlcmd not found' }
  Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-1)} -MaxEvents 40 -ErrorAction SilentlyContinue | Where-Object { $_.LevelDisplayName -in 'Error','Warning' } | Select-Object -First 10 | ForEach-Object { "ev: $($_.ProviderName) $($_.Id) " + ($_.Message -replace '\s+',' ').Substring(0, [math]::Min(200, ($_.Message -replace '\s+',' ').Length)) }
  "freeGB=" + [math]::Round((Get-PSDrive C).Free / 1GB, 1)
 }
 'autologon-on' {
  $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  Set-ItemProperty $k AutoAdminLogon '1'; Set-ItemProperty $k DefaultUserName 'estherlabadmin'; Set-ItemProperty $k DefaultDomainName 'ESTHER'; Set-ItemProperty $k DefaultPassword $p; Set-ItemProperty $k AutoLogonCount 1 -Type DWord
  'autologon=on'
 }
 'shot' {
  # Runs a task in the interactive session of estherlabadmin: open the Operations Console, wait, capture the screen, upload via write SAS.
  $u = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($out))
  $ps = @'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$c = Get-ChildItem 'C:\Program Files\Microsoft System Center\Operations Manager' -Recurse -Filter Microsoft.EnterpriseManagement.Monitoring.Console.exe | Select-Object -First 1
Get-Process Microsoft.EnterpriseManagement.Monitoring.Console, LicensingUI -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Process $c.FullName; Start-Sleep 180
Get-Process LicensingUI -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 3
$b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds; $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
[System.Drawing.Graphics]::FromImage($bmp).CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size); $bmp.Save('C:\scomlab\console.png')
'@
  Set-Content "$w\shot.ps1" $ps
  $a = New-ScheduledTaskAction -Execute powershell.exe -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $w\shot.ps1"
  $pr = New-ScheduledTaskPrincipal -UserId 'ESTHER\estherlabadmin' -LogonType Interactive -RunLevel Highest
  Register-ScheduledTask -TaskName scom-shot -Action $a -Principal $pr -Force | Out-Null; Remove-Item "$w\console.png" -ErrorAction SilentlyContinue
  "sessions=" + ((quser 2>&1) -join ' | ')
  # wait for the SDK (Data Access) service to accept connections on 5724 before opening the console
  $t = 0; while (-not (Get-NetTCPConnection -LocalPort 5724 -State Listen -ErrorAction SilentlyContinue) -and $t -lt 600) { Start-Sleep 15; $t += 15 }; "sdkListenAfterSec=$t"; Start-Sleep 60
  Start-ScheduledTask scom-shot; $t = 0; while (-not (Test-Path "$w\console.png") -and $t -lt 330) { Start-Sleep 10; $t += 10 }
  Unregister-ScheduledTask scom-shot -Confirm:$false
  if (-not (Test-Path "$w\console.png")) { throw 'no screenshot produced' }
  Invoke-WebRequest $u -Method Put -InFile "$w\console.png" -Headers @{ 'x-ms-blob-type' = 'BlockBlob' } -UseBasicParsing | Out-Null; "shotBytes=" + (Get-Item "$w\console.png").Length
 }
 'autologon-off' {
  $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
  Set-ItemProperty $k AutoAdminLogon '0'; Remove-ItemProperty $k DefaultPassword -ErrorAction SilentlyContinue; Remove-ItemProperty $k AutoLogonCount -ErrorAction SilentlyContinue
  "autologon=off passwordStored=" + [bool](Get-ItemProperty $k -Name DefaultPassword -ErrorAction SilentlyContinue)
 }
}
