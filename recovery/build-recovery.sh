#!/usr/bin/env bash
# recovery/build-recovery.sh — initramfs с partclone + restore/rebless + диспетчер cmdline
set -euo pipefail
apt-get install -y dracut partclone

MOD=/usr/lib/dracut/modules.d/99konotop
install -d "$MOD"
install -Dm755 recovery/restore.sh /usr/lib/konotop/restore.sh
install -Dm755 recovery/rebless.sh /usr/lib/konotop/rebless.sh

# dracut-модуль: кладёт скрипты и хук pre-mount
cat >"$MOD/module-setup.sh" <<'EOF'
#!/bin/bash
check() { return 0; }
depends() { echo bash; }
install() {
    inst_multiple partclone.restore partclone.ext4 partclone.chkimg mount umount blkid reboot sync
    inst /usr/lib/konotop/restore.sh /usr/lib/konotop/restore.sh
    inst /usr/lib/konotop/rebless.sh /usr/lib/konotop/rebless.sh
    inst_hook pre-mount 50 "$moddir/konotop-dispatch.sh"
}
EOF

# диспетчер: читает /proc/cmdline и запускает нужный скрипт.
# Для обычной загрузки ставит boot-флаг на p4; если старый флаг остался,
# предыдущая загрузка сорвалась и запускается автоматическое восстановление.
cat >"$MOD/konotop-dispatch.sh" <<'EOF'
#!/bin/sh
set +e
CMDLINE=$(cat /proc/cmdline)
case "$CMDLINE" in
  *konotop.recover=1*) MODE=recover ;;
  *konotop.rebless=1*) MODE=rebless ;;
  *)
    ROOT_PART=/dev/disk/by-label/root
    REC_PART=/dev/disk/by-label/recovery
    PERSIST_PART=/dev/disk/by-label/persist
    mkdir -p /mnt/boot-guard
    if mount "$PERSIST_PART" /mnt/boot-guard 2>/dev/null; then
      if [ -e /mnt/boot-guard/boot-in-progress ]; then
        MODE=auto-recover
        touch /mnt/boot-guard/boot-recovery-started
        umount /mnt/boot-guard 2>/dev/null || true
        bash /usr/lib/konotop/restore.sh
        rc=$?
        if mkdir -p /mnt/reclog && mount "$REC_PART" /mnt/reclog 2>/dev/null; then
          echo "$(cat /proc/uptime) mode=$MODE rc=$rc cmdline=$CMDLINE" >> /mnt/reclog/last-recovery.log
          umount /mnt/reclog 2>/dev/null || true
        fi
        if [ "$rc" -eq 0 ] && mount "$PERSIST_PART" /mnt/boot-guard 2>/dev/null; then
          rm -f /mnt/boot-guard/boot-in-progress /mnt/boot-guard/boot-recovery-started
          umount /mnt/boot-guard 2>/dev/null || true
        fi
        sync
        reboot -f
      fi
      touch /mnt/boot-guard/boot-in-progress
      sync
      umount /mnt/boot-guard 2>/dev/null || true
    fi
    exit 0
    ;;
esac
for tok in $CMDLINE; do
  case "$tok" in
    ROOT_PART=*) export ROOT_PART="${tok#ROOT_PART=}" ;;
    REC_PART=*)  export REC_PART="${tok#REC_PART=}" ;;
  esac
done
# ВАЖНО: bash, а не sh — скрипты используют bash-синтаксис ([[ ]])
if [ "$MODE" = recover ] || [ "$MODE" = auto-recover ]; then
  bash /usr/lib/konotop/restore.sh
else
  bash /usr/lib/konotop/rebless.sh
fi
rc=$?
# журнал результата на p3 для пост-мортема (пишется и при провале)
if mkdir -p /mnt/reclog && mount "$REC_PART" /mnt/reclog 2>/dev/null; then
  echo "$(cat /proc/uptime) mode=$MODE rc=$rc cmdline=$CMDLINE" >> /mnt/reclog/last-recovery.log
  umount /mnt/reclog 2>/dev/null || true
fi
if [ "$rc" -ne 0 ]; then
  echo "konotop: '$MODE' FAILED rc=$rc — загрузка в обычном режиме для диагностики" > /dev/kmsg 2>/dev/null || true
fi
if [ "$rc" -eq 0 ]; then
  PERSIST_PART=/dev/disk/by-label/persist
  mkdir -p /mnt/boot-guard
  if mount "$PERSIST_PART" /mnt/boot-guard 2>/dev/null; then
    rm -f /mnt/boot-guard/boot-in-progress /mnt/boot-guard/boot-recovery-started
    umount /mnt/boot-guard 2>/dev/null || true
  fi
fi
sync
reboot -f
EOF
chmod +x "$MOD/konotop-dispatch.sh"

dracut --force --no-hostonly --add konotop /boot/konotop-recovery.img "$(uname -r)"

# Дублируем recovery-образ и ядро на ESP, чтобы восстановление грузилось даже при повреждённом p2
cp "/boot/konotop-recovery.img" /boot/efi/konotop-recovery.img
cp "/boot/vmlinuz-$(uname -r)" /boot/efi/konotop-vmlinuz
echo "recovery initramfs: /boot/konotop-recovery.img (+ копия на ESP /boot/efi/)"
