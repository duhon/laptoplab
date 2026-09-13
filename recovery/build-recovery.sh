#!/usr/bin/env bash
# recovery/build-recovery.sh — минимальный initramfs с partclone + restore.sh
set -euo pipefail
apt-get install -y dracut partclone
install -Dm755 recovery/restore.sh /usr/lib/konotop/restore.sh
dracut --force --no-hostonly \
  --install "partclone.restore partclone.ext4 partclone.chkimg mount umount" \
  --include recovery/restore.sh /usr/lib/konotop/restore.sh \
  /boot/konotop-recovery.img "$(uname -r)"
echo "recovery initramfs: /boot/konotop-recovery.img"
