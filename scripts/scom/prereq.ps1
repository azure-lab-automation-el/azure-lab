param($stage, $media)
# SCOM 2025 prerequisites on Esther (management server, console, web console, reporting). Runs as SYSTEM via run-command.
$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'
trap { "STAGE_FAIL $stage : $($_.Exception.Message)"; exit 1 }
$w = 'C:\scomlab'; New-Item -ItemType Directory -Force $w | Out-Null
$iis = 'Web-Server','Web-WebServer','Web-Common-Http','Web-Default-Doc','Web-Dir-Browsing','Web-Http-Errors','Web-Static-Content','Web-Health','Web-Http-Logging','Web-Request-Monitor','Web-Performance','Web-Stat-Compression','Web-Security','Web-Filtering','Web-Windows-Auth','Web-App-Dev','Web-Net-Ext45','Web-Asp-Net45','Web-ISAPI-Ext','Web-ISAPI-Filter','Web-Mgmt-Tools','Web-Mgmt-Console','Web-Mgmt-Compat','Web-Metabase','NET-WCF-HTTP-Activation45'
switch ($stage) {
 'sqlstart' {
  foreach ($n in 'MSSQLSERVER','SQLSERVERAGENT','MSSQLFDLauncher','SQLServerReportingServices','SSRS') { $sv = Get-Service $n -EA 0; if ($sv) { Set-Service $n -StartupType Automatic; if ($sv.Status -ne 'Running') { Start-Service $n -EA SilentlyContinue }; "svc $n=" + (Get-Service $n).Status } }
  Start-Sleep 20; try { "rs http=" + (Invoke-WebRequest http://localhost/ReportServer -UseDefaultCredentials -UseBasicParsing -TimeoutSec 60).StatusCode } catch { "rs err=" + $_.Exception.Message }
  "freeGB=" + [math]::Round((Get-PSDrive C).Free / 1GB, 1)
 }
 'diag' {
  "boot=" + (Get-CimInstance Win32_OperatingSystem).LastBootUpTime; "freeGB=" + [math]::Round((Get-PSDrive C).Free / 1GB, 1)
  Get-Service MSSQLSERVER,SQLSERVERAGENT,SSRS,SQLServerReportingServices,MSSQLFDLauncher,W3SVC -EA 0 | ForEach-Object { "svc $($_.Name)=$($_.Status)/$($_.StartType)" }
  Get-ChildItem "$w\scomzip" -Recurse -Filter setup.exe -EA 0 | Select-Object -First 3 | ForEach-Object { "setup at " + $_.FullName }
  Get-Service -EA 0 | Where-Object { $_.Name -match 'SQL|Report' }  | ForEach-Object { "svc $($_.Name)=$($_.Status)" }
  try { "rs http=" + (Invoke-WebRequest http://localhost/ReportServer -UseDefaultCredentials -UseBasicParsing -TimeoutSec 20).StatusCode } catch { "rs err=" + $_.Exception.Message }
  (Get-WindowsFeature Web-Server,Web-Asp-Net45,Web-Metabase,Web-Windows-Auth | ForEach-Object { "$($_.Name)=$($_.InstallState)" }) -join ' '
  Get-ChildItem $w -EA 0 | ForEach-Object { "{0} {1:N0}MB {2}" -f $_.Name, ($_.Length / 1MB), $_.LastWriteTime }
  foreach ($d in 'scomzip','scom') { if (Test-Path "$w\$d") { "dir $d files=" + (Get-ChildItem "$w\$d" -Recurse -File).Count } }
  Get-ChildItem C:\WindowsAzure\Logs\Plugins\Microsoft.CPlat.Core.RunCommandWindows -Recurse -File -EA 0 | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { "rclog " + $_.FullName; Get-Content $_.FullName -Tail 15 }
 }
 'check' {
  Get-WindowsFeature ($iis + 'NET-Framework-Core','Web-Net-Ext','Web-Asp-Net') | ForEach-Object { "$($_.Name)=$($_.InstallState)" }
  "net4=" + (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').Release
  Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match 'ODBC|OLE DB|Report Viewer|CLR Types' } | ForEach-Object { "pkg=$($_.DisplayName) $($_.DisplayVersion)" }
  "freeGB=" + [math]::Round((Get-PSDrive C).Free / 1GB, 1)
 }
 'iis' {
  $r = Install-WindowsFeature $iis -IncludeManagementTools; "iisSuccess=$($r.Success) restart=$($r.RestartNeeded)"
  Import-Module WebAdministration; Get-WebConfiguration '/system.webServer/security/isapiCgiRestriction/add' | Where-Object { $_.path -match 'Framework64\\v4' } | ForEach-Object { Set-WebConfigurationProperty -Filter "/system.webServer/security/isapiCgiRestriction/add[@path='$($_.path)']" -Name allowed -Value True; "isapiAllowed=$($_.path)" }
 }
 'scomextract' {
  # SCOM_2025.zip staged in the same-region blob; $media is a base64 SAS URL.
  # The staged zip is already the extracted SCOM media (setup.exe inside), not a self-extractor. Use it directly.
  if (-not (Test-Path "$w\scom\setup.exe")) { $st = Get-ChildItem "$w\scomzip" -Recurse -Filter setup.exe -EA 0 | Sort-Object { $_.FullName.Length } | Select-Object -First 1
   if ($st) { "setupFound=$($st.FullName)"; if (Test-Path "$w\scom") { Remove-Item "$w\scom" -Recurse -Force }; Move-Item $st.DirectoryName "$w\scom" } }
  if (-not (Test-Path "$w\scom\setup.exe")) {
   $u = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($media))
   if (-not (Get-ChildItem "$w\scomzip" -Recurse -Filter *.exe -EA 0)) {
    if (-not (Test-Path "$w\SCOM_2025.zip") -or (Get-Item "$w\SCOM_2025.zip").Length -lt 800MB) { $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest $u -OutFile "$w\SCOM_2025.zip" -UseBasicParsing -TimeoutSec 900 }
    "zipMB=" + [math]::Round((Get-Item "$w\SCOM_2025.zip").Length / 1MB)
    Expand-Archive "$w\SCOM_2025.zip" "$w\scomzip" -Force; Remove-Item "$w\SCOM_2025.zip" -Force }
   $exe = Get-ChildItem "$w\scomzip" -Recurse -Filter *.exe | Select-Object -First 1; "selfExtractor=$($exe.Name) MB=$([math]::Round($exe.Length/1MB))"
   # Never wait forever: a hidden prompt in the SYSTEM session would hang run-command. Kill after 10 minutes.
   $p = Start-Process $exe.FullName -ArgumentList '/dir="C:\scomlab\scom"', '/silent' -PassThru
   if (-not $p.WaitForExit(600000)) { $p | Stop-Process -Force; "STAGE_FAIL extractor timed out after 10 min (hidden prompt?)" } else { "extractorExit=$($p.ExitCode)" }
  }
  "setup=" + (Test-Path "$w\scom\setup.exe"); Get-ChildItem "$w\scom" | Select-Object -First 15 | ForEach-Object Name
  "freeGB=" + [math]::Round((Get-PSDrive C).Free / 1GB, 1)
 }
}
