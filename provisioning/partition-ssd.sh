#!/usr/bin/env bash
# provisioning/partition-ssd.sh — разметка SSD (GPT). ОПАСНО: стирает диск.
set -euo pipefail
DISK="${1:?usage: partition-ssd.sh /dev/sdX}"

read -rp "Стереть ВЕСЬ $DISK? Введи YES: " ok
[[ "$ok" == "YES" ]] || { echo "отмена"; exit 1; }

sgdisk --zap-all "$DISK"
sgdisk -n1:0:+1G   -t1:ef00 -c1:ESP       "$DISK"
sgdisk -n2:0:+170G -t2:8300 -c2:root      "$DISK"
sgdisk -n3:0:+50G  -t3:8300 -c3:recovery  "$DISK"
sgdisk -n4:0:+2G   -t4:8300 -c4:persist   "$DISK"
partprobe "$DISK"

mkfs.vfat -F32 "${DISK}1"
mkfs.ext4 -F   "${DISK}2"
mkfs.ext4 -F   "${DISK}3"
mkfs.ext4 -F   "${DISK}4"
echo "Готово. Разделы:"; sgdisk -p "$DISK"
