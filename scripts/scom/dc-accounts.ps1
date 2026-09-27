param($p)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$d = Get-ADDomain
$ou = "OU=SCOM,$($d.DistinguishedName)"
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'SCOM'")) { New-ADOrganizationalUnit -Name 'SCOM' -Path $d.DistinguishedName }
$s = ConvertTo-SecureString $p -AsPlainText -Force
foreach ($n in 'svc-scom-action', 'svc-scom-sdk', 'svc-scom-dra', 'svc-scom-dwr', 'svc-sql') {
  if (-not (Get-ADUser -Filter "SamAccountName -eq '$n'")) {
    New-ADUser -Name $n -SamAccountName $n -UserPrincipalName "$n@$($d.DNSRoot)" -Path $ou -AccountPassword $s -Enabled $true -PasswordNeverExpires $true -CannotChangePassword $true
  }
}
if (-not (Get-ADGroup -Filter "Name -eq 'SCOM-Admins'")) { New-ADGroup -Name 'SCOM-Admins' -GroupScope Global -Path $ou }
Add-ADGroupMember 'SCOM-Admins' -Members 'svc-scom-sdk', 'svc-scom-dra', 'estherlabadmin'
"domain=$($d.DNSRoot) netbios=$($d.NetBIOSName) dc=$env:COMPUTERNAME"
"users=" + ((Get-ADUser -SearchBase $ou -Filter *).SamAccountName -join ',')
"SCOM-Admins=" + ((Get-ADGroupMember 'SCOM-Admins').SamAccountName -join ',')
