#!/usr/bin/env bash
# Teardown for the 2026-09-27 rebuild. Default = DRY-RUN (prints, touches nothing).
# Real delete runs only with CONFIRM=DELETE (workflow input) AFTER the user approves the dry-run list.
# Deletes ONLY SCOM-lab resources inside rg-learning-monitoring.
# Explicitly KEPT: anything named *lesson-speech* (esther-lesson-speech-f0 - used by the lessons
# pipeline, NOT part of the SCOM rebuild; separate user decision), the RG itself + its guardrail
# policy assignments, rg-esther-portal (Estherdaxes), all Entra objects, subscription policies, vault.
set -Eeuo pipefail
RG=rg-learning-monitoring
KEEP='lesson-speech'
az account set --subscription "${AZURE_SUBSCRIPTION_ID:?}"
echo '== WOULD DELETE (SCOM lab set) =='
az resource list -g "$RG" --query "[?!(contains(name,'$KEEP'))].{name:name,type:type}" -o table
echo '== KEPT (not part of SCOM rebuild - separate decision) =='
az resource list -g "$RG" --query "[?contains(name,'$KEEP')].{name:name,type:type}" -o table
echo "== ALSO STAYS: RG $RG itself + policy assignments; rg-esther-portal; Entra; subscription policies; vault =="
[ "${CONFIRM:-}" = "DELETE" ] || { echo 'DRY-RUN only. Nothing touched.'; exit 0; }
echo '== DELETING =='
az vm list -g "$RG" --query "[?!(contains(name,'$KEEP'))].id" -o tsv | xargs -r -P3 -I{} az vm delete --ids {} --yes -o none || true
az disk list -g "$RG" --query "[?!(contains(name,'$KEEP'))].id" -o tsv | xargs -r -I{} az disk delete --ids {} --yes -o none
az network nic list -g "$RG" --query "[?!(contains(name,'$KEEP'))].id" -o tsv | xargs -r -I{} az network nic delete --ids {} -o none
az network vnet list -g "$RG" --query "[?!(contains(name,'$KEEP'))].id" -o tsv | xargs -r -I{} az network vnet delete --ids {} -o none
az network nsg list -g "$RG" --query "[?!(contains(name,'$KEEP'))].id" -o tsv | xargs -r -I{} az network nsg delete --ids {} -o none
az storage account list -g "$RG" --query "[?!(contains(name,'$KEEP'))].id" -o tsv | xargs -r -I{} az storage account delete --ids {} --yes -o none
echo '== REMAINING (expect only kept names) =='
az resource list -g "$RG" --query '[].{name:name,type:type}' -o table
echo TEARDOWN_DONE
