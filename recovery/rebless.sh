#!/usr/bin/env bash
# recovery/rebless.sh — снять НОВЫЙ золотой снимок p2 -> p3. Запуск в recovery-среде (p2 не смонтирован).
set -euo pipefail
ROOT_PART="${ROOT_PART:?}"; REC_PART="${REC_PART:?}"
[ "$ROOT_PART" != "$REC_PART" ] || { echo "ROOT_PART == REC_PART — abort"; exit 1; }
mkdir -p /mnt/recovery; mount "$REC_PART" /mnt/recovery
trap 'umount /mnt/recovery 2>/dev/null || true' EXIT
NEW=/mnt/recovery/golden.new.img; CUR=/mnt/recovery/golden.current.img

echo "Снимаю $ROOT_PART -> $NEW ..."
partclone.ext4 -c -s "$ROOT_PART" -O "$NEW" -F

# Проверка целостности нового снимка перед заменой
partclone.chkimg -s "$NEW"
mv -f "$NEW" "$CUR"
sync; umount /mnt/recovery
echo "Новый золотой снимок зафиксирован."
