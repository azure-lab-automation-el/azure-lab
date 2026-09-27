param($p)
$ErrorActionPreference = 'Stop'
$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.PartOfDomain -and $cs.Domain -eq 'esther.lab') { "already-joined domain=$($cs.Domain)"; return }
if ($cs.DomainRole -ge 4) { "STOP: this server is a domain controller of $($cs.Domain)"; return }
$dns = (Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object ServerAddresses).ServerAddresses -join ','
"dns=$dns"
Resolve-DnsName esther.lab -Type A | Out-Null
$c = New-Object System.Management.Automation.PSCredential('ESTHER\estherlabadmin', (ConvertTo-SecureString $p -AsPlainText -Force))
Add-Computer -DomainName 'esther.lab' -Credential $c -Force
"joined-pending-reboot"
