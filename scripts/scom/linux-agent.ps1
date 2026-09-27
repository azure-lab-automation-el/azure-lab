# Runs ON the SCOM server. Minimal Linux monitoring: Universal Linux MPs, Run As account, discovery + agent install. No log-file rules.
param([string]$ScxPw, [string]$ScxKeyB64)
$ErrorActionPreference = 'Stop'
$__sw = [Diagnostics.Stopwatch]::StartNew(); $__last = 0
function T([string]$n) { $now = $__sw.Elapsed.TotalSeconds; "T $n=" + [math]::Round($now - $script:__last,1) + 's'; $script:__last = $now }
Import-Module OperationsManager
T 'import-module'
$mpDir = 'C:\scomlab\scom\ManagementPacks'
$want = 'Microsoft.Linux.Library.mp','Microsoft.Linux.Universal.Library.mp','Microsoft.Linux.Universal.Monitoring.mp','Microsoft.Linux.UniversalD.1.mpb','Microsoft.Linux.UniversalR.1.mpb'
$files = $want | ForEach-Object { Join-Path $mpDir $_ } | Where-Object { Test-Path $_ }
$have = (Get-SCOMManagementPack).Name
$todo = $files | Where-Object { ([IO.Path]::GetFileNameWithoutExtension($_)) -notin $have }
foreach ($f in @($want | ForEach-Object { Join-Path $mpDir $_ } | Where-Object { $_ -in $todo })) {
  try { Import-SCOMManagementPack -Fullname $f -ErrorAction Stop; "imported $f" }
  catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; "IMPORT_FAIL $f :: $($e.Message)" } }
Get-SCOMManagementPack | Where-Object Name -match 'Linux' | ForEach-Object { "mp $($_.Name) $($_.Version)" }
T 'mp-check'
Clear-DnsClientCache; "resolve=" + ((Resolve-DnsName esther-linux-01.esther.lab).IPAddress -join ',')
$sec = ConvertTo-SecureString $ScxPw -AsPlainText -Force
$pool = Get-SCOMResourcePool -DisplayName 'All Management Servers Resource Pool'
# Run As accounts (monitoring + privileged), distributed to the pool, bound to the UNIX/Linux profiles
$acctName = 'Linux scxmon monitoring'; $privName = 'Linux scxmon privileged'
$pc = New-Object System.Management.Automation.PSCredential('scxmon', $sec)
$m = Get-SCOMRunAsAccount -Name 'Linux scxmon maintenance' -ErrorAction SilentlyContinue
if (-not $m) { $m = Add-SCOMRunAsAccount -SCXMaintenance -Name 'Linux scxmon maintenance' -Description 'Lab Linux agent maintenance (sudo)' -RunAsCredential $pc -Sudo }
$p = Get-SCOMRunAsAccount -Name $privName -ErrorAction SilentlyContinue
if (-not $p) { $p = Add-SCOMRunAsAccount -SCXMonitoring -Name $privName -Description 'Lab Linux privileged (sudo)' -RunAsCredential $pc -Sudo }
$a = Get-SCOMRunAsAccount -Name $acctName -ErrorAction SilentlyContinue
if (-not $a) { try { $a = Add-SCOMRunAsAccount -SCXMonitoring -Name $acctName -Description 'Lab Linux monitoring' -RunAsCredential $pc -ErrorAction Stop } catch { "nonpriv account: $($_.Exception.Message) -> using privileged account for action profile"; $a = $p } }
$m = Get-SCOMRunAsAccount -Name 'Linux scxmon maintenance'; $p = Get-SCOMRunAsAccount -Name $privName
$a = Get-SCOMRunAsAccount -Name $acctName -ErrorAction SilentlyContinue; if (-not $a) { $a = $p }
$accts = @(@($a,$p,$m) | Where-Object { $_ } | Sort-Object -Property Id -Unique)
foreach ($x in $accts) { Set-SCOMRunAsDistribution -RunAsAccount $x -MoreSecure -SecureDistribution (@($pool) + @(Get-SCOMManagementServer)) }
"distribution: " + (($accts | ForEach-Object { $_.Name + " -> " + ((Get-SCOMRunAsDistribution -RunAsAccount $_).SecureDistribution.DisplayName -join "|") }) -join "; ")
try { Set-SCOMRunAsProfile -Action Add -Profile (Get-SCOMRunAsProfile -DisplayName 'UNIX/Linux Action Account') -Account $a -ErrorAction Stop } catch { if ($_.Exception.Message -notmatch 'already exists') { throw } }
try { Set-SCOMRunAsProfile -Action Add -Profile (Get-SCOMRunAsProfile -DisplayName 'UNIX/Linux Privileged Account') -Account $p -ErrorAction Stop } catch { if ($_.Exception.Message -notmatch 'already exists') { throw } }
try { Set-SCOMRunAsProfile -Action Add -Profile (Get-SCOMRunAsProfile -DisplayName 'UNIX/Linux Agent Maintenance Account') -Account $m -ErrorAction Stop } catch { if ($_.Exception.Message -notmatch 'already exists') { throw } }
T 'runas-setup'
"runas: " + ((Get-SCOMRunAsAccount | Where-Object Name -like 'Linux scxmon*').Name -join ', ')
# Discovery + install
$installed = $false
$existing = Get-SCXAgent | Where-Object Name -eq 'esther-linux-01.esther.lab'
if (-not $existing) {
  # Background job = non-interactive host: any prompt throws instead of hanging the run-command slot; hard 10 min cap.
  $job = Start-Job -ArgumentList $ScxKeyB64, $ScxPw -ScriptBlock {
    param($KeyB64, $Pw)
    $ErrorActionPreference = 'Stop'; Import-Module OperationsManager
    $pool = Get-SCOMResourcePool -DisplayName 'All Management Servers Resource Pool'
    $kf = Join-Path $env:TEMP 'scx-disc.key'; [IO.File]::WriteAllBytes($kf, [Convert]::FromBase64String($KeyB64))
    try {
      # Get-SCXSSHCredential always prompts for a key passphrase (no parameter for it), so build the same CredentialSet directly.
      $ns = 'Microsoft.SystemCenter.CrossPlatform.ClientLibrary.CredentialManagement.Core.'
      $asm = (Get-Command Invoke-SCXDiscovery).Parameters['SshCredential'].ParameterType.Assembly
      $cred = [Activator]::CreateInstance($asm.GetType($ns + 'CredentialSet')); $cred.IsSSHKey = $true
      $cred.Usage = [Enum]::Parse($asm.GetType($ns + 'CredentialSetUsage'), 'Maintenance')
      $cu = $asm.GetType($ns + 'CredentialUsage')
      $k = [Activator]::CreateInstance($asm.GetType($ns + 'PosixHostCredential')); $k.PrincipalName = 'scxmon'; $k.KeyFile = $kf; $k.Passphrase = New-Object System.Security.SecureString
      $k.Usage = [Enum]::Parse($cu, 'SshDiscovery'); $k.ReadAndValidateSshKey(); $cred.Add($k)
      $e = [Activator]::CreateInstance($asm.GetType($ns + 'PosixHostCredential')); $e.PrincipalName = 'scxmon'; $e.Passphrase = (ConvertTo-SecureString $Pw -AsPlainText -Force)
      $e.Usage = [Enum]::Parse($cu, 'SshSudoElevation'); $cred.Add($e)
      "sshcred ok: user=$($cred.SshUserName) elevation=$($cred.SshElevationType) count=$($cred.Count)"
      $td = Get-Date
      $d = Invoke-SCXDiscovery -Name esther-linux-01.esther.lab -ResourcePool $pool -SSHCredential $cred
      "T discovery=" + [math]::Round(((Get-Date) - $td).TotalSeconds,1) + 's'
      "discovery: " + ($d | Format-List * | Out-String -Width 200)
      if ($d.Succeeded) { $ti = Get-Date; $r = $d | Install-SCXAgent; "T install=" + [math]::Round(((Get-Date) - $ti).TotalSeconds,1) + 's'; "INSTALL_RAN"; "install: " + ($r | Format-List * | Out-String -Width 200) } else { 'DISCOVERY_FAIL' }
    } finally { Remove-Item $kf -Force -ErrorAction SilentlyContinue }
  }
  if (Wait-Job $job -Timeout 600) { try { $out = @(Receive-Job $job -ErrorAction Stop); $out; if ($out -match 'INSTALL_RAN') { $installed = $true } } catch { $e = $_.Exception; while ($e.InnerException) { $e = $e.InnerException }; "JOB_ERROR: $($e.Message)" } }
  else { 'JOB_TIMEOUT (10m) partial:'; Receive-Job $job -ErrorAction SilentlyContinue; Stop-Job $job }
  Remove-Job $job -Force -ErrorAction SilentlyContinue
  T 'discovery-job-total'
}
# Poll for the agent object only when an install actually ran (was a fixed 60 s sleep on every run).
if ($installed) { for ($i = 0; $i -lt 18 -and -not (Get-SCXAgent | Where-Object Name -eq 'esther-linux-01.esther.lab'); $i++) { Start-Sleep 5 } }
T 'agent-wait'
Get-SCXAgent | Format-List Name,AgentVersion,HealthState,ManagementServer,ResourcePool | Out-String -Width 200
$seip = if ($env:SE_IP) { $env:SE_IP } else { '10.78.1.20' }
$tc = New-Object Net.Sockets.TcpClient; $ok = $tc.ConnectAsync($seip, 1270).Wait(3000); $tc.Close(); "wsman1270=$ok"
T 'final-checks'
if (Get-SCXAgent | Where-Object Name -eq 'esther-linux-01.esther.lab') { 'SCX_AGENT_OK' } else { 'SCX_AGENT_MISSING' }
