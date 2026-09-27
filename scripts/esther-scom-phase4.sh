#!/usr/bin/env bash
# Phase 4 of the SCOM lab: finish SSRS after its reboot, free disk space, then SCOM prerequisites (IIS/ASP.NET) and SCOM media.
set -Eeuo pipefail; set +x
step=startup; trap 'printf "ERROR step=%s line=%s\n" "$step" "${BASH_LINENO[0]:-?}" >&2' ERR
: "${AZURE_SUBSCRIPTION_ID:?}" "${MEDIA_ACCOUNT:?}"
RG=rg-learning-monitoring; P=${LAB_PREFIX:-esther}; VM=$P-adaxes-01; DC=$P-dc-01
source scripts/lib/ops-status.sh
declare -A HE=([rsfix]="סיום SSRS אחרי האתחול|Start-Service SSRS; Invoke-WebRequest http://localhost/ReportServer|מוודא ש-Reporting Services עלה ועונה" [cleanup]="ניקוי דיסק|Remove-Item C:\\media\\*.iso; Dism /Cleanup-Image|מוחק קבצי התקנה שכבר לא צריך כדי לפנות מקום ל-SCOM" [check]="בדיקת דרישות מקדימות|Get-WindowsFeature ...; Get-PSDrive C|בודק אילו רכיבים של Windows כבר מותקנים וכמה מקום פנוי" [iis]="התקנת IIS ודרישות Web Console|Install-WindowsFeature Web-Server,Web-Asp-Net45,Web-Windows-Auth,Web-Metabase ...|מתקין את IIS ואת הרכיבים ש-SCOM Web Console צריך" [scomextract]="הורדה וחילוץ של SCOM 2025|Invoke-WebRequest <SAS> -OutFile SCOM_2025.zip; Expand-Archive; SCOM_2025.exe /dir /silent|מוריד את קבצי SCOM מה-Storage וחולץ אותם ל-C:\\scomlab\\scom" [sqlstart]="הפעלת שירותי SQL ו-SSRS|Set-Service MSSQLSERVER -StartupType Automatic; Start-Service ...|מוודא ש-SQL Server, ה-Agent ו-Reporting Services רצים ועולים אוטומטית" [diag]="אבחון מצב השרת|Get-Service; Get-WindowsFeature; Get-ChildItem C:\\scomlab|בדיקה לקריאה בלבד של מצב השרת")
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az vm start -g "$RG" -n "$DC" -o none 2>/dev/null || echo "DC not up yet (preload)";
ops_step 1 7 "אתחול אסתר" "az vm restart -g $RG -n $VM" "מאתחל את השרת כדי לסיים את התקנת SSRS"; step=restart; [[ "${RESTART:-true}" == true ]] && { az vm restart -g "$RG" -n "$VM" -o none; echo restarted; } || az vm start -g "$RG" -n "$VM" -o none
KEY=$(az storage account keys list -g "$RG" -n "$MEDIA_ACCOUNT" --query '[0].value' -o tsv); echo "::add-mask::$KEY"
exp=$(date -u -d '+3 hours' +%Y-%m-%dT%H:%MZ)
SCOM_SAS=$(az storage blob generate-sas --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c media -n SCOM_2025.zip --permissions r --expiry "$exp" --https-only --full-uri -o tsv); echo "::add-mask::$SCOM_SAS"
B64=$(printf %s "$SCOM_SAS" | base64 -w0)
OPS_N=0; OPS_T=$(( $(wc -w <<<"${STAGES:-a b c d e f}") + 1 ))
run() { step="$1:$2"; echo "== $1 $2"; local out; OPS_N=$((OPS_N+1)); IFS="|" read -r hl hc he <<<"${HE[$2]:-$2|$2|}"; ops_step "$OPS_N" "$OPS_T" "$hl" "az vm run-command invoke -n $VM --scripts @$1 stage=$2 → $hc" "$he"
  out=$(az vm run-command invoke -g "$RG" -n "$VM" --command-id RunPowerShellScript --scripts @scripts/scom/$1 --parameters "stage=$2" "media=$B64" -o json | jq -r '.value[]?.message' | grep -v '^\s*$' || true)
  echo "$out" | tail -40
  if grep -qE 'STAGE_FAIL|is not recognized' <<<"$out"; then echo "PHASE4_FAILED at $1 $2"; exit 1; fi; }
for s in ${STAGES:-sql-install.ps1:rsfix sql-install.ps1:cleanup prereq.ps1:check prereq.ps1:iis prereq.ps1:scomextract prereq.ps1:check}; do run "${s%%:*}" "${s#*:}"; done
echo PHASE4_OK
