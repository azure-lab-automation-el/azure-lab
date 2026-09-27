#!/usr/bin/env bash
# Runs ON the Linux VM (run-command). Creates the lab SCX monitoring user; SSH password login allowed only from the lab VNet.
set -euo pipefail
SCXPW="${1:?}"; SCXPUB="$(echo "${2:?}" | base64 -d)"
id scxmon >/dev/null 2>&1 || useradd -m -s /bin/bash scxmon
echo "scxmon:${SCXPW}" | chpasswd
echo 'scxmon ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/90-scxmon; chmod 440 /etc/sudoers.d/90-scxmon
cat > /etc/ssh/sshd_config.d/60-scxmon.conf <<'C'
Match User scxmon Address ${LAB_NET_BASE:-10.77}.0.0/16
    PasswordAuthentication yes
    KbdInteractiveAuthentication yes
C
sshd -t && systemctl restart ssh.socket ssh.service 2>/dev/null || systemctl restart ssh
install -d -m 700 -o scxmon -g scxmon /home/scxmon/.ssh; grep -qxF "$SCXPUB" /home/scxmon/.ssh/authorized_keys 2>/dev/null || echo "$SCXPUB" >> /home/scxmon/.ssh/authorized_keys; chown scxmon:scxmon /home/scxmon/.ssh/authorized_keys; chmod 600 /home/scxmon/.ssh/authorized_keys
hostnamectl --static; id scxmon; echo HOST_PREP_OK
