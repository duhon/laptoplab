#!/usr/bin/env bash
# provisioning/setup-base.sh — базовая настройка Debian. Запуск от root.
set -euo pipefail
PUBKEY="${1:?usage: setup-base.sh 'ssh-ed25519 AAAA... user'}"
ADMIN_USER="${2:-duhon}"

# SSH: вход только по ключу, root по SSH полностью запрещён.
install -d -m700 "/home/$ADMIN_USER/.ssh"
grep -qxF "$PUBKEY" "/home/$ADMIN_USER/.ssh/authorized_keys" 2>/dev/null || echo "$PUBKEY" >> "/home/$ADMIN_USER/.ssh/authorized_keys"
chown -R "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.ssh"
chmod 600 "/home/$ADMIN_USER/.ssh/authorized_keys"
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Питание/тишина
apt-get update
apt-get install -y tlp hdparm unattended-upgrades
install -Dm644 provisioning/tlp.d/50-hdd-spindown.conf /etc/tlp.d/50-hdd-spindown.conf
systemctl enable --now tlp

# Keep the supported schedutil governor provided by the T420 kernel.

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

# Boot guard: recovery-initrd creates this marker before normal boot;
# this service removes it after userspace reaches multi-user.target.
install -Dm644 provisioning/konotop-boot-guard.service \
  /etc/systemd/system/konotop-boot-guard.service
install -Dm644 provisioning/konotop-boot-arm.service \
  /etc/systemd/system/konotop-boot-arm.service
systemctl daemon-reload
systemctl enable konotop-boot-guard.service
systemctl enable konotop-boot-arm.service

# Сеть: разрешить bind на ещё не поднятые интерфейсы (для Tailscale IP в Docker на старте)
cat >/etc/sysctl.d/99-nonlocal-bind.conf <<'EOF'
net.ipv4.ip_nonlocal_bind = 1
EOF
sysctl -p /etc/sysctl.d/99-nonlocal-bind.conf || true

# Автоматические security-обновления
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'AUTO'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
AUTO

systemctl restart ssh
install -Dm644 provisioning/logind.conf.d/50-konotop-lid.conf \
  /etc/systemd/logind.conf.d/50-konotop-lid.conf
systemctl kill -s HUP systemd-logind.service || true
# A headless server must not suspend because of a lid/ACPI event.
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
echo "Базовая настройка завершена."
