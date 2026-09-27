# exec/ - cloud-agnostic post-config transport
Same scripts/scom/*.ps1 + bash installers, any cloud. Dispatcher: `run.sh [--print] <cloud> <role> <script> [k=v]`.
Roles: dc / esther / linux. --print shows the exact command with no cloud calls (validation mode).
- azure.sh: az vm run-command (the live transport today)
- aws.sh:   SSM Run Command, role->instance via tag Role (dc|scom|linux-agent), script staged through the media bucket
- gcp.sh:   gcloud compute ssh/scp for Linux; Windows via WinRM after a one-time bootstrap - pending his approval, execute mode exits 2 until then
Windows/Linux mismatch is rejected (ps1 on Linux / sh on Windows).
