# Runs ON the DC (esther-dc-01) via run-command; reaches the SCOM server over WinRM so the SCOM server's own run-command slot is never used.
# Mode probe  = read-only: WinRM reachable, admin identity, stuck run-command PowerShell processes on the SCOM server.
# Mode unstick = stop only the hung run-command PowerShell script process(es) on the SCOM server (no restart).
# $Mode and $Pw are defined by the runner-built header (secret in the self-deleting script body, never a command-line parameter).
$ErrorActionPreference = 'Stop'
$c = New-Object System.Management.Automation.PSCredential('ESTHER\estherlabadmin', (ConvertTo-SecureString $Pw -AsPlainText -Force))
# Azure VM esther-adaxes-01 has Windows computer name ESTHERLAB (seen in the heartbeat row).
$t = 'ESTHERLAB.esther.lab'
try { Test-WSMan $t -ErrorAction Stop | Out-Null; 'wsman=ok' } catch { "wsman=FAIL $($_.Exception.Message)"; 'WINRM_FAIL'; exit 0 }
$sb = {
  param($Mode)
  "remote=" + (whoami) + " admin=" + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
  $stuck = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match '-File script\d+\.ps1' }
  foreach ($p in $stuck) { "stuck pid=$($p.ProcessId) started=$($p.CreationDate) cmd=" + ($p.CommandLine -replace '(-File script\d+\.ps1).*','$1 <args redacted>') }
  if (-not $stuck) { 'stuck=none' }
  Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'RunCommand|Packages\\Plugins|scx|Invoke-SCX' -or $_.Name -match 'powershell|pwsh' } | ForEach-Object { "proc pid=$($_.ProcessId) ppid=$($_.ParentProcessId) $($_.Name) started=$($_.CreationDate) cmd=" + ("$($_.CommandLine)" -replace '(script\d+\.ps1).*','$1 <args redacted>') }
  if ($Mode -eq 'unstick') { foreach ($p in $stuck) { Stop-Process -Id $p.ProcessId -Force; "killed $($p.ProcessId)"; Stop-Process -Id $p.ParentProcessId -Force -ErrorAction SilentlyContinue } }
  if ($Mode -eq 'inspect') {
    Import-Module OperationsManager
    $cmd = Get-Command Get-SCXSSHCredential; "impl=" + $cmd.ImplementingType.AssemblyQualifiedName; "out=" + ($cmd.OutputType.Type.FullName -join ',')
    $asm = (Get-Command Invoke-SCXDiscovery).Parameters['SshCredential'].ParameterType.Assembly
    $ns='Microsoft.SystemCenter.CrossPlatform.ClientLibrary.CredentialManagement.Core.'
    foreach ($n in 'CredentialSet','PosixHostCredential') { $t=$asm.GetType($ns+$n); $t.GetMethods() | Where-Object { $_.DeclaringType -eq $t } | ForEach-Object { "$n.$($_.Name)(" + (($_.GetParameters() | ForEach-Object { "$($_.ParameterType.Name) $($_.Name)" }) -join ', ') + ") static=$($_.IsStatic)" } }
    foreach ($n in 'CredentialSetUsage','CredentialUsage') { "$n = " + ([Enum]::GetNames($asm.GetType($ns+$n)) -join ',') }
    (Get-Command Invoke-SCXDiscovery).Parameters['SshCredential'].ParameterType.AssemblyQualifiedName
    (Get-Command Invoke-SCXDiscovery).Parameters['WsManCredential'].ParameterType.FullName
  }
  "scomsvc=" + ((Get-Service HealthService, OMSDK, cshost -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name):$($_.Status)" }) -join ',')
}
$j = Invoke-Command -ComputerName $t -Credential $c -ScriptBlock $sb -ArgumentList $Mode -AsJob
if (Wait-Job $j -Timeout 150) { try { Receive-Job $j -ErrorAction Stop } catch { "REMOTE_ERROR: $($_.Exception.Message)" } } else { 'REMOTE_TIMEOUT'; Stop-Job $j }
"WINRM_$($Mode.ToUpper())_DONE"
