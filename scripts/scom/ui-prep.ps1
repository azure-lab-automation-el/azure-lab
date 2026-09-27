# Runs ON the SCOM server. Read-only: interactive sessions, console path, UNIX/Linux views.
param([string]$ScxPw, [string]$ScxKeyB64)
"sessions:"; (query user 2>&1) | ForEach-Object { "  $_" }
(qwinsta 2>&1) | ForEach-Object { "  qw $_" }
$exe = Get-ChildItem 'C:\Program Files\Microsoft System Center*' -Recurse -Filter Microsoft.EnterpriseManagement.Monitoring.Console.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
"console=$exe"
Import-Module OperationsManager
Get-SCOMView | Where-Object { $_.DisplayName -match 'UNIX|Linux' } | Select-Object -First 15 | ForEach-Object { "view $($_.Name) | $($_.DisplayName)" }
Get-SCXAgent | ForEach-Object { "scx $($_.Name) health=$($_.HealthState)" }
"edge=" + (Test-Path 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe')
'UI_PREP_DONE'
