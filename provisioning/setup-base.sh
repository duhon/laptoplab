#!/usr/bin/env bash
# provisioning/setup-base.sh — базовая настройка Debian. Запуск от root.
set -euo pipefail
PUBKEY="${1:?usage: setup-base.sh 'ssh-ed25519 AAAA... user'}"

# SSH: ключи вместо пароля
install -d -m700 /root/.ssh
echo "$PUBKEY" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# Питание/тишина
apt-get update
apt-get install -y tlp hdparm unattended-upgrades
systemctl enable --now tlp

# CPU governor powersave
echo 'GOVERNOR=powersave' >> /etc/default/cpufrequtils || true

# Спиндаун HDD в простое (5 минут). /dev/sdb — HDD, проверить lsblk!
cat >/etc/systemd/system/hdd-spindown.service <<'EOF'
[Unit]
Description=HDD spindown
[Service]
Type=oneshot
ExecStart=/sbin/hdparm -S 60 -B 127 /dev/disk/by-label/data
[Install]
WantedBy=multi-user.target
EOF
systemctl enable hdd-spindown.service

# Автоматические security-обновления
dpkg-reconfigure -f noninteractive unattended-upgrades

systemctl restart ssh
echo "Базовая настройка завершена."
