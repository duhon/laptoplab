#!/usr/bin/env bash
# recovery/restore.sh — восстановить p2 из золотого снимка. Запуск ТОЛЬКО в recovery-среде.
set -euo pipefail
ROOT_PART="${ROOT_PART:?e.g. /dev/sda2}"
REC_PART="${REC_PART:?e.g. /dev/sda3}"

mkdir -p /mnt/recovery
mount "$REC_PART" /mnt/recovery
IMG=/mnt/recovery/golden.current.img
[[ -f "$IMG" ]] || { echo "нет снимка $IMG"; exit 1; }

echo "Восстанавливаю $ROOT_PART из $IMG ..."
partclone.restore -s "$IMG" -O "$ROOT_PART" -F
sync
umount /mnt/recovery
echo "Готово. Перезагрузка..."
