# Runs ON the SCOM server. Opens the Operations console in the logged-on admin's console session on the UNIX/Linux computers view,
# so the VM's boot-diagnostics console screenshot shows it. Read-only for SCOM; the helper scheduled task is removed afterwards.
param([string]$ScxPw, [string]$ScxKeyB64)
$ErrorActionPreference = 'Stop'
Import-Module OperationsManager
$mg = Get-SCOMManagementGroup
$views = $mg.Presentation.GetViews() | Where-Object { $_.DisplayName -match 'UNIX/Linux|Linux' }
$views | Select-Object -First 12 | ForEach-Object { "view $($_.Name) | $($_.DisplayName)" }
$v = $views | Where-Object { $_.DisplayName -match 'Computers' -and $_.Name -match 'State' } | Select-Object -First 1
if (-not $v) { $v = $views | Where-Object { $_.DisplayName -match 'Computers' } | Select-Object -First 1 }
"chosen=$($v.Name) | $($v.DisplayName)"
$lin = Get-SCOMClass -Name 'Microsoft.Linux.Computer' | Get-SCOMClassInstance
$lin | ForEach-Object { "linux $($_.DisplayName) health=$($_.HealthState) available=$($_.IsAvailable)" }
$exe = 'C:\Program Files\Microsoft System Center\Operations Manager\Console\Microsoft.EnterpriseManagement.Monitoring.Console.exe'
Get-Process Microsoft.EnterpriseManagement.Monitoring.Console -ErrorAction SilentlyContinue | Where-Object SessionId -eq 1 | Stop-Process -Force -ErrorAction SilentlyContinue
$a = New-ScheduledTaskAction -Execute $exe -Argument ("/ViewName:" + $v.Name)
$p = New-ScheduledTaskPrincipal -UserId 'ESTHER\estherlabadmin' -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'lab-ui-shot' -Action $a -Principal $p -Force | Out-Null
Start-ScheduledTask -TaskName 'lab-ui-shot'
Start-Sleep 70
$cp = Get-Process Microsoft.EnterpriseManagement.Monitoring.Console -ErrorAction SilentlyContinue | Where-Object SessionId -eq 1
"console_running=" + [bool]$cp + " title=" + ($cp | Select-Object -First 1).MainWindowTitle
Unregister-ScheduledTask -TaskName 'lab-ui-shot' -Confirm:$false
"locked=" + [bool](Get-Process LogonUI -ErrorAction SilentlyContinue | Where-Object SessionId -eq 1)
'UI_SHOT_DONE'
