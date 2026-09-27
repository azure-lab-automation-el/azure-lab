#!/usr/bin/env bash
# שלב 2: מבחן שחזור על דיסק לינוקס (שוודיה - המכסה שם פנויה במקביל להקמה בישראל).
# מכונה זמנית מהדיסק השמור, בדיקת עלייה, וניקוי. מוכיח שדרך ה-undo עובדת לפני ההקמה.
set -euo pipefail
RG=rg-learning-monitoring; SENET=${LAB_SE_NET_BASE:-10.78}
VM=esther-linux-01rb; NIC=$VM-nic; DISK=esther-linux-01-osdisk
SUBID=$(az network vnet show -g $RG -n esther-se-vnet --query id -o tsv)
az network nic create -g $RG -n $NIC -l swedencentral --subnet "$SUBID/subnets/esther-se-subnet" --private-ip-address $SENET.1.20 --only-show-errors -o none && echo "NIC זמני נוצר"
az vm create -g $RG -n $VM -l swedencentral --attach-os-disk $DISK --os-type linux --nics $NIC --size Standard_B2ats_v2 --only-show-errors -o none && echo "מכונה זמנית נוצרה מהדיסק השמור"
out=""
for i in 1 2 3 4 5 6; do
  sleep 30
  out=$(az vm run-command invoke -g $RG -n $VM --command-id RunShellScript --scripts "hostname; systemctl is-active ssh" --query "value[0].message" -o tsv 2>&1 || true)
  echo "ניסיון $i: $out"
  echo "$out" | grep -qi 'esther-linux-01' && break
done
echo "== מנקה מכונת בדיקה =="
az vm delete -g $RG -n $VM --yes --only-show-errors -o none
az network nic delete -g $RG -n $NIC --only-show-errors -o none
echo "$out" | grep -qi 'esther-linux-01' && echo "✅ שחזור מהדיסק עובד - hostname=esther-linux-01" || { echo "❌ מכונת הבדיקה לא עלתה - עוצר לפני ההקמה"; exit 1; }
