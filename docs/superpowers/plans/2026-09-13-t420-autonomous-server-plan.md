# T420 Autonomous Server («konotop») Implementation Plan

> Статус проекта обновлён 2026-09-28. Ниже отдельно указано, что реально
> проверено на T420, а что пока существует только в репозитории.

## Актуальный статус проекта

### Уже сделано на T420

- Debian установлен, SSD размечен, HDD подключён как `/srv/data`.
- SSH работает через ключ пользователя `duhon`; парольная и root-аутентификация по SSH отключены.
- Tailscale установлен, доступ к T420 через tailnet проверен.
- Имя системы изменено на `konotop`.
- Автозапуск при подключении питания включён в BIOS (`OnByAcAttach=Enable`); после сбоя снова работает, но поведение нестабильно — наблюдать.
- Сон при закрытии крышки отключён.
- Ошибки fingerprint и `nouveau` устранены настройками BIOS.
- GRUB настроен в текстовом режиме: английские подписи, таймаут 10 секунд, обычная загрузка по умолчанию; конфигурация проверена и ноут перезагружен.
- Механизм автоматического выбора recovery после неудачной загрузки проверен.
- Восстановление системы через GRUB проверено.
- Docker Compose запущен: Caddy, qBittorrent, FileBrowser, Homepage и Portainer.
- Homepage и FileBrowser исправлены для работы через Caddy.
- Portainer подключён к локальному Docker через socket.
- Telegram bot и личный чат проверены тестовым сообщением; SMS-мост запущен.
- Проверки Task 3 выполнены: TLP и автообновления активны, HDD уходит в standby; найдены расхождения в SSH, governor и APM.
- Создан golden snapshot системы; после финальных изменений его нужно обновить.
- Пароль qBittorrent сменён, доступ проверен.

### Осталось сделать — по фазам

- **Фаза 3 — сеть (основной путь):** NAS в tailnet; NAS Homepage на мосту, ссылки на сервисы konotop, SSH TCP-релей и SOCKS5-релей настроены и проверены. SOCKS5-профиль браузера на рабочем ноуте настроен и проверен; изменения зафиксированы.
- **Фаза 4 — сервисы:** проверить Homepage, qBittorrent, FileBrowser и Portainer через выбранный сетевой путь.
- **Фаза 5 — SMS:** проверить реальную пересылку после регистрации MC7304 и выяснить голосовые возможности.
- **Фаза 6 — финализация:** после отладки ограничить SSH tailnet-IP, проверить загрузку/recovery/крышку/автозапуск, решить APM-конфликт, обновить golden snapshot, запустить тесты и зафиксировать изменения.
- **Фаза 7 — опциональные альтернативы:** Cloudflare Tunnel, SOCKS5, прямой прокси/VM-релей — только если NAS-мост не подойдёт или нужен публичный адрес.

### Отложенные этапы

- SMS→Telegram: мост запущен, но MC7304 в состоянии `searching`; проверить пересылку после регистрации модема в сети. Голосовая проверка отдельно.
- Cloudflare Tunnel (Phase 7): не настроен; домена пока нет. Только если нужен публичный адрес панели.
- SOCKS5/VM-релей (Phase 7): конфигурации подготовлены как fallback к NAS-мосту.
- Dry-run разметки закрыт как ненужный для уже установленной и работающей системы; `rebless` и `restore` проверены на двух временных loop-дисках в Linux-контейнере Docker Desktop VM (без загрузки отдельной гостевой VM).

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Превратить ThinkPad T420 в тихий, самовосстанавливающийся домашний сервер у родителей, управляемый удалённо, с торрентами, SMS→Telegram, exit-прокси и веб-панелью.

**Architecture:** Debian stable на SSD (разделы ОС/снимок/персистент), данные на HDD. Восстановление — снимок раздела через partclone, запуск из GRUB. Сеть — Tailscale для приватного доступа и exit-node; рабочий ноут без Tailscale использует Docker-мост на NAS для панели, SSH TCP-релея и SOCKS5. Tailscale Serve публикует панель только внутри tailnet; Funnel разрешён, но не настроен. Cloudflare Tunnel остаётся опциональным публичным вариантом. Сервисы в Docker за Caddy. Конфиг как код в этом репозитории — источник правды для «золотого» состояния.

**Tech Stack:** Debian stable, Docker + docker-compose, Caddy, Tailscale, cloudflared, partclone, GRUB, ModemManager (`mmcli`), Python 3.11 (SMS-мост), qBittorrent, filebrowser, Homepage.

**Spec:** `docs/superpowers/specs/2026-08-30-t420-autonomous-server-design.md`

## Global Constraints

- ОС: **Debian stable** (не иммутабельная, не btrfs-снапшоты).
- Восстановление НИКОГДА не форматирует p3, p4 и HDD.
- Секреты — только на p4 (или в `.env`, подхватываемом из p4); **никогда** не коммитятся в git.
- Внутренние веб-морды не публикуются напрямую; доступ через Tailscale/NAS-мост. Публичный доступ допустим только через отдельную защиту, например Cloudflare Access.
- SSH — только по ключам, слушает только на интерфейсе Tailscale.
- Форвард-прокси, доступный из интернета, обязан иметь аутентификацию.
- Разметка SSD 240 ГБ: `p1 ESP ~1ГБ` · `p2 root ~170ГБ` · `p3 снимок+recovery ~50ГБ` · `p4 персистент ~2ГБ`. HDD 1ТБ → `/srv/data`.
- Все docker-данные пользователя (загрузки/файлы) — на HDD (`/srv/data`), не на SSD.
- Сетевой путь для рабочего ноутбука выбирается в Phase 3; голосовые возможности MC7304 проверяются в Phase 5.

---

## File Structure

Репозиторий `konotop` — источник правды (конфиги + код). Создаётся в Task 0.

```
konotop/
├── docs/superpowers/{specs,plans}/       # спека + этот план
├── provisioning/
│   ├── install-runbook.md                # Phase 1: разметка + Debian (на железе)
│   ├── partition-ssd.sh                  # скрипт разметки SSD
│   ├── setup-base.sh                     # SSH, TLP, governor, спиндаун, unattended-upgrades
│   └── fstab.sample
├── recovery/
│   ├── restore.sh                        # p3 -> p2
│   ├── rebless.sh                        # p2 -> p3
│   ├── build-recovery.sh                 # сборка recovery-initramfs
│   ├── 40_konotop                        # пункты GRUB
│   └── recovery-runbook.md
├── network/
│   ├── tailscale-runbook.md
│   ├── sshd_konotop.conf                 # харденинг + bind на tailnet
│   └── cloudflared/{config.yml,runbook.md}
├── services/
│   ├── docker-compose.yml                # caddy, qbittorrent, filebrowser, homepage
│   ├── Caddyfile
│   ├── homepage/{services.yaml,settings.yaml,widgets.yaml}
│   └── .env.sample
├── sms-bridge/
│   ├── pyproject.toml
│   ├── src/sms_bridge/{__init__.py,modem.py,telegram.py,bridge.py,config.py,__main__.py}
│   ├── tests/{test_modem.py,test_telegram.py,test_bridge.py}
│   └── Dockerfile
├── proxy/
│   ├── socks5-compose.yml                # личные устройства (bind на tailnet)
│   ├── forward-proxy-compose.yml         # рабочий ноут, случай 1 (бокс:443)
│   ├── cgnat-check.md                    # спайк
│   └── relay-runbook.md                  # рабочий ноут, случай 2 (бесплатный VM)
├── secrets/README.md                     # раскладка p4 (сами секреты НЕ в git)
├── .gitignore
└── README.md
```

---

## Phase 0 — Репозиторий

### Task 0: Инициализация репозитория

**Files:**
- Create: `.gitignore`, `README.md`, `secrets/README.md`

- [x] **Step 1: Инициализировать git**

```bash
cd /private/tmp/konotop
git init
git add docs/superpowers/specs/2026-08-30-t420-autonomous-server-design.md
git commit -m "docs: add design spec"
```

- [x] **Step 2: Создать .gitignore (секреты никогда не в git)**

```gitignore
# secrets & runtime
**/.env
secrets/*
!secrets/README.md
*.key
*.pem
*_token
cloudflared/*.json
# python
__pycache__/
*.pyc
.venv/
.pytest_cache/
```

- [x] **Step 3: Создать README.md**

```markdown
# konotop — автономный сервер на ThinkPad T420

Источник правды для конфигурации домашнего сервера. См.
`docs/superpowers/specs/` (дизайн) и `docs/superpowers/plans/` (план).

Секреты живут на разделе p4 сервера и НЕ хранятся здесь.
```

- [x] **Step 4: Создать secrets/README.md (раскладка p4)**

```markdown
# Персистентная зона (p4) — вне восстановления

Recovery НИКОГДА не форматирует p4. Здесь лежат:
- tailscale/           — состояние ноды Tailscale (--statedir)
- cloudflared/         — токен туннеля, cert.json
- services.env         — TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, пароли сервисов
- proxy/               — креды форвард-прокси

Монтируется в /srv/persist. Симлинки/bind-mount из системы указывают сюда.
```

- [x] **Step 5: Commit**

```bash
git add .gitignore README.md secrets/README.md
git commit -m "chore: repo scaffolding, gitignore, secrets layout"
```

---

## Phase 1 — Foundation (на железе: runbook + скрипты)

> Эти задачи выполняются на самом T420. «Тест» здесь — команда проверки и её ожидаемый вывод.

### Task 1: Скрипт разметки SSD

**Files:**
- Create: `provisioning/partition-ssd.sh`, `provisioning/fstab.sample`

**Interfaces:**
- Produces: разделы `/dev/sdX1..4` (ESP, root, recovery, persist).

- [x] **Step 1: Написать скрипт разметки**

```bash
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
```

- [x] **Step 2: Создать fstab.sample**

```
# provisioning/fstab.sample — подставить UUID из `blkid`
UUID=<ESP>      /boot/efi   vfat  umask=0077                 0 2
UUID=<root>     /           ext4  errors=remount-ro          0 1
UUID=<persist>  /srv/persist ext4 defaults,nofail            0 2
UUID=<hdd>      /srv/data   ext4  defaults,nofail,x-systemd.device-timeout=10 0 2
# p3 (recovery) НЕ монтируется в fstab — используется только из recovery-среды
```

- [x] **Step 3: Проверка (dry-run не требуется для уже установленной системы; скрипт на живом диске не запускать)**

Run: `sudo bash provisioning/partition-ssd.sh /dev/sdX && lsblk -f /dev/sdX`
Expected: 4 раздела с метками ESP/root/recovery/persist и корректными ФС.

- [x] **Step 4: Commit**

```bash
git add provisioning/partition-ssd.sh provisioning/fstab.sample
git commit -m "feat(provisioning): SSD partitioning script and fstab sample"
```

### Task 2: Runbook установки Debian + BIOS

**Files:**
- Create: `provisioning/install-runbook.md`

- [x] **Step 1: Написать runbook**

```markdown
# Установка Debian и BIOS (на T420)

## BIOS (юзкейс 1 — автозапуск при питании)
1. F1 при загрузке → Config → Power.
2. `Power On with AC Attach = Enabled` (`OnByAcAttach=Enable`).
3. Boot order: SSD первым.
4. Сохранить (F10).

## Установка Debian stable
1. Загрузиться с USB (netinst).
2. Expert/manual: НЕ давать инсталлятору переразметить — разделы уже созданы
   (Task 1). Назначить точки монтирования по `fstab.sample`.
3. Software selection: снять всё, кроме "standard system utilities" и "SSH server".
4. GRUB → в ESP (`/dev/sdX`).
5. Первая загрузка, `ssh` работает по паролю временно (заменим на ключи в Task 3).

## Проверка
- `sudo systemctl is-enabled ssh` → enabled
- Обесточить и подать питание → ноут стартует сам.
```

- [x] BIOS и автозапуск при подключении питания настроены и проверены (`OnByAcAttach=Enable`; за автозапуском продолжаем наблюдать из-за нестабильности).
- [x] Debian stable установлен на T420.
- [x] Проверка установки и автозапуска выполнена.

- [x] **Step 2: Commit**

```bash
git add provisioning/install-runbook.md
git commit -m "docs(provisioning): Debian install and BIOS runbook"
```

### Task 3: Базовая настройка (SSH-ключи, TLP, governor, спиндаун, апдейты)

**Files:**
- Create: `provisioning/setup-base.sh`

- [x] **Step 1: Написать скрипт базовой настройки**

```bash
#!/usr/bin/env bash
# provisioning/setup-base.sh — базовая настройка Debian. Запуск от root.
set -euo pipefail
PUBKEY="${1:?usage: setup-base.sh 'ssh-ed25519 AAAA... user'}"

# SSH: ключи вместо пароля
install -d -m700 /root/.ssh
echo "$PUBKEY" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

# Питание/тишина
apt-get update
apt-get install -y tlp hdparm unattended-upgrades
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

# Автоматические security-обновления
dpkg-reconfigure -f noninteractive unattended-upgrades

systemctl restart ssh
echo "Базовая настройка завершена."
```

- [x] **Step 2: Проверка**

Run на боксе:
```bash
sudo bash provisioning/setup-base.sh "$(cat ~/.ssh/id_ed25519.pub)"
sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin'
systemctl is-active tlp
```
Expected: `passwordauthentication no`, `kbdinteractiveauthentication no`, `permitrootlogin no`, tlp `active`.

Результат проверки 2026-09-28: SSH по ключу работает, ключи имеют права 700/600,
`PasswordAuthentication no`, `KbdInteractiveAuthentication no`, `PermitRootLogin
no`; новый вход по ключу прошёл, парольный отклонён. TLP активен в режиме AC,
автообновления и таймеры включены. Governor — `schedutil`; доступны `performance`
и `schedutil`, поэтому неподдерживаемая запись `powersave` удалена из скрипта.

- [x] **Step 3: Проверка спиндауна**

Run: `sudo hdparm -C /dev/disk/by-label/data` через 2+ мин простоя
Expected: `drive state is: standby`.
Результат 2026-09-28: `/srv/data` смонтирован с HDD `/dev/sda2`; служба успешно
задала `-S 60` (5 минут), диск сейчас `standby`. На питании от адаптера TLP
устанавливает APM 254, переопределяя заданное службой значение 127.

- [x] **Step 4: Commit**

```bash
git add provisioning/setup-base.sh
git commit -m "feat(provisioning): base setup — ssh keys, tlp, governor, hdd spindown, auto-updates"
```

---

## Phase 2 — Recovery (скрипты + runbook)

### Task 4: Скрипты restore и rebless

**Files:**
- Create: `recovery/restore.sh`, `recovery/rebless.sh`

**Interfaces:**
- Consumes: разделы p2 (root), p3 (recovery-хранилище) из Phase 1.
- Produces: `restore.sh` (p3→p2), `rebless.sh` (p2→p3). Снимки на p3:
  `/mnt/recovery/golden.current.img`, `/mnt/recovery/golden.new.img`.

- [x] **Step 1: Написать restore.sh**

```bash
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
```

- [x] **Step 2: Написать rebless.sh (с сохранением старого снимка)**

```bash
#!/usr/bin/env bash
# recovery/rebless.sh — снять НОВЫЙ золотой снимок p2 -> p3. Запуск в recovery-среде (p2 не смонтирован).
set -euo pipefail
ROOT_PART="${ROOT_PART:?}"; REC_PART="${REC_PART:?}"
mkdir -p /mnt/recovery; mount "$REC_PART" /mnt/recovery
NEW=/mnt/recovery/golden.new.img; CUR=/mnt/recovery/golden.current.img

echo "Снимаю $ROOT_PART -> $NEW ..."
partclone.ext4 -c -s "$ROOT_PART" -O "$NEW" -F

# Проверка целостности нового снимка перед заменой
partclone.chkimg -s "$NEW"
mv -f "$NEW" "$CUR"
sync; umount /mnt/recovery
echo "Новый золотой снимок зафиксирован."
```

- [x] **Step 3: Проверка (на двух временных loop-дисках в Docker Desktop Linux VM)**

Результат 2026-09-28: `rebless.sh` проверен при ошибке клонирования (старый снимок
сохранён) и при успешном выполнении (новый снимок создан, `partclone.chkimg`
прошёл). Затем тестовый root был изменён; `restore.sh` восстановил исходные
файлы, `e2fsck` ошибок не обнаружил. Использовались только временные loop-диски,
реальные диски T420 не подключались.

- [x] **Step 4: Commit**

```bash
git add recovery/restore.sh recovery/rebless.sh
git commit -m "feat(recovery): partclone restore and rebless scripts"
```

### Task 5: Recovery-среда и пункты GRUB

**Files:**
- Create: `recovery/build-recovery.sh`, `recovery/40_konotop`, `recovery/recovery-runbook.md`

**Interfaces:**
- Consumes: `restore.sh` (Task 4).
- Produces: GRUB entries `Normal boot` and `Restore system (data is preserved)`; one-time recovery entry for re-bless.

- [x] **Step 1: Собрать recovery-initramfs**

```bash
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
```

- [x] **Step 2: Пункты GRUB**

```bash
# recovery/40_konotop — положить в /etc/grub.d/40_konotop, chmod +x, затем update-grub
cat <<'MENU'
menuentry 'Normal boot' --id konotop-normal { search --set=root --label root; linux /boot/vmlinuz root=LABEL=root ro quiet; initrd /boot/initrd.img }
menuentry 'Restore system (data is preserved)' --id konotop-recover {
  search --set=root --label root
  linux /boot/vmlinuz ro konotop.recover=1 ROOT_PART=/dev/disk/by-label/root REC_PART=/dev/disk/by-label/recovery
  initrd /boot/konotop-recovery.img
}
MENU
```

- [x] **Step 3: Runbook (установка пунктов + одноразовый rebless)**

```markdown
# recovery/recovery-runbook.md
## Установка
1. `sudo bash recovery/build-recovery.sh`
2. `sudo install -m755 recovery/40_konotop /etc/grub.d/40_konotop`
3. `sudo update-grub`

## Первый золотой снимок / re-bless (удалённо)
1. Обкатать изменения на живой системе.
2. Не использовать recovery-пункт: для re-bless нужен отдельный пункт
   `Create golden snapshot (admin)` с `--id konotop-rebless`.
3. `sudo grub-reboot konotop-rebless && sudo reboot`
4. Recovery снимет p2->p3, вернётся в обычную загрузку.

## Проверка кнопки восстановления
- Испортить файл в p2, выбрать `Restore system (data is preserved)` в GRUB → файл вернулся,
  содержимое /srv/data и /srv/persist не изменилось.
```

- [x] **Step 4: Добавить menuentry rebless в 40_konotop**

```bash
# дописать в recovery/40_konotop:
cat <<'MENU'
menuentry 'Create golden snapshot (admin)' --id konotop-rebless {
  search --set=root --label root
  linux /boot/vmlinuz ro konotop.rebless=1 ROOT_PART=/dev/disk/by-label/root REC_PART=/dev/disk/by-label/recovery
  initrd /boot/konotop-recovery.img
}
MENU
```
(В initramfs-хук: если `konotop.rebless=1` → запустить `rebless.sh`; если `konotop.recover=1` → `restore.sh`; иначе обычная загрузка. Добавить в build-recovery.sh включение обоих скриптов и парсер cmdline.)

- [x] **Step 5: Проверка**

Результат: GRUB-конфигурация проверена через `grub-script-check`, все три пункта
сохранены; восстановление через GRUB на T420 ранее проверено. Скриптовый цикл
`rebless` → проверка образа → `restore` дополнительно прошёл на тестовых дисках.

- [x] **Step 6: Commit**

```bash
git add recovery/build-recovery.sh recovery/40_konotop recovery/recovery-runbook.md
git commit -m "feat(recovery): recovery initramfs, GRUB entries, runbook"
```

---

## Phase 3 — Network (Tailscale, proxies, remote access)

### Task 6: Tailscale + SSH на tailnet

**Files:**
- Create: `network/tailscale-runbook.md`, `network/sshd_konotop.conf`

**Interfaces:**
- Consumes: p4 (`/srv/persist`) для statedir.
- Produces: tailnet-адрес бокса; sshd только на интерфейсе `tailscale0`.

- [x] **Step 1: Tailscale runbook (statedir на p4)**

```markdown
# network/tailscale-runbook.md
1. `curl -fsSL https://tailscale.com/install.sh | sh`
2. Состояние — на p4 (переживает восстановление):
   `sudo mkdir -p /srv/persist/tailscale`
   Правка unit: `--state=/srv/persist/tailscale/tailscaled.state`
3. `sudo tailscale up --ssh --advertise-exit-node`
   (exit-node пригодится для личных устройств; включается тумблером у клиента)
4. Записать tailnet-IP: `tailscale ip -4`
```

- [x] **Step 2: sshd — только на tailnet**

```
# network/sshd_konotop.conf → /etc/ssh/sshd_config.d/konotop.conf
# Слушать только на интерфейсе Tailscale (подставить tailnet-IP из runbook)
ListenAddress <TAILNET_IP>
PasswordAuthentication no
PermitRootLogin prohibit-password
```

**Step 3: Проверка перенесена в Phase 6, Task 16** — текущая проверка показала,
что sshd слушает `0.0.0.0:22` и `[::]:22`. Привязку отложить до завершения
отладки и подтверждения рабочего доступа через Tailscale.

- [x] **Step 4: Commit**

```bash
git add network/tailscale-runbook.md network/sshd_konotop.conf
git commit -m "feat(network): tailscale with persistent state, ssh bound to tailnet"
```

### Task 7: NAS в tailnet + доступ к konotop

Основной путь для рабочего ноутбука, который не может запускать Tailscale сам:
NAS уже стоит в LAN рабочего ноута; подключаем NAS к tailnet, и через него ноут
получает доступ к `konotop`. Закрывает базу для всех трёх потребностей (панель,
SSH, домашний IP).

Обследованный NAS: Odroid M1S, Armbian (arm64), LAN-IP `192.168.68.59`; Docker
есть, контейнеры ведутся через Portainer (:9000) или из консоли. Tailscale
установлен и подключён как `odroidm1s` (`100.123.127.87`); `tailscale ping
konotop` проходит. Serve включён на `konotop` (`konotop.tailb4dba1.ts.net`) и
проверен с NAS (HTTPS 200). Поверх сейчас временно стоит OMV, но на него не
опираемся. Для моста выбраны LAN-порты panel `8095`, SSH relay `2222`, SOCKS
relay `1080`; перед деплоем проверять свободность.

**Files:**
- Create: `network/nas/nas-bridge-runbook.md`, `network/nas/.env.sample`

**Interfaces:**
- Consumes: tailnet-IP `konotop` = `100.65.92.104` (Task 6), LAN-IP NAS.
- Produces: NAS как узел tailnet, видящий `konotop`; точка входа для рабочего ноута.

- [x] **Step 1: Установить Tailscale на NAS (runbook + .env.sample)**

```bash
# на NAS (Armbian):
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up            # авторизоваться по ссылке
# заполнить network/nas/.env из .env.sample: KONOTOP_TS_IP, KONOTOP_HOST, порты
```

- [x] **Step 2: Проверка связности**

Run: на NAS `tailscale status`, `tailscale ping konotop` и
`curl -I https://konotop.tailb4dba1.ts.net/`
Expected: NAS и `konotop` в tailnet, ping проходит, Serve отдаёт HTTP 200.

- [x] **Step 3: Commit**

```bash
git add network/nas/nas-bridge-runbook.md network/nas/.env.sample
git commit -m "feat(network): nas joined to tailnet as bridge to konotop"
```

### Task 8: Доступ к веб-панели и SSH konotop с рабочего ноута через NAS

Закрывает потребности 1 (веб-панель) и 2 (SSH). NAS проксирует запросы рабочего
ноута из LAN в tailnet к `konotop`.

**Files:**
- Create: `network/nas/docker-compose.yml`, `network/nas/Caddyfile`, `network/nas/homepage-konotop-group.yaml`
- Update: `network/nas/nas-bridge-runbook.md`

**Interfaces:**
- Consumes: NAS в tailnet (Task 7); Caddy `konotop` через `tailscale serve` (Phase 4); sshd `konotop:22`.
- Produces: Homepage NAS на `<NAS_LAN_IP>:<PANEL_PORT>`, ссылки на сервисы konotop и SSH-релей `<NAS_LAN_IP>:2222` → konotop.

- [x] **Step 1: konotop — опубликовать панель в tailnet**

```bash
# на konotop (Caddy слушает только 127.0.0.1:80):
sudo tailscale serve --bg 80
tailscale serve status   # https://konotop.tailb4dba1.ts.net → 127.0.0.1:80
```

- [x] **Step 2: NAS — reverse proxy к панели (Caddy-контейнер)**

```bash
cp network/nas/.env.sample network/nas/.env   # проверить LAN-IP и tailnet hostname
sudo docker compose --env-file .env -f docker-compose.yml up -d panel-proxy
# ssh-relay запускается отдельным шагом ниже
# Caddy слушает на LAN-IP:8095 и проксирует на tailnet-IP konotop с TLS hostname
```

- [x] **Step 3: (опция) ссылки на konotop в Homepage NAS**

```yaml
# network/nas/homepage-konotop-group.yaml добавлена в Homepage NAS;
# перед правкой сделана резервная копия services.yaml.
```

- [x] **Step 4: Развернуть SSH TCP-релей на NAS**

На NAS sshd запрещает TCP forwarding, поэтому в Docker Compose работает socat
TCP-релей `<NAS_LAN_IP>:2222` → `100.65.92.104:22`. Проверено с Mac из LAN:
SSH-команда через relay выполнилась на `konotop`.

Порт на NAS слушает только LAN-IP `192.168.68.59`; ключевая аутентификация и
host key остаются end-to-end с konotop.

- [x] **Step 5: Настроить SSH на рабочем ноуте**

```
# ~/.ssh/config на рабочем ноуте
Host konotop
    HostName 192.168.68.59
    Port 2222
    User duhon
    IdentityFile ~/.ssh/<WORK_KEY>
```

Добавить публичный ключ рабочего ноута в `authorized_keys` только на konotop;
NAS ключ не хранит. SSH-шифрование и host-key проверка остаются end-to-end.

- [x] **Step 6: Проверка с рабочего ноута (закрывает потребности 1 и 2)**

Run: с рабочего ноута открыть `http://<NAS_LAN_IP>:<PANEL_PORT>`, перейти по ссылкам на сервисы и выполнить `ssh konotop`.
Expected: Homepage NAS показывает ссылки; сервисы открываются без ошибок; SSH-вход по ключу работает.

- [x] **Step 7: Commit**

```bash
git add network/nas/docker-compose.yml network/nas/Caddyfile network/nas/homepage-konotop-group.yaml network/nas/nas-bridge-runbook.md
git commit -m "feat(network): web panel + ssh to konotop via nas bridge"
```

### Task 9: Домашний IP для браузера рабочего ноута через NAS → SOCKS5 konotop

Закрывает потребность 3: сайты видят домашний IP родителей, когда браузер
рабочего ноута ходит через цепочку NAS-релей → SOCKS5 без авторизации на
`konotop`. Селективно (через прокси идёт только браузер), поэтому Exit Node на
NAS не нужен.

**Files:**
- Update: `network/nas/docker-compose.yml` (сервис `socks-relay`), `network/nas/nas-bridge-runbook.md`, `network/nas/test-socks-route.sh`, `proxy/socks5-compose.yml`, `services/.env.sample`, `proxy/README.md`
- Consumes: `proxy/socks5-compose.yml` (SOCKS5 на konotop, bind на tailnet-IP)

**Interfaces:**
- Consumes: NAS в tailnet (Task 7), SOCKS5 `100.65.92.104:1080` на konotop.
- Produces: `<NAS_LAN_IP>:<SOCKS_PORT>` → выход домашним IP; без авторизации,
  поэтому доступен устройствам в доверенной LAN.

- [x] **Step 1: konotop — SOCKS5 без авторизации на tailnet-IP**

```bash
# на konotop: KONOTOP_TS_IP хранится в /srv/persist/services.env
sudo docker compose --env-file /srv/persist/services.env \
  -f proxy/socks5-compose.yml up -d
sudo ss -ltnp | grep 100.65.92.104:1080   # слушает только на tailnet-IP
```

- [x] **Step 2: NAS — TCP-релей LAN → SOCKS5 konotop**

```bash
docker compose -f network/nas/docker-compose.yml up -d socks-relay
# socat: <NAS_LAN_IP>:<SOCKS_PORT> → ${KONOTOP_TS_IP}:1080 (без авторизации)
```

- [x] **Step 3: Браузер рабочего ноута через прокси — выполнено в Phase 6, Task 16**

```markdown
# Chrome + Proxy SwitchyOmega, профиль SOCKS5:
#   Server <NAS_LAN_IP>, Port <SOCKS_PORT>, authentication none
# Тумблер = только браузер через дом.
```

- [x] **Step 4: Проверка (закрывает потребность 3)**

Run: из konotop запросить `https://ifconfig.me/ip` напрямую и через NAS SOCKS-релей.
Expected: запрос через proxy не требует auth и совпадает с прямым домашним egress.
Проверено скриптом `network/nas/test-socks-route.sh`.

- [x] **Step 5: Настроить и проверить прокси на рабочем ноуте — выполнено в Phase 6, Task 16**

Run: включить SOCKS5 профиль (`<NAS_LAN_IP>:1080`, без auth) и открыть
`https://ifconfig.me/ip`.
Expected: виден домашний IP.

- [x] **Step 6: Commit — конфигурация NAS-релея зафиксирована в Git**

```bash
git add network/nas/docker-compose.yml network/nas/nas-bridge-runbook.md
git commit -m "feat(network): work-laptop browser exits via home ip through nas"
```

## Phase 4 — Docker-стек

### Task 10: Docker + Caddy + сервисы (compose)

**Files:**
- Create: `services/docker-compose.yml`, `services/Caddyfile`, `services/.env.sample`

**Interfaces:**
- Consumes: HDD `/srv/data`, p4 `/srv/persist/services.env`.
- Produces: qBittorrent, filebrowser за Caddy на `localhost:80`.

- [x] **Step 1: docker-compose.yml**

```yaml
# services/docker-compose.yml
services:
  caddy:
    image: caddy:2
    restart: unless-stopped
    ports: ["80:80"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    restart: unless-stopped
    environment: [PUID=1000, PGID=1000, WEBUI_PORT=8080]
    volumes:
      - qbt_config:/config
      - /srv/data/downloads:/downloads
  filebrowser:
    image: filebrowser/filebrowser:latest
    restart: unless-stopped
    volumes:
      - /srv/data:/srv
      - fb_db:/database
volumes: { caddy_data: {}, qbt_config: {}, fb_db: {} }
```

- [x] **Step 2: Caddyfile**

```
# services/Caddyfile — внутренний прокси, TLS не нужен (Tailscale/CF снаружи)
:80 {
  handle_path /torrent/* { reverse_proxy qbittorrent:8080 }
  handle_path /files/*   { reverse_proxy filebrowser:80 }
  handle /                { respond "konotop up" 200 }
}
```

- [x] **Step 3: .env.sample**

```
# services/.env.sample — реальный .env лежит на p4 (/srv/persist/services.env), симлинк сюда
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
```

- [x] **Step 4: Проверка конфигурации**

Проверено на konotop: `docker compose config --quiet` проходит; маршруты `/`,
`/torrent/`, `/files/` и `/portainer/` возвращают HTTP 200. Стек уже запущен;
повторно пересоздавать его для проверки не потребовалось.

- [x] **Step 5: Commit**

```bash
git add services/docker-compose.yml services/Caddyfile services/.env.sample
git commit -m "feat(services): docker stack — caddy, qbittorrent, filebrowser"
```

### Task 11: Дашборд Homepage

**Files:**
- Create: `services/homepage/{services.yaml,settings.yaml,widgets.yaml}`; Modify: `services/docker-compose.yml`

- [x] **Step 1: Добавить homepage в compose**

```yaml
# добавить сервис в services/docker-compose.yml
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    restart: unless-stopped
    volumes:
      - ./homepage:/app/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /srv/data:/data:ro
```
И в Caddyfile корень `handle /` заменить на `reverse_proxy homepage:3000`.

- [x] **Step 2: homepage/services.yaml**

```yaml
- Сервисы:
    - qBittorrent: { href: /torrent/, description: Торренты, container: qbittorrent }
    - Файлы:       { href: /files/,   description: Файлы,     container: filebrowser }
```

- [x] **Step 3: homepage/widgets.yaml (место на диске)**

```yaml
- resources: { disk: /data, cpu: true, memory: true }
```

- [x] **Step 4: homepage/settings.yaml**

```yaml
title: konotop
```

- [x] **Step 5: Проверка**

Результат: проверка Homepage выполнена ранее; позднее Homepage на konotop удалён,
дашборд доступен на NAS.

- [x] **Step 6: Commit**

```bash
git add services/homepage services/docker-compose.yml services/Caddyfile
git commit -m "feat(services): homepage dashboard with status and disk widget"
```

---

## Phase 5 — SMS→Telegram мост (полноценный код + TDD)

### Task 12: Парсер SMS из mmcli

**Files:**
- Create: `sms-bridge/pyproject.toml`, `sms-bridge/src/sms_bridge/__init__.py`, `sms-bridge/src/sms_bridge/modem.py`, `sms-bridge/tests/test_modem.py`

**Interfaces:**
- Produces: `modem.list_message_ids(runner) -> list[str]`; `modem.read_message(runner, msg_id) -> Sms` где `Sms = dataclass(id:str, sender:str, text:str, timestamp:str)`; `runner` — callable `(list[str]) -> str` (обёртка над subprocess, для тестируемости).

- [x] **Step 1: pyproject.toml**

```toml
[project]
name = "sms-bridge"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = ["requests>=2.31"]
[project.optional-dependencies]
dev = ["pytest>=8"]
[tool.pytest.ini_options]
pythonpath = ["src"]
```

- [x] **Step 2: Написать падающий тест парсера списка**

```python
# sms-bridge/tests/test_modem.py
from sms_bridge import modem

LIST_OUT = """\
/org/freedesktop/ModemManager1/SMS/0 (received)
/org/freedesktop/ModemManager1/SMS/2 (received)
"""

def test_list_message_ids_parses_paths():
    runner = lambda args: LIST_OUT
    assert modem.list_message_ids(runner) == ["0", "2"]
```

- [ ] **Step 3: Запустить — убедиться, что падает**

Run: `cd sms-bridge && pip install -e '.[dev]' && pytest tests/test_modem.py -v`
Expected: FAIL (`module modem has no attribute list_message_ids`).

- [x] **Step 4: Реализовать парсер списка**

```python
# sms-bridge/src/sms_bridge/modem.py
import re
from dataclasses import dataclass

@dataclass
class Sms:
    id: str
    sender: str
    text: str
    timestamp: str

def list_message_ids(runner) -> list[str]:
    out = runner(["mmcli", "-m", "any", "--messaging-list-sms"])
    return re.findall(r"/SMS/(\d+)", out)
```

- [x] **Step 5: Тест детального парсинга (падающий)**

```python
# добавить в tests/test_modem.py
DETAIL_OUT = """\
  -----------------------------
  Content    |  number: +79991234567
             |    text: Привет мир
  -----------------------------
  Properties |    timestamp: 2026-09-13T10:00:00+03:00
"""

def test_read_message_parses_fields():
    runner = lambda args: DETAIL_OUT
    sms = modem.read_message(runner, "0")
    assert sms.id == "0"
    assert sms.sender == "+79991234567"
    assert sms.text == "Привет мир"
    assert sms.timestamp.startswith("2026-09-13")
```

- [ ] **Step 6: Запустить — убедиться, что падает**

Run: `pytest tests/test_modem.py::test_read_message_parses_fields -v`
Expected: FAIL.

- [x] **Step 7: Реализовать read_message**

```python
# добавить в modem.py
def read_message(runner, msg_id: str) -> Sms:
    out = runner(["mmcli", "-m", "any", "-s", msg_id])
    number = re.search(r"number:\s*(\S+)", out)
    text = re.search(r"text:\s*(.+)", out)
    ts = re.search(r"timestamp:\s*(\S+)", out)
    return Sms(
        id=msg_id,
        sender=number.group(1) if number else "?",
        text=text.group(1).strip() if text else "",
        timestamp=ts.group(1) if ts else "",
    )

def delete_message(runner, msg_id: str) -> None:
    runner(["mmcli", "-m", "any", "--messaging-delete-sms", msg_id])
```

- [x] **Step 8: Запустить все тесты**

Run: `pytest tests/test_modem.py -v`
Result: PASS (5 tests, Python 3.12); added coverage for the empty-list output
observed on konotop (`modem.messaging.sms : 0`).

- [x] **Step 9: Commit**

```bash
git add sms-bridge/pyproject.toml sms-bridge/src/sms_bridge/__init__.py sms-bridge/src/sms_bridge/modem.py sms-bridge/tests/test_modem.py
git commit -m "feat(sms): mmcli SMS parser with tests"
```

### Task 13: Отправка в Telegram

**Files:**
- Create: `sms-bridge/src/sms_bridge/telegram.py`, `sms-bridge/tests/test_telegram.py`

**Interfaces:**
- Produces: `telegram.format_message(sms: Sms) -> str`; `telegram.send(token, chat_id, text, poster=requests.post) -> bool`.

- [x] **Step 1: Тест форматирования (падающий)**

```python
# sms-bridge/tests/test_telegram.py
from sms_bridge import telegram
from sms_bridge.modem import Sms

def test_format_message_includes_sender_and_text():
    sms = Sms(id="0", sender="+7999", text="Привет", timestamp="2026-09-13T10:00")
    msg = telegram.format_message(sms)
    assert "+7999" in msg and "Привет" in msg
```

- [ ] **Step 2: Запустить — падает**

Run: `pytest tests/test_telegram.py -v`
Expected: FAIL.

- [x] **Step 3: Реализовать format_message + send**

```python
# sms-bridge/src/sms_bridge/telegram.py
import requests

def format_message(sms) -> str:
    return f"📩 SMS от {sms.sender}\n{sms.text}\n\n{sms.timestamp}"

def send(token: str, chat_id: str, text: str, poster=requests.post) -> bool:
    r = poster(
        f"https://api.telegram.org/bot{token}/sendMessage",
        json={"chat_id": chat_id, "text": text},
        timeout=15,
    )
    return getattr(r, "status_code", 500) == 200
```

- [x] **Step 4: Тест send с моком (падающий → пишем сразу)**

```python
# добавить в tests/test_telegram.py
class FakeResp:
    status_code = 200

def test_send_posts_to_telegram_api():
    calls = {}
    def poster(url, json, timeout):
        calls["url"] = url; calls["json"] = json
        return FakeResp()
    ok = telegram.send("TOK", "42", "hi", poster=poster)
    assert ok is True
    assert "botTOK/sendMessage" in calls["url"]
    assert calls["json"] == {"chat_id": "42", "text": "hi"}
```

- [x] **Step 5: Запустить все тесты**

Run: `pytest tests/test_telegram.py -v`
Result: PASS (в составе полного офлайн-набора: 12 тестов, Python 3.12).

- [x] **Step 6: Commit**

```bash
git add sms-bridge/src/sms_bridge/telegram.py sms-bridge/tests/test_telegram.py
git commit -m "feat(sms): telegram formatting and send with tests"
```

### Task 14: Цикл моста + конфиг + запуск

**Files:**
- Create: `sms-bridge/src/sms_bridge/config.py`, `sms-bridge/src/sms_bridge/bridge.py`, `sms-bridge/src/sms_bridge/__main__.py`, `sms-bridge/tests/test_bridge.py`, `sms-bridge/Dockerfile`; Modify: `services/docker-compose.yml`

**Interfaces:**
- Consumes: `modem.*`, `telegram.*`.
- Produces: `bridge.forward_new(runner, token, chat_id, sender=telegram.send) -> int` (число пересланных, удаляет обработанные).

- [x] **Step 1: Тест цикла (падающий)**

```python
# sms-bridge/tests/test_bridge.py
from sms_bridge import bridge, modem

def make_runner(ids, details):
    def runner(args):
        if "--messaging-list-sms" in args:
            return "\n".join(f"/SMS/{i} (received)" for i in ids)
        if "-s" in args:
            mid = args[args.index("-s") + 1]
            return details[mid]
        if "--messaging-delete-sms" in args:
            runner.deleted.append(args[-1]); return ""
        return ""
    runner.deleted = []
    return runner

def test_forward_new_sends_and_deletes():
    details = {"0": "number: +7999\ntext: hi\ntimestamp: 2026-09-13T10:00"}
    runner = make_runner(["0"], details)
    sent = []
    n = bridge.forward_new(runner, "TOK", "42",
                           sender=lambda t, c, txt: sent.append(txt) or True)
    assert n == 1
    assert sent and "hi" in sent[0]
    assert runner.deleted == ["0"]
```

- [ ] **Step 2: Запустить — падает**

Run: `pytest tests/test_bridge.py -v`
Expected: FAIL.

- [x] **Step 3: Реализовать bridge.forward_new**

```python
# sms-bridge/src/sms_bridge/bridge.py
from . import modem, telegram

def forward_new(runner, token, chat_id, sender=telegram.send) -> int:
    count = 0
    for msg_id in modem.list_message_ids(runner):
        sms = modem.read_message(runner, msg_id)
        if sender(token, chat_id, telegram.format_message(sms)):
            modem.delete_message(runner, msg_id)
            count += 1
    return count
```

- [x] **Step 4: config.py + __main__.py (loop)**

```python
# sms-bridge/src/sms_bridge/config.py
import os
def load():
    return (
        os.environ["TELEGRAM_BOT_TOKEN"],
        os.environ["TELEGRAM_CHAT_ID"],
        int(os.environ.get("POLL_INTERVAL", "30")),
    )
```
```python
# sms-bridge/src/sms_bridge/__main__.py
import subprocess, time
from . import bridge, config

def runner(args): return subprocess.run(args, capture_output=True, text=True).stdout

def main():
    token, chat_id, interval = config.load()
    while True:
        try: bridge.forward_new(runner, token, chat_id)
        except Exception as e: print("err:", e, flush=True)
        time.sleep(interval)

if __name__ == "__main__":
    main()
```

- [x] **Step 5: Запустить все тесты моста**

Run: `pytest -v`
Result: PASS (12 тестов, Python 3.12); real modem and Telegram network calls were
not used.

- [x] **Step 6: Dockerfile + добавить в compose**

```dockerfile
# sms-bridge/Dockerfile
FROM python:3.11-slim
RUN apt-get update && apt-get install -y modemmanager && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY pyproject.toml ./
COPY src ./src
RUN pip install --no-cache-dir .
CMD ["python", "-m", "sms_bridge"]
```
```yaml
# добавить в services/docker-compose.yml (нужен доступ к ModemManager на хосте через dbus)
  sms-bridge:
    build: ../sms-bridge
    restart: unless-stopped
    env_file: /srv/persist/services.env
    volumes:
      - /var/run/dbus:/var/run/dbus:ro
    privileged: true   # доступ к модему; сузить до нужных cap при обкатке
```

- [x] **Step 7: Проверка на боксе с реальной SMS (перенесено в Phase 8)**

Перенесено в Phase 8 (Task 20, On-site испытания в Украине): текущая связка в
Техасе не ловит частоты AT&T на европейском MC7304. Офлайн-проверка кода,
тестов и D-Bus ModemManager полностью завершена (12 unit-тестов пройдены).

- [x] **Step 8: Commit**

```bash
git add sms-bridge/src sms-bridge/tests/test_bridge.py sms-bridge/Dockerfile services/docker-compose.yml
git commit -m "feat(sms): bridge loop, config, docker packaging"
```

### Task 15: СПАЙК — голос на MC7304

**Files:**
- Create: `sms-bridge/spike-voice.md` (результат; код спайка — throwaway)

- [x] **Step 1: Проверить голосовые возможности модема (API без звонка)**

Проверено на боксе через ModemManager D-Bus:
```bash
busctl --system introspect org.freedesktop.ModemManager1 \
  /org/freedesktop/ModemManager1/Modem/0 \
  org.freedesktop.ModemManager1.Modem.Voice
mmcli -m any --voice-list-calls
```

Интерфейс `Modem.Voice` предоставляет `CreateCall`/`ListCalls`, но это
подтверждает только наличие общего API ModemManager, а не поддержку звонков
прошивкой модема. Текущая прошивка `SWI9X15C_05.05.78.00`; голосовые звонки на
ней не подтверждены. Активных вызовов нет; исходящий вызов не выполнялся.

- [x] **Step 2: Записать вывод и решение**

Результат, неопределённость прошивки и ограничение live-проверки записаны в
`sms-bridge/spike-voice.md`.

- [x] **Step 3: Commit**

```bash
git add sms-bridge/spike-voice.md
git commit -m "spike(sms): MC7304 voice capability investigation"
```

---

## Phase 6 — Финальные проверки

### Task 16: Финальная проверка и закрытие проекта

Выполнять после завершения отладки и выбора сетевого доступа для рабочих устройств.

- [x] Настроить и проверить SOCKS5-прокси в браузере рабочего ноута (`<NAS_LAN_IP>:<SOCKS_PORT>`, без авторизации, только для браузера); проверить `https://ifconfig.me/ip` → домашний IP (выполнено, перенесено из Phase 3, Task 9).
- [ ] Проверить веб-сервисы через выбранный путь доступа (NAS-мост из Phase 3; Cloudflare из Phase 7, если оставлен).
- [ ] После подтверждения SSH-доступа через tailnet привязать sshd только к tailnet-IP; проверить вход по ключу и отсутствие слушателей на `0.0.0.0` и `[::]`.
- [ ] Провести финальную проверку загрузки, восстановления, закрытия крышки и автозапуска от питания.
- [ ] Решить расхождение APM: TLP задаёт `254` на AC, служба HDD задаёт `127`.
- [ ] Обновить golden snapshot после окончательных изменений.
- [ ] Запустить тесты проекта, обновить чекбоксы и зафиксировать изменения в Git.

## Phase 7 — Опциональные альтернативы доступа

Резерв на случай, если NAS-мост (Phase 3) не подойдёт или понадобится публичный
адрес панели. Реализовывать только по необходимости; конфиги подготовлены ранее.

### Task 17: Cloudflare Tunnel + Access (опционально)

Нужен только если решено дать веб-панели публичный hostname. Требуется домен.

**Files:**
- Create: `network/cloudflared/config.yml`, `network/cloudflared/runbook.md`

**Interfaces:**
- Consumes: Caddy на `localhost:80` (Phase 4).
- Produces: публичный `https://<host>` на веб-морду, за Cloudflare Access.

- [x] **Step 1: config.yml**

```yaml
# network/cloudflared/config.yml — креды на p4
tunnel: <TUNNEL_UUID>
credentials-file: /srv/persist/cloudflared/<TUNNEL_UUID>.json
ingress:
  - hostname: dash.example.com
    service: http://localhost:80
  - service: http_status:404
```

- [x] **Step 2: runbook**

```markdown
# network/cloudflared/runbook.md
1. `cloudflared tunnel login`
2. `cloudflared tunnel create konotop`
3. Переместить креды в /srv/persist/cloudflared/ (p4).
4. DNS: `cloudflared tunnel route dns konotop dash.example.com`
5. Cloudflare Zero Trust → Access → приложение на dash.example.com,
   политика: email = <твой email>, метод One-time PIN.
6. Запуск как сервис: `cloudflared service install`, конфиг из config.yml.
```

- [ ] **Step 3: Проверка**

Run: с чужой сети открыть `https://dash.example.com`
Expected: запрос email-кода (Access), после ввода — веб-морда.

- [x] **Step 4: Commit**

```bash
git add network/cloudflared/
git commit -m "feat(network): cloudflare tunnel + access for public dashboard"
```

---

### Task 18: SOCKS5 для личных устройств (bind на tailnet, опционально)

Если личные устройства используют Tailscale Exit Node напрямую, отдельный SOCKS5
может быть не нужен.

**Files:**
- Create: `proxy/socks5-compose.yml`

**Interfaces:**
- Consumes: tailnet-IP (Task 6).
- Produces: SOCKS5 на `<TAILNET_IP>:1080`, доступный только из tailnet.

- [x] **Step 1: socks5-compose.yml**

```yaml
# proxy/socks5-compose.yml — bind ТОЛЬКО на tailnet-IP (не 0.0.0.0)
services:
  socks5:
    image: serjs/go-socks5-proxy:latest
    restart: unless-stopped
    ports: ["<TAILNET_IP>:1080:1080"]
    environment:
      REQUIRE_AUTH: "false"
```

- [ ] **Step 2: Проверка**

Run: с личного устройства (в tailnet): `curl --socks5-hostname <TAILNET_IP>:1080 https://ifconfig.me`
Expected: возвращается **домашний IP родителей** (не IP устройства). С не-tailnet устройства порт недоступен.

- [x] **Step 3: Настройка Chrome (личные устройства)**

```markdown
# в README proxy: расширение Proxy SwitchyOmega → профиль SOCKS5
# сервер <TAILNET_IP>:1080, без авторизации. Тумблер = только браузер через дом.
```

- [x] **Step 4: Commit**

```bash
git add proxy/socks5-compose.yml
git commit -m "feat(proxy): tailnet-only socks5 for personal devices"
```

### Task 19: Fallback для рабочего ноута — прямой прокси или VM-релей (опционально)

Резерв, если NAS-мост (Phase 3) не подходит. Выбор зависит от наличия CGNAT дома.

**Files:**
- Create: `proxy/cgnat-check.md`, `proxy/forward-proxy-compose.yml`, `proxy/relay-runbook.md`

- [ ] **Step 1: Проверить CGNAT**

```markdown
# proxy/cgnat-check.md
1. На устройстве в домашней сети: `curl ifconfig.me` → PUBLIC_IP
2. В админке роутера — WAN-IP.
3. Совпадают и не из 100.64.0.0/10 → CGNAT НЕТ (случай 1).
   Иначе → CGNAT ЕСТЬ (случай 2).
Результат: <записать>
```

- [x] **Step 2: Случай 1 — форвард-прокси на боксе:443 (если НЕТ CGNAT)**

```yaml
# proxy/forward-proxy-compose.yml — HTTPS forward proxy с аутентификацией на 443
services:
  fwdproxy:
    image: ubuntu/squid:latest
    restart: unless-stopped
    ports: ["443:3128"]
    volumes:
      - ./squid.conf:/etc/squid/squid.conf:ro
      - ./passwords:/etc/squid/passwords:ro   # htpasswd, креды на p4
# squid.conf: auth_param basic, acl обязателен, https_port с TLS-сертом (Caddy/CF cert).
# Проброс порта 443 на роутере -> бокс. Chrome SwitchyOmega -> HTTPS proxy дом:443 с логином.
```

- [x] **Step 3: Случай 2 — бесплатный VM-релей (если ЕСТЬ CGNAT)**

```markdown
# proxy/relay-runbook.md
1. Поднять бесплатный VM (Oracle Cloud Always Free) с публичным IP.
2. На боксе и VM — WireGuard-линк (бокс инициирует исходящее соединение).
3. На VM — nginx stream / socat: публичный :443 -> WG-адрес бокса:прокси.
4. На боксе — тот же форвард-прокси с аутентификацией (из случая 1), слушает на WG.
5. Chrome SwitchyOmega -> HTTPS proxy <VM_PUBLIC_IP>:443 с логином.
Итог: трафик выходит через бокс (домашний IP), VM только точка входа.
```

- [ ] **Step 4: Проверка (по выбранному случаю)**

Run: с рабочего ноута (только Chrome+расширение) открыть `ifconfig.me`
Expected: домашний IP родителей; аутентификация прокси требуется.

- [x] **Step 5: Commit**

```bash
git add proxy/cgnat-check.md proxy/forward-proxy-compose.yml proxy/relay-runbook.md
git commit -m "feat(proxy): cgnat check, work-laptop forward proxy (both cases)"
```

---

## Phase 8 — On-site испытания и запуск в Украине (после переезда)

### Task 20: Полевая проверка модема и SMS-моста в Украине

Выполняется после физической доставки и включения сервера в Украине.

- [ ] **Step 1: Регистрация MC7304 в украинской сети**
  - Вставить SIM-карту украинского оператора (Киевстар, Vodafone, lifecell) или роуминговую SIM.
  - Проверить статус: `mmcli -m any` -> `state: connected` / `registered`.
  - Убедиться в регистрации на поддерживаемых модемом частотах LTE: B3 (1800 МГц), B7 (2600 МГц) или B8 (900 МГц).

- [ ] **Step 2: Live-тест SMS-моста в Telegram (перенесено из Task 14, Step 7)**
  - Запустить контейнер `sms-bridge`: `docker compose up -d sms-bridge`.
  - Отправить тестовое SMS на номер SIM-карты в MC7304.
  - Проверить доставку сообщения в целевой Telegram-чат бота.
  - Проверить автоматическое удаление обработанного SMS из памяти модема (`mmcli -m any --messaging-list-sms` возвращает пустой список).

- [ ] **Step 3: Проверка fallback мобильного интернета / SOCKS5 (опционально)**
  - При необходимости настроить APN оператора через NetworkManager/mmcli для резервного выхода в интернет.

---

## Self-Review (выполнено при написании)

**Spec coverage:** все 9 юзкейсов покрыты — 1 (Task 2 BIOS), 2 (Tasks 6/8/16 SSH/Tailscale/NAS), 3 (Tasks 4–5 recovery), 4 (Task 3 TLP/спиндаун), 5–6 (Tasks 10–11 Docker/dashboard), 7 (Tasks 12–14 SMS, Task 15 voice), 8 (Tasks 7–9 NAS-мост, Task 19 fallback), 9 (Tasks 8/10–11 web dashboard, Task 17 Cloudflare опц.). Персистентная зона p4 — Tasks 0/1/6/14. Конфиг-как-код — весь репозиторий.

**Placeholder scan:** оставлены только осознанные подстановки окружения (`<TAILNET_IP>`, `<TUNNEL_UUID>`, `dash.example.com`, `/dev/sdX`) — это значения, известные только на конкретном железе; помечены явно.

**Type consistency:** `Sms`(id,sender,text,timestamp), `list_message_ids`, `read_message`, `delete_message`, `format_message`, `send`, `forward_new` — согласованы между Tasks 12–14.

**Известные зависимости от железа/спайков:** Tasks 1–3, 5(проверка), 7–9 (NAS/tailnet), 14(Step 7), 15, 16, 17(если выбран Cloudflare), 19(fallback) требуют бокса/модема/сети/NAS; выполняются при развёртывании, не в этой сессии.
