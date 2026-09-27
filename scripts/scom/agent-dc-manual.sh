#!/usr/bin/env bash
# Manual SCOM agent install on the lab DC (push discovery can't reach it). Rollback: msiexec /x on the DC + Delete agent in console.
# Sourced from esther-scom-phase5.sh (needs RG, VM, MEDIA_ACCOUNT, KEY, exp).
DC=${LAB_PREFIX:-esther}-dc-01; MSI=momagent.msi
rc() { az vm run-command invoke -g "$RG" -n "$1" --command-id RunPowerShellScript --scripts "$2" -o json | jq -r '.value[]?.message' | grep -v '^\s*$' || true; }
W=$(az storage blob generate-sas --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c media -n $MSI --permissions cw --expiry "$exp" --https-only --full-uri -o tsv); echo "::add-mask::$W"
R=$(az storage blob generate-sas --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c media -n $MSI --permissions r --expiry "$exp" --https-only --full-uri -o tsv); echo "::add-mask::$R"
echo "== approval setting + upload MSI from Esther"
rc "$VM" "\$ErrorActionPreference='Stop'; Import-Module OperationsManager; New-SCOMManagementGroupConnection -ComputerName localhost; Set-SCOMAgentApprovalSetting -Pending; 'approval=' + (Get-SCOMAgentApprovalSetting); \$m = Get-ChildItem 'C:\Program Files\Microsoft System Center\Operations Manager' -Recurse -Filter MOMAgent.msi | Where-Object FullName -match 'amd64' | Select-Object -First 1; 'msi=' + \$m.FullName + ' bytes=' + \$m.Length; Invoke-WebRequest '$W' -Method Put -InFile \$m.FullName -Headers @{'x-ms-blob-type'='BlockBlob'} -UseBasicParsing | Out-Null; 'UPLOAD_OK'" | tee /tmp/a1.txt
grep -q UPLOAD_OK /tmp/a1.txt || { echo "STAGE_FAIL agent-manual upload"; exit 1; }
echo "== install on DC"
rc "$DC" "\$ErrorActionPreference='Stop'; New-Item -ItemType Directory -Force C:\scomlab | Out-Null; Invoke-WebRequest '$R' -OutFile C:\scomlab\MOMAgent.msi -UseBasicParsing; if (Get-Service HealthService -ErrorAction SilentlyContinue) { 'already installed' } else { \$p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList '/i C:\scomlab\MOMAgent.msi /qn /l*v C:\scomlab\agent-install.log USE_SETTINGS_FROM_AD=0 USE_MANUALLY_SPECIFIED_SETTINGS=1 MANAGEMENT_GROUP=ESTHER-MG MANAGEMENT_SERVER_DNS=ESTHERLAB.esther.lab SECURE_PORT=5723 ACTIONS_USE_COMPUTER_ACCOUNT=1 AcceptEndUserLicenseAgreement=1'; 'msiexit=' + \$p.ExitCode }; 'svc=' + (Get-Service HealthService).Status; Remove-Item C:\scomlab\MOMAgent.msi -ErrorAction SilentlyContinue; 'DC_INSTALL_DONE'" | tee /tmp/a2.txt
grep -qE 'svc=Running' /tmp/a2.txt || { echo "STAGE_FAIL agent-manual install"; exit 1; }
az storage blob delete --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c media -n $MSI -o none || true
echo "== approve + readback"
rc "$VM" "Import-Module OperationsManager; New-SCOMManagementGroupConnection -ComputerName localhost; for (\$i=0; \$i -lt 18 -and -not (Get-SCOMAgent -DNSHostName ESTHERDC01.esther.lab -ErrorAction SilentlyContinue); \$i++) { Get-SCOMPendingManagement | Where-Object AgentName -match 'ESTHERDC01' | Approve-SCOMPendingManagement; Start-Sleep 10 }; Start-Sleep 60; Get-SCOMAgent | % { 'AGENT ' + \$_.DisplayName + ' health=' + \$_.HealthState + ' ver=' + \$_.Version }; Set-SCOMAgentApprovalSetting -Reject; 'approval=' + (Get-SCOMAgentApprovalSetting); 'AGENT_DC_OK'" | tee /tmp/a3.txt
grep -q 'AGENT ESTHERDC01' /tmp/a3.txt || { echo "STAGE_FAIL agent-manual approve"; exit 1; }
