#!/usr/bin/env bash
# mivtza-eser finalize (runs always(), success or abort): restore Defender/WU defaults, guaranteed resize-down,
# per-stage timings from table rows, end-state verify. MODE=success|abort.
set -Eeuo pipefail; set +x
: "${AZURE_SUBSCRIPTION_ID:?}" "${MEDIA_ACCOUNT:?}"
MODE=${MODE:-success}; RG=rg-learning-monitoring; P=${LAB_PREFIX:-esther}; DC=$P-dc-01; VM=$P-adaxes-01
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
restore='Remove-MpPreference -ExclusionPath @("C:\lab","C:\scomlab","C:\media","C:\Program Files\Microsoft SQL Server","C:\Program Files\Microsoft System Center") -ErrorAction SilentlyContinue; Enable-ScheduledTask -TaskPath "\Microsoft\Windows\Server Manager\" -TaskName "ServerManager" -ErrorAction SilentlyContinue | Out-Null; "defaults restored on $env:COMPUTERNAME"'
for v in "$DC" "$VM"; do
  az vm show -g $RG -n "$v" -o none 2>/dev/null && az vm run-command invoke -g $RG -n "$v" --command-id RunPowerShellScript --scripts "$restore" -o json | jq -r '.value[]?.message' || true
done
echo "== resize-down (guaranteed) =="
if az vm show -g $RG -n "$DC" -o none 2>/dev/null; then
  cur=$(az vm show -g $RG -n "$DC" --query hardwareProfile.vmSize -o tsv)
  if [ "$cur" != Standard_B2ats_v2 ]; then az vm deallocate -g $RG -n "$DC" -o none; az vm resize -g $RG -n "$DC" --size Standard_B2ats_v2 -o none; az vm start -g $RG -n "$DC" -o none; echo "dc: $cur -> Standard_B2ats_v2"; else echo "dc already Standard_B2ats_v2"; fi
fi
echo "== timings (from table) =="
KEY=$(az storage account keys list -g $RG -n "$MEDIA_ACCOUNT" --query '[0].value' -o tsv)
for m in dc vm; do
  j=$(az storage entity show --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" --table-name labstate --partition-key "$m" --row-key state --query data -o tsv 2>/dev/null || true)
  [ -n "$j" ] && jq -r '.hist | to_entries | sort_by(.value) | .[] | "  \(.key): \(.value)"' <<<"$j" | sed "s/^/$m/" || echo "$m: no state row"
done
if [ "$MODE" = success ]; then
  echo "== verify =="
  az vm run-command invoke -g $RG -n "$VM" --command-id RunPowerShellScript --scripts 'try { $r = Invoke-WebRequest http://localhost/OperationsManager -UseBasicParsing -TimeoutSec 30; "WEBCONSOLE_HTTP $($r.StatusCode)" } catch { "WEBCONSOLE_FAIL $($_.Exception.Message)" }; (Get-Service OMSDK,HealthService | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join " "' -o json | jq -r '.value[]?.message'
  echo REBUILD_VERIFY_DONE
else echo "ABORT mode: defaults restored, costs stopped, state rows above show where it stopped"; fi
