#!/usr/bin/env bash
# AWS adapter: SSM Run Command. Roles map to instance tags (Role=dc|scom|linux-agent from the tofu module).
# Requires SSM agent (present on Amazon Windows/Ubuntu AMIs) + an instance profile - noted in tofu outputs.
set -euo pipefail
ROLE=$1; SCRIPT=$2; shift 2
case $ROLE in
  dc)     TAG=dc;          DOC=AWS-RunPowerShellScript;;
  esther) TAG=scom;        DOC=AWS-RunPowerShellScript;;
  linux)  TAG=linux-agent; DOC=AWS-RunShellScript;;
  *) echo "unknown role: $ROLE" >&2; exit 64;;
esac
[[ $SCRIPT == *.sh && $DOC == AWS-RunPowerShellScript ]] && { echo "role $ROLE is Windows; use .ps1" >&2; exit 64; }
[[ $SCRIPT == *.ps1 && $DOC == AWS-RunShellScript ]] && { echo "role $ROLE is Linux; use .sh" >&2; exit 64; }
IID=$(aws ec2 describe-instances --filters "Name=tag:Role,Values=$TAG" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || true)
CMDLINE="aws ssm send-command --instance-ids <iid> --document-name $DOC --parameters '{\"commands\":[\"$(basename "$SCRIPT")\"]}' # script delivered via S3 staging"
if [ "${PRINT:-0}" = 1 ]; then
  echo "aws ec2 describe-instances --filters Name=tag:Role,Values=$TAG  # -> instance id"
  echo "aws s3 cp $SCRIPT s3://\$MEDIA_BUCKET/exec/ && $CMDLINE"
  exit 0
fi
[ -n "$IID" ] && [ "$IID" != None ] || { echo "no running instance with Role=$TAG" >&2; exit 1; }
: "${MEDIA_BUCKET:?media bucket for script staging}"
KEY="exec/$(basename "$SCRIPT")"
aws s3 cp "$SCRIPT" "s3://$MEDIA_BUCKET/$KEY" >/dev/null
if [ "$DOC" = AWS-RunPowerShellScript ]; then
  PS="Invoke-WebRequest -Uri 'https://$MEDIA_BUCKET.s3.amazonaws.com/$KEY' -OutFile 'C:\\scomlab\\$KEY'; & 'C:\\scomlab\\$KEY'"
  CID=$(aws ssm send-command --instance-ids "$IID" --document-name "$DOC" \
    --parameters "{\"commands\":[\"$PS\"]}" --query 'Command.CommandId' --output text)
else
  CID=$(aws ssm send-command --instance-ids "$IID" --document-name "$DOC" \
    --parameters "{\"commands\":[\"curl -fsSL https://$MEDIA_BUCKET.s3.amazonaws.com/$KEY | bash\"]}" --query 'Command.CommandId' --output text)
fi
for i in $(seq 1 60); do
  ST=$(aws ssm get-command-invocation --command-id "$CID" --instance-id "$IID" --query 'Status' --output text 2>/dev/null || echo Pending)
  case $ST in Success) aws ssm get-command-invocation --command-id "$CID" --instance-id "$IID" --query 'StandardOutputContent' --output text; exit 0;;
    Failed|Cancelled|TimedOut) aws ssm get-command-invocation --command-id "$CID" --instance-id "$IID" --query 'StandardErrorContent' --output text >&2; exit 1;;
  esac; sleep 10
done
echo "SSM command still running after 10m: $CID" >&2; exit 1
