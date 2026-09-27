#!/usr/bin/env bash
set -euo pipefail
export AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID}"
export ESTHER_VM_ADMIN_PASSWORD="${ESTHER_VM_ADMIN_PASSWORD}"
export ESTHER_DSRM_PASSWORD="${ESTHER_DSRM_PASSWORD}"
export ESTHER_SCOM_SVC_PASSWORD="${ESTHER_SCOM_SVC_PASSWORD}"
export GH_TOKEN="${GH_TOKEN}"
export LINUX_SCX_PASSWORD="${LINUX_SCX_PASSWORD}"
export LINUX_SCX_SSH_KEY="${LINUX_SCX_SSH_KEY}"
export LINUX_SCX_PPK_B64="${LINUX_SCX_PPK_B64}"
export LAB_AGENT_PAT="${LAB_AGENT_PAT}"
export GH_REPO="${GH_REPO}"
export ROTATE_KEY="${ROTATE_KEY}"
ENTRY_FAILED=0
echo "== Linux VM Sweden Central (policy, network, vm) =="
for s in policy network vm; do STAGE=$s bash scripts/esther-sweden.sh; done
