#!/usr/bin/env bash
# Builds a DC-side PowerShell script that runs <inner.ps1> on the SCOM server (ESTHERLAB) over WinRM, capped at <cap> seconds.
# Secrets come from env PW/SCXPW/KEYB64 and are embedded as literals in the script body (never on a process command line);
# the script deletes its own file on the DC when done. Inner secrets travel as Invoke-Command arguments (remoting channel).
set -euo pipefail; inner=$1; cap=${2:-1080}
q() { printf "%s" "$1" | sed "s/'/''/g"; }
cat <<PS
\$Pw = '$(q "$PW")'; \$ScxPw = '$(q "$SCXPW")'; \$ScxKeyB64 = '$(q "$KEYB64")'
"DC_START_EPOCH=" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
try {
\$c = New-Object System.Management.Automation.PSCredential('ESTHER\\estherlabadmin', (ConvertTo-SecureString \$Pw -AsPlainText -Force))
\$inner = @'
$(cat "$inner")
'@
\$t0 = Get-Date
\$s = New-PSSession -ComputerName ESTHERLAB.esther.lab -Credential \$c
"WINRM_SESSION_MS=" + [int]((Get-Date) - \$t0).TotalMilliseconds
\$j = Invoke-Command -Session \$s -ScriptBlock ([scriptblock]::Create(\$inner)) -ArgumentList \$ScxPw, \$ScxKeyB64 -AsJob
\$dl = (Get-Date).AddSeconds($cap); while (\$j.State -in 'NotStarted','Running' -and (Get-Date) -lt \$dl) { Start-Sleep -Milliseconds 500 }
if (\$j.State -eq 'Blocked') { 'REMOTE_BLOCKED (a command wanted interactive input); closing the session instead of waiting'; Remove-PSSession \$s -ErrorAction SilentlyContinue; Remove-Job \$j -Force -ErrorAction SilentlyContinue }
elseif (\$j.State -in 'NotStarted','Running') { 'REMOTE_TIMEOUT (${cap}s) partial:'; Receive-Job \$j -ErrorAction SilentlyContinue 2>&1 | ForEach-Object { "\$_" }; Stop-Job \$j }
else { Receive-Job \$j -ErrorAction Continue 2>&1 | ForEach-Object { "\$_" } | ForEach-Object { if (\$_ -like 'MPZIP:*') { New-Item -ItemType Directory C:\\scom-export -Force | Out-Null; Set-Content C:\\scom-export\\mp.b64 (\$_.Substring(6)) -NoNewline; "MPZIP saved on DC chars=" + (\$_.Length - 6) } else { \$_ } } }
"REMOTE_SECONDS=" + [int]((Get-Date) - \$t0).TotalSeconds
Remove-PSSession \$s -ErrorAction SilentlyContinue
"DC_END_EPOCH=" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
} finally { if (\$PSCommandPath) { Remove-Item \$PSCommandPath -Force -ErrorAction SilentlyContinue } }
PS
