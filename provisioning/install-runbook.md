# Установка Debian и BIOS (на T420)

## BIOS (юзкейс 1 — автозапуск при питании)
1. F1 при загрузке → Config → Power.
2. `After Power Loss = Power On`.
3. Boot order: SSD первым.
4. Сохранить (F10).

## Установка Debian stable
1. Загрузиться с USB (netinst).
2. Expert/manual: НЕ давать инсталлятору переразметить — разделы уже созданы
   (Task 1). Назначить точки монтирования по `fstab.sample`.
3. Software selection: снять всё, кроме "standard system utilities" и "SSH server".
4. GRUB → в ESP (`/dev/sdX`).
5. Первая загрузка, `ssh` работает по паролю временно (заменим на ключи в Task 3).

## Форматирование HDD (данные)
1 ТБ HDD (отдельный диск, напр. /dev/sdb) под данные:
`sudo mkfs.ext4 -L data /dev/sdY`   # подставить реальный диск (НЕ SSD!)
Метка `data` обязательна — на неё ссылаются fstab.sample и hdd-spindown.service.

## Проверка
- `sudo systemctl is-enabled ssh` → enabled
- Обесточить и подать питание → ноут стартует сам.
