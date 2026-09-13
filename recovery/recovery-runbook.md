# recovery/recovery-runbook.md
## Установка
1. `sudo bash recovery/build-recovery.sh`
2. `sudo install -m755 recovery/40_konotop /etc/grub.d/40_konotop`
3. `sudo update-grub`

## Первый золотой снимок / re-bless (удалённо)
1. Обкатать изменения на живой системе.
2. `sudo grub-reboot 'ВОССТАНОВИТЬ...'` НЕЛЬЗЯ для rebless — нужен отдельный
   grub-пункт «Снять снимок»: аналог recovery, но запускает rebless.sh.
   (Добавить menuentry 'Снять золотой снимок' с konotop.rebless=1.)
3. `sudo grub-reboot 'Снять золотой снимок' && sudo reboot`
4. Recovery снимет p2->p3, вернётся в обычную загрузку.

## Проверка кнопки восстановления
- Испортить файл в p2, выбрать «ВОССТАНОВИТЬ» в GRUB → файл вернулся,
  содержимое /srv/data и /srv/persist не изменилось.
