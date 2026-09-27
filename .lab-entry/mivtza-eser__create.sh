#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID ESTHER_VM_ADMIN_PASSWORD ESTHER_DSRM_PASSWORD ESTHER_SCOM_SVC_PASSWORD GH_TOKEN MEDIA_ACCOUNT
echo "== מבצע עשר: יצירת רשת + שתי מכונות במקביל =="
bash rebuild/v2/create.sh
