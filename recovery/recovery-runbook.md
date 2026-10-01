# recovery/recovery-runbook.md
## Установка
1. `sudo bash recovery/build-recovery.sh`
2. `sudo install -m755 recovery/40_konotop /etc/grub.d/05_konotop`
3. В `/etc/default/grub` задать `GRUB_TIMEOUT=10`, `GRUB_RECORDFAIL_TIMEOUT=10`,
   `GRUB_TIMEOUT_STYLE=menu`
   и `GRUB_TERMINAL=console` (текстовый режим меню использует подписи на английском).
4. `sudo update-grub`; проверить `/boot/grub/grub.cfg` и запланировать проверку
   меню на следующей перезагрузке.

## Первый золотой снимок / re-bless (удалённо)
1. Обкатать изменения на живой системе.
2. Не использовать recovery-пункт: для re-bless нужен отдельный пункт
   `Create golden snapshot (admin)` с `--id konotop-rebless`.
3. `sudo grub-reboot konotop-rebless && sudo reboot`
4. Recovery снимет p2->p3, вернётся в обычную загрузку.

## Проверка кнопки восстановления
- Испортить файл в p2, выбрать `Restore system (data is preserved)` в GRUB → файл вернулся,
  содержимое /srv/data и /srv/persist не изменилось.

## Устойчивость при повреждённом p2
build-recovery.sh дублирует recovery-образ и ядро на ESP (/boot/efi/). Если /boot
на p2 станет нечитаемым, при развёртывании настроить пункт GRUB на загрузку
konotop-vmlinuz + konotop-recovery.img с ESP. Проверить на железе.
