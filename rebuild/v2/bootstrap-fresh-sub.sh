#!/usr/bin/env bash
# Fresh-clean-subscription bootstrap for the lab. Run LOCALLY as Owner on the new subscription (az login done).
# Two modes:
#   MODE=export (default, read-only on the CURRENT sub): export the 5 lab policy definitions+assignments to payload/policy/*.json
#   MODE=apply  (new sub): providers + RG + media storage + policy-as-code from payload/policy/*.json
#     Policy apply is GATED: requires APPROVE_POLICY=YES (his explicit word, per standing rule).
set -Eeuo pipefail
MODE=${MODE:-export}; RG=rg-learning-monitoring; LOC=${LAB_LOCATION:-israelcentral}
POLICIES='lab-types lab-locations lab-vm-images lab-vm-skus lab-tags'
case "$MODE" in
export)
  mkdir -p policy
  for p in $POLICIES; do
    az policy definition show -n "$p" > "policy/$p.def.json" 2>/dev/null && echo "exported def $p" || echo "MISSING def $p"
  done
  SCOPE="/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RG"
  for p in $POLICIES lab-locations-swa-exempt; do
    az policy assignment show --scope "$SCOPE" -n "$p" > "policy/$p.assign.json" 2>/dev/null && echo "exported assign $p" || true
  done
  echo EXPORT_OK - commit payload/policy/ with the next payload push
  ;;
apply)
  : "${AZURE_SUBSCRIPTION_ID:?set to the NEW sub}"; az account set --subscription "$AZURE_SUBSCRIPTION_ID"
  echo "== providers =="
  for rp in Microsoft.Compute Microsoft.Network Microsoft.Storage Microsoft.Authorization; do
    az provider register -n "$rp" --wait -o none 2>/dev/null || az provider register -n "$rp" -o none; echo "  $rp: $(az provider show -n $rp --query registrationState -o tsv)"
  done
  echo "== RG + media storage =="
  az group create -n "$RG" -l "$LOC" -o none
  az storage account create -g "$RG" -n "$MEDIA_ACCOUNT" -l "$LOC" --sku Standard_LRS --kind StorageV2 --allow-blob-public-access false --https-only true -o none
  az storage container create --account-name "$MEDIA_ACCOUNT" -n media --auth-mode login -o none
  echo "== quota =="
  q=$(az vm list-usage -l "$LOC" --query "[?name.value=='cores'].{used:currentValue,limit:limit}" -o json)
  free=$(( $(jq -r '.[0].limit' <<<"$q") - $(jq -r '.[0].used' <<<"$q") )); echo "regional cores free: $free"
  [ "$free" -ge 4 ] || echo "WARN: <4 cores - use the other approved region or Standard_B2ats_v2-only build"
  echo "== policy as code (GATED) =="
  if [ "${APPROVE_POLICY:-}" = YES ]; then
    ls policy/*.def.json >/dev/null 2>&1 || { echo "FAIL: payload/policy/*.json missing - run MODE=export on the old sub first"; exit 1; }
    for f in policy/*.def.json; do n=$(basename "$f" .def.json); az policy definition create -n "$n" --rules <(jq .properties.policyRule "$f") --params <(jq '.properties.parameters // {}' "$f") --display-name "$(jq -r .properties.displayName "$f")" -o none; echo "  def $n"; done
    for f in policy/*.assign.json; do n=$(basename "$f" .assign.json); az policy assignment create -n "$n" --scope "/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$RG" --policy "$(jq -r .properties.policyDefinitionId "$f" | sed "s|/subscriptions/[^/]*|/subscriptions/$AZURE_SUBSCRIPTION_ID|")" -o none; echo "  assign $n"; done
    echo POLICY_APPLIED
  else echo "policy apply SKIPPED (set APPROVE_POLICY=YES with his explicit approval)"; fi
  echo "== next manual steps =="
  echo "1. create SP + OIDC federated cred for the repo, grant Contributor on $RG"
  echo "2. set repo secrets (AZURE_*, LAB_AGE_KEY, ESTHER_*, MEGA_*)"
  echo "3. run mivtza-eser dryrun, then real"
  ;;
esac
