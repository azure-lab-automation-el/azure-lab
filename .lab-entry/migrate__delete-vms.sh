#!/usr/bin/env bash
# שלב 1: הכנת הגיבוי + מחיקת מכונות. snapshots חסומים במדיניות, לכן הגיבוי הוא הדיסקים עצמם:
# קודם מוודאים deleteOption=Detach (ברירת המחדל של CLI היא Delete - בלי זה הדיסק היה נמחק עם המכונה!),
# אחר כך מוחקים את 3 המכונות במקביל, וחונים את ה-NICs על כתובות זמניות לשחרור ה-IP הקבוע.
set -euo pipefail
RG=rg-learning-monitoring; NET=${LAB_NET_BASE:-10.77}; SENET=${LAB_SE_NET_BASE:-10.78}
echo "== ניתוק חשמל קשיח מקבילי (כלל קבוע: teardown תמיד skip-shutdown, בלי כיבוי מנומס) =="
for vm in esther-dc-01 esther-adaxes-01 esther-linux-01; do
  az vm stop -g $RG -n $vm --skip-shutdown --only-show-errors -o none 2>/dev/null &
done
wait
echo "== שחרור (deallocate) מקבילי =="
for vm in esther-dc-01 esther-adaxes-01 esther-linux-01; do
  az vm deallocate -g $RG -n $vm --no-wait --only-show-errors -o none 2>/dev/null &
done
wait
for i in $(seq 1 24); do
  up=$(for vm in esther-dc-01 esther-adaxes-01 esther-linux-01; do az vm show -d -g $RG -n $vm --query powerState -o tsv 2>/dev/null; done | grep -vc deallocated || true)
  if [ "$up" = 0 ]; then break; fi; sleep 10
done
echo "== קיבוע דיסקים ו-NICs (deleteOption=Detach) =="
for vm in esther-dc-01 esther-adaxes-01 esther-linux-01; do
  az vm update -g $RG -n $vm --set storageProfile.osDisk.deleteOption=Detach --only-show-errors -o none &
done
wait
for vm in esther-dc-01 esther-adaxes-01 esther-linux-01; do
  opt=$(az vm show -g $RG -n $vm --query "storageProfile.osDisk.deleteOption" -o tsv 2>/dev/null || true)
  if [ -z "$opt" ]; then
    if az vm show -g $RG -n $vm -o none 2>/dev/null; then
      echo "$vm ללא osDisk (shell תקול) - אין דיסק בסכנה, מדלג על קיבוע"
    else
      echo "$vm כבר לא קיימת - מדלג"
    fi
    continue
  fi
  echo "$vm osDisk.deleteOption=$opt"
  [ "$opt" = "Detach" ] || { echo "❌ $vm: הדיסק עדיין יימחק עם המכונה - עוצר"; exit 1; }
done
echo "== מחיקת 3 המכונות במקביל (דיסקים ו-NICs נשארים) =="
# לקח מריצה 1 (מבצע עשר): delete סינכרוני על מכונה דולקת מחכה לכיבוי מנומס - דקות ארוכות.
# --force-deletion true מדלג על הכיבוי, --no-wait מקבץ, ווידוא אחד בסוף.
for vm in esther-dc-01 esther-adaxes-01 esther-linux-01; do
  if az vm show -g $RG -n $vm -o none 2>/dev/null; then
    az vm delete -g $RG -n $vm --yes --force-deletion true --no-wait --only-show-errors -o none && echo "מחיקה שוגרה: $vm" &
  else echo "כבר לא קיימת: $vm"; fi
done
wait
for i in $(seq 1 30); do
  left=$(for vm in esther-dc-01 esther-adaxes-01 esther-linux-01; do az vm show -g $RG -n $vm --query name -o tsv 2>/dev/null; done)
  if [ -z "$left" ]; then break; fi; echo "ממתין למחיקה: $left"; sleep 10
done
if [ -n "$left" ]; then echo "❌ עדיין קיימות: $left"; exit 1; fi
echo "3 המכונות נמחקו (דיסקים ו-NICs נשמרו)"
echo "== וידוא שהדיסקים שרדו =="
for d in esther-dc-01-osdisk esther-adaxes-01-osdisk esther-linux-01-osdisk; do
  st=$(az disk show -g $RG -n $d --query "{ps:provisioningState,state:diskState,size:diskSizeGb}" -o json 2>/dev/null || echo MISSING)
  echo "$d $st"
  [ "$st" = "MISSING" ] && { echo "❌ דיסק $d לא שרד - עוצר"; exit 1; }
done
park() {
  # חנייה על כתובת זמנית פנויה בלבד - אף פעם לא דריסת NIC גיבוי שחונה שם (לקח: nicm2 על .248/.250)
  if az network nic show -g $RG -n "$1" -o none 2>/dev/null; then
    local base=$2
    for t in 246 247 248 249 250 251 252; do
      if [ -z "$(az network nic list -g $RG --query "[?ipConfigurations[0].privateIPAddress=='$base.$t'].name" -o tsv)" ]; then
        az network nic ip-config update -g $RG --nic-name "$1" -n ipconfig1 --private-ip-address "$base.$t" --only-show-errors -o none && echo "חונה: $1 -> $base.$t"
        return
      fi
    done
    echo "⚠️ לא נמצאה כתובת חנייה פנויה עבור $1 - נשאר במקום (בלתי מזיק)"
  else echo "NIC לא קיים (דילוג): $1"; fi
}
park esther-dc-01-nic $NET.1 &
park esther-adaxes-01-nic $NET.1 &
park esther-linux-01-se-nic $SENET.1 &
wait
echo "== מכסת ליבות אחרי מחיקה =="
az vm list-usage -l israelcentral --query "[?name.value=='cores'].{cur:currentValue,lim:limit}" -o json
az vm list-usage -l swedencentral --query "[?name.value=='cores'].{cur:currentValue,lim:limit}" -o json
echo "✅ שלב 1 הושלם - מכסה פנויה, דיסקי הגיבוי שלמים ומנותקים"
