#!/usr/bin/env bash
# Phase 5 of the SCOM lab: SCOM 2025 install (single server) and a screenshot of the Operations Console via a temporary autologon session.
set -Eeuo pipefail; set +x
step=startup; trap 'printf "ERROR step=%s line=%s\n" "$step" "${BASH_LINENO[0]:-?}" >&2' ERR
: "${AZURE_SUBSCRIPTION_ID:?}" "${ESTHER_SCOM_SVC_PASSWORD:?}" "${ESTHER_VM_ADMIN_PASSWORD:?}" "${MEDIA_ACCOUNT:?}"
RG=rg-learning-monitoring; P=${LAB_PREFIX:-esther}; VM=$P-adaxes-01; DC=$P-dc-01
source scripts/lib/ops-status.sh; ops_mask "$ESTHER_SCOM_SVC_PASSWORD" "$ESTHER_VM_ADMIN_PASSWORD"
ops_step 1 7 "הדלקת השרתים" "az vm start -g $RG -n $DC && az vm start -n $VM" "מדליק את ה-DC ואת אסתר (אם כבויים), כדי שההתקנה תוכל לרוץ"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"
az vm start -g "$RG" -n "$DC" -o none; az vm start -g "$RG" -n "$VM" -o none
KEY=$(az storage account keys list -g "$RG" -n "$MEDIA_ACCOUNT" --query '[0].value' -o tsv); echo "::add-mask::$KEY"
exp=$(date -u -d '+1 hour' +%Y-%m-%dT%H:%MZ)
OUT=$(az storage blob generate-sas --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c media -n console.png --permissions cw --expiry "$exp" --https-only --full-uri -o tsv); echo "::add-mask::$OUT"
az storage table create --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -n heartbeat -o none
HBS=$(az storage table generate-sas --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -n heartbeat --permissions au --expiry "$(date -u -d '+365 day' +%Y-%m-%dT%H:%MZ)" --https-only -o tsv); echo "::add-mask::$HBS"
HB="https://$MEDIA_ACCOUNT.table.core.windows.net/heartbeat(PartitionKey='esther',RowKey='hb')?$HBS"; echo "::add-mask::$HB"
declare -A HE=([hb-on]="2|הפעלת דופק (heartbeat) עצמאי|Register-ScheduledTask scom-heartbeat → שורה אחת ב-Table Storage כל 45 שנ׳ / 15 דק׳|משימה ברקע שמעלה מצב התקנה ללא תלות ב-run-command" [hb-off]="7|הסרת הדופק|Unregister-ScheduledTask scom-heartbeat|מסיר את משימת הדופק בסוף" [install]="2|התקנת SCOM 2025 (Management Server + Console + Web Console)|Setup.exe /silent /install /components:OMServer,OMConsole,OMWebConsole ...|מתקין את SCOM: יוצר את מסדי הנתונים ב-SQL, את שירותי ה-Management Server ואת הקונסולה" [autologon-on]="3|הפעלת Auto Logon זמני|Set-ItemProperty HKLM:\\...\\Winlogon AutoAdminLogon=1|מגדיר כניסה אוטומטית של estherlabadmin כדי שיהיה מסך אמיתי לצילום" [shot]="5|צילום הקונסולה|Start-Process Microsoft.EnterpriseManagement.Monitoring.Console.exe; CopyFromScreen|פותח את Operations Console בסשן, מחכה שיתחבר ומצלם את המסך ל-PNG" [webconsole]="2|התקנת Web Console|Setup.exe /silent /install /components:OMWebConsole /WebSiteName:\"Default Web Site\"|מתקין את קונסולת הווב של SCOM על IIS ובודק שהאתר עונה" [autologon-off]="6|כיבוי Auto Logon ומחיקת הסיסמה|Remove-ItemProperty Winlogon DefaultPassword; AutoAdminLogon=0|מבטל את הכניסה האוטומטית ומוחק את הסיסמה מהרג׳יסטרי")
run() { step=$1; echo "== $1"; IFS="|" read -r hn hl hc he <<<"${HE[$1]:-0|$1|$1|}"; ops_step "$hn" 7 "$hl" "az vm run-command invoke -n $VM --scripts @scom-install.ps1 stage=$1 → $hc" "$he"; local pw=$ESTHER_SCOM_SVC_PASSWORD out; [[ $1 == autologon-on ]] && pw=$ESTHER_VM_ADMIN_PASSWORD
  out=$(az vm run-command invoke -g "$RG" -n "$VM" --command-id RunPowerShellScript --scripts @scripts/scom/scom-install.ps1 \
    --parameters "stage=$1" "p=$pw" "out=$(printf %s "$([[ $1 == hb-on ]] && echo "$HB" || echo "$OUT")" | base64 -w0)" "a=$ESTHER_VM_ADMIN_PASSWORD" -o json | jq -r '.value[]?.message' | grep -v '^\s*$' || true)
  echo "$out" | tail -40
  if grep -qE 'STAGE_FAIL|is not recognized' <<<"$out"; then echo "PHASE5_FAILED at $1"; [[ $1 == shot ]] && run autologon-off; exit 1; fi; }
for s in ${STAGES:-hb-on install autologon-on restart shot autologon-off}; do
  if [[ $s == dc-fixes ]]; then step=dc-fixes; source scripts/scom/dc-fixes.sh; continue; fi
  if [[ $s == mps ]]; then step=mps; source scripts/scom/mps-ad-dns.sh; continue; fi
  if [[ $s == agent-manual ]]; then step=agent-manual; source scripts/scom/agent-dc-manual.sh; continue; fi
  if [[ $s == restart ]]; then step=restart; ops_step 4 7 "אתחול אסתר" "az vm restart -g $RG -n $VM" "מאתחל את השרת כדי שה-Auto Logon ייכנס ויפתח שולחן עבודה"; az vm restart -g "$RG" -n "$VM" -o none; echo "== restarted"
    for i in $(seq 1 18); do
      out=$(az vm run-command invoke -g "$RG" -n "$VM" --command-id RunPowerShellScript --scripts 'Write-Output READY' -o json 2>/dev/null | jq -r '.value[]?.message' || true)
      grep -q READY <<<"$out" && { echo "== VM ready after ~$((i*10))s"; break; }
      sleep 10
    done; continue; fi
  run "$s"
done
if [[ " ${STAGES:-shot} " == *" shot "* ]]; then mkdir -p out; az storage blob download --account-name "$MEDIA_ACCOUNT" --account-key "$KEY" -c media -n console.png -f out/console.png -o none; ls -l out/console.png; fi
ops_step 7 7 "הורדת הצילום וסיום" "az storage blob download -c media -n console.png" "מוריד את צילום הקונסולה מה-Storage ל-Artifact של הריצה"
echo PHASE5_OK
