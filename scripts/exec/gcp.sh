#!/usr/bin/env bash
# GCP adapter: gcloud compute ssh/scp for Linux; Windows via WinRM after a one-time bootstrap
# (reset-windows-password + firewall rule) - the bootstrap is printed in --print mode and is
# the only pending piece; execute mode for Windows exits 2 until he approves enabling WinRM.
set -euo pipefail
ROLE=$1; SCRIPT=$2; shift 2
ZONE=${GCP_ZONE:-europe-west1-b}
case $ROLE in
  dc)     VM=esther-dc-01;     OS=windows;;
  esther) VM=esther-adaxes-01; OS=windows;;
  linux)  VM=esther-linux-01;  OS=linux;;
  *) echo "unknown role: $ROLE" >&2; exit 64;;
esac
if [ "$OS" = linux ]; then
  if [ "${PRINT:-0}" = 1 ]; then
    echo "gcloud compute scp $SCRIPT $VM:/tmp/$(basename "$SCRIPT") --zone $ZONE"
    echo "gcloud compute ssh $VM --zone $ZONE --command 'bash /tmp/$(basename "$SCRIPT")'"
    exit 0
  fi
  gcloud compute scp "$SCRIPT" "$VM:/tmp/$(basename "$SCRIPT")" --zone "$ZONE" --quiet
  gcloud compute ssh "$VM" --zone "$ZONE" --quiet --command "bash /tmp/$(basename "$SCRIPT")"
else
  echo "gcloud compute reset-windows-password $VM --zone $ZONE  # one-time WinRM bootstrap (pending his approval)" >&2
  echo "powershell over WinRM 5986: $(basename "$SCRIPT")" >&2
  [ "${PRINT:-0}" = 1 ] && exit 0
  echo "gcp windows adapter pending WinRM bootstrap approval" >&2; exit 2
fi
