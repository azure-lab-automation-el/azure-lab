param($stage, $p, $iso, $ssrs)
# SQL Server 2022 Developer (free, dev/test) + Full-Text + SSRS native mode, for SCOM 2025. Runs as SYSTEM through run-command.
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
trap { "STAGE_FAIL $stage : $($_.Exception.Message)"; exit 1 }
$sq = Get-ChildItem 'C:\Program Files\Microsoft SQL Server' -Recurse -Filter sqlcmd.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if ($sq) { Set-Alias sqlcmd $sq }
# SAS URLs arrive base64-encoded (run-command passes parameters through cmd, which splits on &).
if ($iso) { $iso = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($iso)) }
if ($ssrs) { $ssrs = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ssrs)) }
$w = 'C:\scomlab'; New-Item -ItemType Directory -Force $w, "$w\logs" | Out-Null
switch ($stage) {
 'download' {
  # Media comes from a same-region Storage blob (short-lived SAS URLs); Esther has no internet.
  if (-not (Test-Path "$w\sqlsetup\setup.exe")) {
   Invoke-WebRequest $iso -OutFile "$w\SQL2022-Dev.iso" -UseBasicParsing
   $img = Mount-DiskImage -ImagePath "$w\SQL2022-Dev.iso" -PassThru; $dl = ($img | Get-Volume).DriveLetter
   New-Item -ItemType Directory -Force "$w\sqlsetup" | Out-Null; Copy-Item "${dl}:\*" "$w\sqlsetup" -Recurse -Force
   Dismount-DiskImage -ImagePath "$w\SQL2022-Dev.iso" | Out-Null; Remove-Item "$w\SQL2022-Dev.iso" -Force
  }
  if (-not (Test-Path "$w\SQLServerReportingServices.exe")) { Invoke-WebRequest $ssrs -OutFile "$w\SQLServerReportingServices.exe" -UseBasicParsing }
  "setup=" + (Test-Path "$w\sqlsetup\setup.exe"); "ssrs=" + (Get-Item "$w\SQLServerReportingServices.exe").Length
  "freeGB=" + [math]::Round((Get-PSDrive C).Free / 1GB, 1)
 }
 'install' {
  if (-not (Get-Service MSSQLSERVER -ErrorAction SilentlyContinue)) {
   $a = @('/Q', '/ACTION=Install', '/FEATURES=SQLENGINE,FULLTEXT', '/INSTANCENAME=MSSQLSERVER', '/IACCEPTSQLSERVERLICENSETERMS',
     '/SQLSVCACCOUNT=ESTHER\svc-sql', "/SQLSVCPASSWORD=$p", '/AGTSVCACCOUNT=ESTHER\svc-sql', "/AGTSVCPASSWORD=$p", '/AGTSVCSTARTUPTYPE=Automatic',
     '/SQLSYSADMINACCOUNTS="ESTHER\SCOM-Admins" "ESTHER\estherlabadmin"', '/SQLCOLLATION=SQL_Latin1_General_CP1_CI_AS', '/TCPENABLED=1',
     '/UPDATEENABLED=False', '/SQLMAXMEMORY=3072', '/USESQLRECOMMENDEDMEMORYLIMITS=False')
   $pr = Start-Process "$w\sqlsetup\setup.exe" -ArgumentList $a -Wait -PassThru; "setupExit=$($pr.ExitCode)"
  }
  Get-Service MSSQLSERVER, SQLSERVERAGENT, MSSQLFDLauncher | ForEach-Object { "$($_.Name)=$($_.Status)" }
 }
 'ssrs' {
  if (-not (Get-Service SQLServerReportingServices -ErrorAction SilentlyContinue)) {
   $pr = Start-Process "$w\SQLServerReportingServices.exe" -ArgumentList '/quiet', '/norestart', '/IAcceptLicenseTerms', '/Edition=Dev', "/log $w\logs\ssrs.log" -Wait -PassThru; "ssrsExit=$($pr.ExitCode)"
  }
  (Get-Service SQLServerReportingServices).Status
 }
 'ssrsconfig' {
  $ns = 'root\Microsoft\SqlServer\ReportServer\RS_SSRS\v16\Admin'
  $c = Get-CimInstance -Namespace $ns -ClassName MSReportServer_ConfigurationSetting
  if (-not $c.DatabaseName) {
   $s = (Invoke-CimMethod -InputObject $c -MethodName GenerateDatabaseCreationScript -Arguments @{DatabaseName = 'ReportServer'; Lcid = 1033; IsSharePointMode = $false }).Script
   $s | Out-File "$w\rsdb.sql"; & sqlcmd -S localhost -E -i "$w\rsdb.sql" | Out-Null
   $r = (Invoke-CimMethod -InputObject $c -MethodName GenerateDatabaseRightsScript -Arguments @{UserName = 'NT SERVICE\SQLServerReportingServices'; DatabaseName = 'ReportServer'; IsRemote = $false; IsWindowsUser = $true }).Script
   $r | Out-File "$w\rsrights.sql"; & sqlcmd -S localhost -E -i "$w\rsrights.sql" | Out-Null
   Invoke-CimMethod -InputObject $c -MethodName SetDatabaseConnection -Arguments @{Server = 'localhost'; DatabaseName = 'ReportServer'; CredentialsType = 2; UserName = ''; Password = '' } | Out-Null
   Invoke-CimMethod -InputObject $c -MethodName SetVirtualDirectory -Arguments @{Application = 'ReportServerWebService'; VirtualDirectory = 'ReportServer'; Lcid = 1033 } | Out-Null
   Invoke-CimMethod -InputObject $c -MethodName ReserveURL -Arguments @{Application = 'ReportServerWebService'; UrlString = 'http://+:80'; Lcid = 1033 } | Out-Null
   Invoke-CimMethod -InputObject $c -MethodName SetVirtualDirectory -Arguments @{Application = 'ReportServerWebApp'; VirtualDirectory = 'Reports'; Lcid = 1033 } | Out-Null
   Invoke-CimMethod -InputObject $c -MethodName ReserveURL -Arguments @{Application = 'ReportServerWebApp'; UrlString = 'http://+:80'; Lcid = 1033 } | Out-Null
   Invoke-CimMethod -InputObject $c -MethodName SetServiceState -Arguments @{EnableWindowsService = $false; EnableWebService = $false; EnableReportManager = $false } | Out-Null
   Invoke-CimMethod -InputObject $c -MethodName SetServiceState -Arguments @{EnableWindowsService = $true; EnableWebService = $true; EnableReportManager = $true } | Out-Null
  }
  $c = Get-CimInstance -Namespace $ns -ClassName MSReportServer_ConfigurationSetting
  "rsdb=$($c.DatabaseName) initialized=$($c.IsInitialized) svc=$((Get-Service SQLServerReportingServices).Status)"
  try { "reportserverHttp=" + (Invoke-WebRequest http://localhost/ReportServer -UseDefaultCredentials -UseBasicParsing).StatusCode } catch { "reportserverHttp=" + $_.Exception.Message }
 }
 'rsfix' {
  # After the SSRS reboot (3010): restart the service and confirm the report server is initialized and answering.
  Restart-Service SQLServerReportingServices -Force; Start-Sleep 45
  $ns = 'root\Microsoft\SqlServer\ReportServer\RS_SSRS\v16\Admin'; $c = Get-CimInstance -Namespace $ns -ClassName MSReportServer_ConfigurationSetting
  $u = Invoke-CimMethod -InputObject $c -MethodName ListReservedUrls; for ($i = 0; $i -lt $u.Application.Count; $i++) { "url=$($u.Application[$i]) $($u.UrlString[$i])" }
  "rsdb=$($c.DatabaseName) initialized=$($c.IsInitialized)"
  foreach ($p2 in 'ReportServer', 'Reports') { try { "http_$p2=" + (Invoke-WebRequest "http://localhost/$p2" -UseDefaultCredentials -UseBasicParsing -TimeoutSec 60).StatusCode } catch { "http_$p2=" + $_.Exception.Message } }
 }
 'verify' {
  $q = "SELECT SERVERPROPERTY('ProductVersion') v, SERVERPROPERTY('ProductUpdateLevel') cu, SERVERPROPERTY('Edition') e, SERVERPROPERTY('Collation') c, FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') fts"
  & sqlcmd -S localhost -E -Q "SET NOCOUNT ON; $q" -W -s '|'
  Get-Service MSSQLSERVER, SQLSERVERAGENT, MSSQLFDLauncher, SQLServerReportingServices | ForEach-Object { "$($_.Name)=$($_.Status)" }
  "freeGB=" + [math]::Round((Get-PSDrive C).Free / 1GB, 1)
 }
 'cleanup' {
  # Free space after SQL: drop copied setup media and installers, temp, and superseded Windows components.
  $before = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
  Remove-Item "$w\sqlsetup", "$w\SQL2022-Dev.iso", "$w\SQLServerReportingServices.exe" -Recurse -Force -ErrorAction SilentlyContinue
  Get-ChildItem $env:TEMP, 'C:\Windows\Temp' -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  Start-Process dism.exe -ArgumentList '/Online', '/Cleanup-Image', '/StartComponentCleanup' -Wait -NoNewWindow
  $after = [math]::Round((Get-PSDrive C).Free / 1GB, 2)
  "freeBefore=$before"; "freeAfter=$after"
  Get-ChildItem 'C:\' -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { $sz = (Get-ChildItem $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum; '{0}={1:N1}GB' -f $_.Name, ($sz / 1GB) }
 }
}
