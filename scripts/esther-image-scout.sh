#!/usr/bin/env bash
# Read-only: plan + terms for third-party AD DC images in israelcentral.
set -uo pipefail
L=israelcentral
for urn in \
  cloud-infrastructure-services:ad-dc-2022:ad-dc-2022:latest \
  tidalmediainc:active-directory-2019:active-directory-2019:latest; do
  echo "== $urn"
  az vm image show -l "$L" --urn "$urn" --query "{planName:plan.name,planPublisher:plan.publisher,planProduct:plan.product}" -o json 2>&1 | head -6
  az vm image terms show --urn "$urn" --query "{accepted:accepted,licenseTextLink:licenseTextLink}" -o json 2>&1 | head -6
done
