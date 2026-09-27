# Runs ON the SCOM server. Read-only inventory of what is configured live, via the SCOM SDK only (no OperationsManager cmdlets:
# one of them prompted and blocked the remote job in run 36041445341). Also exports every unsealed MP as XML, zipped, returned as MPZIP:<base64>.
param([string]$ScxPw, [string]$ScxKeyB64)
$ErrorActionPreference = 'Stop'; $ConfirmPreference = 'None'; $ProgressPreference = 'SilentlyContinue'
$dll = Get-ChildItem 'C:\Program Files\Microsoft System Center\Operations Manager' -Recurse -Filter Microsoft.EnterpriseManagement.OperationsManager.dll -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
$dir = Split-Path $dll
foreach ($n in 'Microsoft.EnterpriseManagement.Core.dll','Microsoft.EnterpriseManagement.Runtime.dll','Microsoft.EnterpriseManagement.OperationsManager.dll') { $f = Join-Path $dir $n; if (Test-Path $f) { [void][Reflection.Assembly]::LoadFrom($f) } }
$mg = [Microsoft.EnterpriseManagement.ManagementGroup]::Connect('localhost')
function Sec($name, [scriptblock]$b) { try { & $b } catch { "ERR $name : $($_.Exception.Message)" } }
$L = & {
Sec mg { "mg=$($mg.Name) version=$($mg.Version)" }
$mps = @($mg.ManagementPacks.GetManagementPacks())
$uns = @($mps | Where-Object { -not $_.Sealed })
"mps_total=$($mps.Count) sealed=$($mps.Count - $uns.Count) unsealed=$($uns.Count)"
foreach ($mp in $uns) { Sec $mp.Name { "unsealed $($mp.Name) | $($mp.DisplayName) | overrides=$(@($mp.GetOverrides()).Count) monitors=$(@($mp.GetMonitors()).Count) rules=$(@($mp.GetRules()).Count) classes=$(@($mp.GetClasses()).Count) views=$(@($mp.GetViews()).Count) | modified=$($mp.LastModified.ToString('yyyy-MM-dd'))" } }
Sec sealed { "sealed_by_family: " + (($mps | Where-Object Sealed | ForEach-Object { ($_.Name -split '\.')[0..1] -join '.' } | Group-Object | Sort-Object Count -Descending | Select-Object -First 12 | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ') }
Sec sealed_extra { "sealed_imported: " + (($mps | Where-Object { $_.Sealed -and $_.Name -notmatch '^(Microsoft\.SystemCenter|System\.|Microsoft\.Windows\.(Server\.Library|Library|Client|Server\.2016)|Microsoft\.Unix|Microsoft\.Linux|Microsoft\.Windows\.InternetInformationServices|Microsoft\.SQLServer|Microsoft\.Windows\.Server\.AD|ODR|Microsoft\.Information|Microsoft\.Web|Microsoft\.Windows\.Cluster|Microsoft\.Windows\.Image|Microsoft\.Windows\.Server\.ClusterSharedVolume)' } | ForEach-Object { "$($_.Name) $($_.Version)" }) -join ', ') }
Sec agents { "agents_windows: " + ((@($mg.Administration.GetAllAgentManagedComputers()) | ForEach-Object { "$($_.PrincipalName)[$($_.HealthState)]" }) -join ', ') }
Sec linux { $c = @($mg.EntityTypes.GetClasses((New-Object Microsoft.EnterpriseManagement.Configuration.ManagementPackClassCriteria("Name = 'Microsoft.Unix.Computer'"))))[0]
  $m = $mg.EntityObjects.GetType().GetMethods() | Where-Object { $_.Name -eq 'GetObjectReader' -and $_.IsGenericMethodDefinition -and ($_.GetParameters().ParameterType.Name -join ',') -eq 'ManagementPackClass,ObjectQueryOptions' } | Select-Object -First 1
  $rd = $m.MakeGenericMethod([Microsoft.EnterpriseManagement.Monitoring.MonitoringObject]).Invoke($mg.EntityObjects, @($c, [Microsoft.EnterpriseManagement.Common.ObjectQueryOptions]::Default))
  "agents_unix: " + ((@($rd) | ForEach-Object { "$($_.DisplayName)[$($_.HealthState)]" }) -join ', ') }
Sec runas { "runas: " + ((@($mg.Security.GetSecureData()) | Where-Object { $_.Name -notmatch '^(Local System|Data Warehouse|Reporting|APM)' } | ForEach-Object { "$($_.Name)[$($_.GetType().Name)]" }) -join ', ') }
Sec module { Import-Module OperationsManager -ErrorAction Stop; "module loaded" }
Sec notif { "subscriptions: " + ((@(Get-SCOMNotificationSubscription) | ForEach-Object { "$($_.DisplayName)[enabled=$($_.Enabled)]" }) -join ', ') }
Sec chan { "channels: " + ((@(Get-SCOMNotificationChannel) | ForEach-Object { $_.DisplayName }) -join ', ') }
Sec alerts { $al = @($mg.OperationalData.GetMonitoringAlerts((New-Object Microsoft.EnterpriseManagement.Monitoring.MonitoringAlertCriteria('ResolutionState = 0')), $null)); "alerts_open=$($al.Count): " + (($al | ForEach-Object { "$($_.Name) @ $($_.MonitoringObjectDisplayName) [$($_.Severity)]" }) -join ' ; ') }
Sec settings { "setting agent_approval=" + (Get-SCOMAgentApprovalSetting).AgentApprovalSetting }
}
$L
Sec export {
  $out = 'C:\scom-export'; if (Test-Path $out) { Remove-Item $out -Recurse -Force }; New-Item -ItemType Directory $out | Out-Null
  $L | Set-Content (Join-Path $out 'inventory.txt') -Encoding UTF8
  $w = New-Object Microsoft.EnterpriseManagement.Configuration.IO.ManagementPackXmlWriter($out)
  foreach ($mp in $uns) { try { [void]$w.WriteManagementPack($mp) } catch { "ERR xmlwriter $($mp.Name): $($_.Exception.Message)" } }
  if (-not (Get-ChildItem $out -Filter *.xml)) { "xmlwriter wrote nothing; using Export-SCOMManagementPack"; Get-SCOMManagementPack | Where-Object { -not $_.Sealed } | Export-SCOMManagementPack -Path $out }
  "exported: " + ((Get-ChildItem $out -Filter *.xml | ForEach-Object { "$($_.Name)=$($_.Length)" }) -join ', ')
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = 'C:\scom-export.zip'; if (Test-Path $zip) { Remove-Item $zip -Force }
  [IO.Compression.ZipFile]::CreateFromDirectory($out, $zip, [IO.Compression.CompressionLevel]::Optimal, $false)
  $b = [IO.File]::ReadAllBytes($zip); "MPZIP_BYTES=$($b.Length) SHA256=" + (Get-FileHash $zip -Algorithm SHA256).Hash
  'MPZIP:' + [Convert]::ToBase64String($b) }
'INVENTORY_DONE'
