param($p)
$ErrorActionPreference = 'Stop'
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools | Out-Null
Import-Module ADDSDeployment
$r = Install-ADDSForest -DomainName 'esther.lab' -DomainNetbiosName 'ESTHER' -InstallDns -SafeModeAdministratorPassword (ConvertTo-SecureString $p -AsPlainText -Force) -NoRebootOnCompletion -Force -WarningAction SilentlyContinue
"status=$($r.Status) $($r.Message)"
