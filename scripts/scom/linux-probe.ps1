# Read-only probe on the SCOM server before Linux agent discovery.
Import-Module OperationsManager -ErrorAction SilentlyContinue
"ms=" + (Get-SCOMManagementServer | Select-Object -Expand DisplayName)
"linuxMPs:"; Get-SCOMManagementPack | Where-Object { $_.Name -match 'Linux|Unix|SCX|CrossPlat' } | ForEach-Object { "  $($_.Name) $($_.Version)" }
"runas:"; Get-SCOMRunAsAccount | Where-Object { $_.AccountType -match 'SCX' } | ForEach-Object { "  $($_.Name) $($_.AccountType)" }
"pools:"; Get-SCOMResourcePool | ForEach-Object { "  $($_.DisplayName)" }
"unixKits:"; Get-ChildItem 'C:\Program Files\Microsoft System Center\Operations Manager\Server\AgentManagement\UnixAgents\DownloadedKits' -ErrorAction SilentlyContinue | ForEach-Object { "  $($_.Name)" }
"mpFolder:"; Get-ChildItem C:\ -Recurse -Filter 'Microsoft.Linux.Universal*.mp*' -ErrorAction SilentlyContinue | Select-Object -First 8 | ForEach-Object { "  $($_.FullName)" }
"dns=" + ((Resolve-DnsName esther-linux-01.esther.lab -ErrorAction SilentlyContinue).IPAddress -join ',')
$seip = if ($env:SE_IP) { $env:SE_IP } else { '10.78.1.20' }
"ssh22=" + (Test-NetConnection $seip -Port 22 -WarningAction SilentlyContinue).TcpTestSucceeded
"wsman1270=" + (Test-NetConnection $seip -Port 1270 -WarningAction SilentlyContinue).TcpTestSucceeded
