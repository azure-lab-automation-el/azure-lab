# Runs ON the SCOM server. Read-only status: SCOM services, Linux computers health, open alerts.
# Fast path: load only the SCOM SDK assembly and connect directly (skips the 15 s OperationsManager module load). Falls back to the module.
param([string]$ScxPw, [string]$ScxKeyB64)
$ErrorActionPreference = 'Stop'
$sw = [Diagnostics.Stopwatch]::StartNew()
Get-Service HealthService, OMSDK, cshost -ErrorAction SilentlyContinue | ForEach-Object { "svc $($_.Name)=$($_.Status)" }
$mode = 'sdk'
try {
  $dll = Get-ChildItem 'C:\Program Files\Microsoft System Center\Operations Manager' -Recurse -Filter Microsoft.EnterpriseManagement.OperationsManager.dll -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
  $dir = Split-Path $dll
  foreach ($n in 'Microsoft.EnterpriseManagement.Core.dll','Microsoft.EnterpriseManagement.Runtime.dll','Microsoft.EnterpriseManagement.OperationsManager.dll') { $f = Join-Path $dir $n; if (Test-Path $f) { [void][Reflection.Assembly]::LoadFrom($f) } }
  "sdk dir=$dir"
  $mg = [Microsoft.EnterpriseManagement.ManagementGroup]::Connect('localhost')
  "T sdk-connect=" + [math]::Round($sw.Elapsed.TotalSeconds,1) + 's'; $t = $sw.Elapsed.TotalSeconds
  $cls = @($mg.EntityTypes.GetClasses((New-Object Microsoft.EnterpriseManagement.Configuration.ManagementPackClassCriteria("Name = 'Microsoft.Linux.Computer'"))))[0]
  $m = $mg.EntityObjects.GetType().GetMethods() | Where-Object { $_.Name -eq 'GetObjectReader' -and $_.IsGenericMethodDefinition -and ($_.GetParameters().ParameterType.Name -join ',') -eq 'ManagementPackClass,ObjectQueryOptions' } | Select-Object -First 1
  $rd = $m.MakeGenericMethod([Microsoft.EnterpriseManagement.Monitoring.MonitoringObject]).Invoke($mg.EntityObjects, @($cls, [Microsoft.EnterpriseManagement.Common.ObjectQueryOptions]::Default))
  foreach ($o in $rd) { "linux $($o.DisplayName) health=$($o.HealthState) available=$($o.IsAvailable)" }
  $crit = New-Object Microsoft.EnterpriseManagement.Monitoring.MonitoringAlertCriteria('ResolutionState = 0')
  $al = @($mg.OperationalData.GetMonitoringAlerts($crit, $null)); "alerts_open=" + $al.Count
  $al | Select-Object -First 5 | ForEach-Object { "alert [$($_.Severity)] $($_.Name) | $($_.MonitoringObjectDisplayName) | $($_.TimeRaised)" }
} catch {
  $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; "sdk path failed: $($e.Message) -> module fallback"
  if ($e.LoaderExceptions) { $e.LoaderExceptions | Select-Object -First 3 | ForEach-Object { "  loader: $($_.Message)" } }
  $mode = 'module'; $sw.Restart()
  Import-Module OperationsManager
  "T import-module=" + [math]::Round($sw.Elapsed.TotalSeconds,1) + 's'; $t = $sw.Elapsed.TotalSeconds
  Get-SCOMClass -Name 'Microsoft.Linux.Computer' | Get-SCOMClassInstance | ForEach-Object { "linux $($_.DisplayName) health=$($_.HealthState) available=$($_.IsAvailable)" }
  $al = @(Get-SCOMAlert -ResolutionState 0); "alerts_open=" + $al.Count
  $al | Select-Object -First 5 | ForEach-Object { "alert [$($_.Severity)] $($_.Name) | $($_.MonitoringObjectDisplayName) | $($_.TimeRaised)" }
}
"mode=$mode T op=" + [math]::Round($sw.Elapsed.TotalSeconds - $t,1) + 's'
'SCOM_STATUS_DONE'
