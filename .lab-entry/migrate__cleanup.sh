#!/usr/bin/env bash
# שלב 5 (אחרי אור ירוק בלבד): מחיקת הגיבויים — דיסקים ישנים, NICs חונים, snapshots.
set -euo pipefail
RG=rg-learning-monitoring
for d in esther-dc-01-osdisk esther-adaxes-01-osdisk esther-linux-01-osdisk; do
  az disk show -g $RG -n $d -o none 2>/dev/null && { az disk delete -g $RG -n $d --yes --only-show-errors -o none; echo "נמחק דיסק ישן: $d"; } || echo "כבר נמחק: $d"
done
for n in esther-dc-01-nic esther-adaxes-01-nic esther-linux-01-se-nic; do
  az network nic show -g $RG -n $n -o none 2>/dev/null && { az network nic delete -g $RG -n $n --only-show-errors -o none; echo "נמחק NIC ישן: $n"; } || echo "כבר נמחק: $n"
done
for s in mig-dc mig-adaxes mig-linux; do
  az snapshot show -g $RG -n $s -o none 2>/dev/null && { az snapshot delete -g $RG -n $s --only-show-errors -o none; echo "נמחק snapshot: $s"; } || echo "כבר נמחק: $s"
done
echo "✅ ניקוי הושלם — נשארה רק השכבה החדשה"
