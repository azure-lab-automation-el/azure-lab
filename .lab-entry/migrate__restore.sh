#!/usr/bin/env bash
# שלב שחזור חירום (רק אם ההקמה נכשלה): מנקה שאריות הקמה, מחזיר NICs לכתובות המקור, ומחזיר את 3 המכונות מהדיסקים.
set -euo pipefail
RG=rg-learning-monitoring; NET=${LAB_NET_BASE:-10.77}; SENET=${LAB_SE_NET_BASE:-10.78}; SUF=${LAB_NAME_SUFFIX:-m2}
echo "== ניקוי שאריות הקמה (אם נוצרו) =="
for vm in esther-dc-01 esther-adaxes-01 esther-linux-01; do
  az vm show -g $RG -n $vm -o none 2>/dev/null && { az vm delete -g $RG -n $vm --yes --only-show-errors -o none; echo "נמחקה מכונת הקמה: $vm"; } || true
done
for n in esther-dc-01-nic$SUF esther-adaxes-01-nic$SUF esther-linux-01-se-nic$SUF; do
  az network nic show -g $RG -n "$n" -o none 2>/dev/null && { az network nic delete -g $RG -n "$n" --only-show-errors -o none; echo "נמחק NIC הקמה: $n"; } || true
done
for d in esther-dc-01-osdisk$SUF esther-adaxes-01-osdisk$SUF esther-linux-01-osdisk$SUF; do
  az disk show -g $RG -n "$d" -o none 2>/dev/null && { az disk delete -g $RG -n "$d" --yes --only-show-errors -o none; echo "נמחק דיסק הקמה: $d"; } || true
done
echo "== החזרת כתובות ל-NICs המקוריים =="
az network nic ip-config update -g $RG --nic-name esther-dc-01-nic -n ipconfig1 --private-ip-address $NET.1.10 --only-show-errors -o none
az network nic ip-config update -g $RG --nic-name esther-adaxes-01-nic -n ipconfig1 --private-ip-address $NET.1.4 --only-show-errors -o none
az network nic ip-config update -g $RG --nic-name esther-linux-01-se-nic -n ipconfig1 --private-ip-address $SENET.1.20 --only-show-errors -o none
echo "== יצירת 3 המכונות מהדיסקים השמורים =="
az vm create -g $RG -n esther-dc-01 -l israelcentral --attach-os-disk esther-dc-01-osdisk --os-type windows --nics esther-dc-01-nic --size Standard_B2ats_v2 --only-show-errors -o none && echo "חזר: esther-dc-01"
az vm create -g $RG -n esther-adaxes-01 -l israelcentral --attach-os-disk esther-adaxes-01-osdisk --os-type windows --nics esther-adaxes-01-nic --size Standard_B2as_v2 --only-show-errors -o none && echo "חזר: esther-adaxes-01"
az vm create -g $RG -n esther-linux-01 -l swedencentral --attach-os-disk esther-linux-01-osdisk --os-type linux --nics esther-linux-01-se-nic --size Standard_B2ats_v2 --only-show-errors -o none && echo "חזר: esther-linux-01"
az vm list -g $RG --query "[].{vm:name,power:powerState}" -d -o table 2>/dev/null || az vm list -g $RG -o table
echo "✅ שחזור הושלם — 3 המכונות חזרו מהדיסקים"
