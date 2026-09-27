#!/usr/bin/env bash
# Best-effort media warmer: pulls SQL+SSRS+SCOM media onto the Esther VM in parallel with the
# DC build and domain join, so phase 3 download and phase 4 scomextract become Test-Path no-ops.
# Never blocks the rebuild: on repeated failure it exits 0 and the sql/prereq jobs pull media themselves.
set -uo pipefail
export AZURE_SUBSCRIPTION_ID ESTHER_VM_ADMIN_PASSWORD ESTHER_DSRM_PASSWORD ESTHER_SCOM_SVC_PASSWORD GH_TOKEN MEDIA_ACCOUNT
echo "== Pre-pull SQL+SSRS+SCOM media to Esther VM (parallel with DC+join; best effort) =="
warm() { local name=$1; shift
  for a in 1 2 3 4 5; do
    if "$@"; then echo "PRELOAD_${name}_OK"; return 0; fi
    echo "preload $name attempt $a failed (VM busy with join/resize); retrying in 30s"; sleep 30
  done
  echo "PRELOAD_${name}_SKIPPED - the dependent job will pull it itself"; }
warm SQL STAGES=download bash scripts/esther-scom-phase3.sh
warm SCOM env RESTART=false STAGES=prereq.ps1:scomextract bash scripts/esther-scom-phase4.sh
exit 0
