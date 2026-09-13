# T420 Autonomous Server («konotop») Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Превратить ThinkPad T420 в тихий, самовосстанавливающийся домашний сервер у родителей, управляемый удалённо, с торрентами, SMS→Telegram, exit-прокси и веб-панелью.

**Architecture:** Debian stable на SSD (разделы ОС/снимок/персистент), данные на HDD. Восстановление — снимок раздела через partclone, запуск из GRUB. Сеть — Tailscale (админ + exit-прокси личных устройств) + Cloudflare Tunnel (веб-морда наружу). Сервисы в Docker за Caddy. Конфиг как код в этом репозитории — источник правды для «золотого» состояния.

**Tech Stack:** Debian stable, Docker + docker-compose, Caddy, Tailscale, cloudflared, partclone, GRUB, ModemManager (`mmcli`), Python 3.11 (SMS-мост), qBittorrent, filebrowser, Homepage.

**Spec:** `docs/superpowers/specs/2026-08-30-t420-autonomous-server-design.md`

## Global Constraints

- ОС: **Debian stable** (не иммутабельная, не btrfs-снапшоты).
- Восстановление НИКОГДА не форматирует p3, p4 и HDD.
- Секреты — только на p4 (или в `.env`, подхватываемом из p4); **никогда** не коммитятся в git.
- Внутренние веб-морды НЕ торчат в интернет; доступ через Tailscale.
- SSH — только по ключам, слушает только на интерфейсе Tailscale.
- Форвард-прокси, доступный из интернета, обязан иметь аутентификацию.
- Разметка SSD 240 ГБ: `p1 ESP ~1ГБ` · `p2 root ~170ГБ` · `p3 снимок+recovery ~50ГБ` · `p4 персистент ~2ГБ`. HDD 1ТБ → `/srv/data`.
- Все docker-данные пользователя (загрузки/файлы) — на HDD (`/srv/data`), не на SSD.
- Два спайка перед финализацией: голос MC7304 (§Phase 5), CGNAT дома (§Phase 6).

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

- [ ] **Step 1: Инициализировать git**

```bash
cd /private/tmp/konotop
git init
git add docs/superpowers/specs/2026-08-30-t420-autonomous-server-design.md
git commit -m "docs: add design spec"
```

- [ ] **Step 2: Создать .gitignore (секреты никогда не в git)**

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

- [ ] **Step 3: Создать README.md**

```markdown
# konotop — автономный сервер на ThinkPad T420

Источник правды для конфигурации домашнего сервера. См.
`docs/superpowers/specs/` (дизайн) и `docs/superpowers/plans/` (план).

Секреты живут на разделе p4 сервера и НЕ хранятся здесь.
```

- [ ] **Step 4: Создать secrets/README.md (раскладка p4)**

```markdown
# Персистентная зона (p4) — вне восстановления

Recovery НИКОГДА не форматирует p4. Здесь лежат:
- tailscale/           — состояние ноды Tailscale (--statedir)
- cloudflared/         — токен туннеля, cert.json
- services.env         — TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, пароли сервисов
- proxy/               — креды форвард-прокси

Монтируется в /srv/persist. Симлинки/bind-mount из системы указывают сюда.
```

- [ ] **Step 5: Commit**

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

- [ ] **Step 1: Написать скрипт разметки**

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

- [ ] **Step 2: Создать fstab.sample**

```
# provisioning/fstab.sample — подставить UUID из `blkid`
UUID=<ESP>      /boot/efi   vfat  umask=0077                 0 2
UUID=<root>     /           ext4  errors=remount-ro          0 1
UUID=<persist>  /srv/persist ext4 defaults,nofail            0 2
UUID=<hdd>      /srv/data   ext4  defaults,nofail,x-systemd.device-timeout=10 0 2
# p3 (recovery) НЕ монтируется в fstab — используется только из recovery-среды
```

- [ ] **Step 3: Проверка (dry-run в VM или на диске)**

Run: `sudo bash provisioning/partition-ssd.sh /dev/sdX && lsblk -f /dev/sdX`
Expected: 4 раздела с метками ESP/root/recovery/persist и корректными ФС.

- [ ] **Step 4: Commit**

```bash
git add provisioning/partition-ssd.sh provisioning/fstab.sample
git commit -m "feat(provisioning): SSD partitioning script and fstab sample"
```

### Task 2: Runbook установки Debian + BIOS

**Files:**
- Create: `provisioning/install-runbook.md`

- [ ] **Step 1: Написать runbook**

```markdown
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

## Проверка
- `sudo systemctl is-enabled ssh` → enabled
- Обесточить и подать питание → ноут стартует сам.
```

- [ ] **Step 2: Commit**

```bash
git add provisioning/install-runbook.md
git commit -m "docs(provisioning): Debian install and BIOS runbook"
```

### Task 3: Базовая настройка (SSH-ключи, TLP, governor, спиндаун, апдейты)

**Files:**
- Create: `provisioning/setup-base.sh`

- [ ] **Step 1: Написать скрипт базовой настройки**

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
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# Питание/тишина
apt-get update
apt-get install -y tlp hdparm unattended-upgrades
systemctl enable --now tlp

# CPU governor powersave
echo 'GOVERNOR=powersave' >> /etc/default/cpufrequtils || true

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

- [ ] **Step 2: Проверка**

Run на боксе:
```bash
sudo bash provisioning/setup-base.sh "$(cat ~/.ssh/id_ed25519.pub)"
sudo sshd -T | grep -E 'passwordauthentication|permitrootlogin'
systemctl is-active tlp
```
Expected: `passwordauthentication no`, `permitrootlogin prohibit-password`, tlp `active`.

- [ ] **Step 3: Проверка спиндауна**

Run: `sudo hdparm -C /dev/disk/by-label/data` через 2+ мин простоя
Expected: `drive state is: standby`.

- [ ] **Step 4: Commit**

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

- [ ] **Step 1: Написать restore.sh**

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

- [ ] **Step 2: Написать rebless.sh (с сохранением старого снимка)**

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

- [ ] **Step 3: Проверка (в VM с двумя дисками)**

Run: смонтировать тестовую среду, `ROOT_PART=/dev/sdb2 REC_PART=/dev/sdb3 bash recovery/rebless.sh` затем `restore.sh`
Expected: `golden.current.img` создан, `partclone.chkimg` без ошибок, restore проходит.

- [ ] **Step 4: Commit**

```bash
git add recovery/restore.sh recovery/rebless.sh
git commit -m "feat(recovery): partclone restore and rebless scripts"
```

### Task 5: Recovery-среда и пункты GRUB

**Files:**
- Create: `recovery/build-recovery.sh`, `recovery/40_konotop`, `recovery/recovery-runbook.md`

**Interfaces:**
- Consumes: `restore.sh` (Task 4).
- Produces: GRUB-пункты «Обычная загрузка» и «Восстановить»; одноразовый вход в recovery для rebless.

- [ ] **Step 1: Собрать recovery-initramfs**

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

- [ ] **Step 2: Пункты GRUB**

```bash
# recovery/40_konotop — положить в /etc/grub.d/40_konotop, chmod +x, затем update-grub
cat <<'MENU'
menuentry 'Обычная загрузка' { search --set=root --label root; linux /boot/vmlinuz root=LABEL=root ro quiet; initrd /boot/initrd.img }
menuentry 'ВОССТАНОВИТЬ систему (данные сохранятся)' {
  search --set=root --label root
  linux /boot/vmlinuz ro konotop.recover=1 ROOT_PART=/dev/disk/by-label/root REC_PART=/dev/disk/by-label/recovery
  initrd /boot/konotop-recovery.img
}
MENU
```

- [ ] **Step 3: Runbook (установка пунктов + одноразовый rebless)**

```markdown
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
```

- [ ] **Step 4: Добавить menuentry rebless в 40_konotop**

```bash
# дописать в recovery/40_konotop:
cat <<'MENU'
menuentry 'Снять золотой снимок (для админа)' {
  search --set=root --label root
  linux /boot/vmlinuz ro konotop.rebless=1 ROOT_PART=/dev/disk/by-label/root REC_PART=/dev/disk/by-label/recovery
  initrd /boot/konotop-recovery.img
}
MENU
```
(В initramfs-хук: если `konotop.rebless=1` → запустить `rebless.sh`; если `konotop.recover=1` → `restore.sh`; иначе обычная загрузка. Добавить в build-recovery.sh включение обоих скриптов и парсер cmdline.)

- [ ] **Step 5: Проверка**

Run: `sudo bash recovery/build-recovery.sh && sudo update-grub && grep konotop /boot/grub/grub.cfg`
Expected: три пункта (обычная, восстановить, снять снимок).

- [ ] **Step 6: Commit**

```bash
git add recovery/build-recovery.sh recovery/40_konotop recovery/recovery-runbook.md
git commit -m "feat(recovery): recovery initramfs, GRUB entries, runbook"
```

---

## Phase 3 — Network

### Task 6: Tailscale + SSH на tailnet

**Files:**
- Create: `network/tailscale-runbook.md`, `network/sshd_konotop.conf`

**Interfaces:**
- Consumes: p4 (`/srv/persist`) для statedir.
- Produces: tailnet-адрес бокса; sshd только на интерфейсе `tailscale0`.

- [ ] **Step 1: Tailscale runbook (statedir на p4)**

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

- [ ] **Step 2: sshd — только на tailnet**

```
# network/sshd_konotop.conf → /etc/ssh/sshd_config.d/konotop.conf
# Слушать только на интерфейсе Tailscale (подставить tailnet-IP из runbook)
ListenAddress <TAILNET_IP>
PasswordAuthentication no
PermitRootLogin prohibit-password
```

- [ ] **Step 3: Проверка**

Run: `sudo install -m644 network/sshd_konotop.conf /etc/ssh/sshd_config.d/konotop.conf && sudo systemctl restart ssh && sudo ss -tlnp | grep :22`
Expected: sshd слушает только на tailnet-IP, не на `0.0.0.0`.

- [ ] **Step 4: Commit**

```bash
git add network/tailscale-runbook.md network/sshd_konotop.conf
git commit -m "feat(network): tailscale with persistent state, ssh bound to tailnet"
```

### Task 7: Cloudflare Tunnel + Access

**Files:**
- Create: `network/cloudflared/config.yml`, `network/cloudflared/runbook.md`

**Interfaces:**
- Consumes: Caddy на `localhost:80` (Phase 4).
- Produces: публичный `https://<host>` на веб-морду, за Cloudflare Access.

- [ ] **Step 1: config.yml**

```yaml
# network/cloudflared/config.yml — креды на p4
tunnel: <TUNNEL_UUID>
credentials-file: /srv/persist/cloudflared/<TUNNEL_UUID>.json
ingress:
  - hostname: dash.example.com
    service: http://localhost:80
  - service: http_status:404
```

- [ ] **Step 2: runbook**

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

- [ ] **Step 4: Commit**

```bash
git add network/cloudflared/
git commit -m "feat(network): cloudflare tunnel + access for public dashboard"
```

---

## Phase 4 — Docker-стек

### Task 8: Docker + Caddy + сервисы (compose)

**Files:**
- Create: `services/docker-compose.yml`, `services/Caddyfile`, `services/.env.sample`

**Interfaces:**
- Consumes: HDD `/srv/data`, p4 `/srv/persist/services.env`.
- Produces: qBittorrent, filebrowser за Caddy на `localhost:80`.

- [ ] **Step 1: docker-compose.yml**

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

- [ ] **Step 2: Caddyfile**

```
# services/Caddyfile — внутренний прокси, TLS не нужен (Tailscale/CF снаружи)
:80 {
  handle_path /torrent/* { reverse_proxy qbittorrent:8080 }
  handle_path /files/*   { reverse_proxy filebrowser:80 }
  handle /                { respond "konotop up" 200 }
}
```

- [ ] **Step 3: .env.sample**

```
# services/.env.sample — реальный .env лежит на p4 (/srv/persist/services.env), симлинк сюда
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
```

- [ ] **Step 4: Проверка конфигурации**

Run: `cd services && docker compose config && docker compose up -d && curl -s localhost:80`
Expected: `docker compose config` без ошибок; `curl` → `konotop up`; `/torrent/` и `/files/` отвечают.

- [ ] **Step 5: Commit**

```bash
git add services/docker-compose.yml services/Caddyfile services/.env.sample
git commit -m "feat(services): docker stack — caddy, qbittorrent, filebrowser"
```

### Task 9: Дашборд Homepage

**Files:**
- Create: `services/homepage/{services.yaml,settings.yaml,widgets.yaml}`; Modify: `services/docker-compose.yml`

- [ ] **Step 1: Добавить homepage в compose**

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

- [ ] **Step 2: homepage/services.yaml**

```yaml
- Сервисы:
    - qBittorrent: { href: /torrent/, description: Торренты, container: qbittorrent }
    - Файлы:       { href: /files/,   description: Файлы,     container: filebrowser }
```

- [ ] **Step 3: homepage/widgets.yaml (место на диске)**

```yaml
- resources: { disk: /data, cpu: true, memory: true }
```

- [ ] **Step 4: homepage/settings.yaml**

```yaml
title: konotop
```

- [ ] **Step 5: Проверка**

Run: `cd services && docker compose up -d && curl -s localhost:80 | grep -i konotop`
Expected: HTML дашборда со статусом контейнеров и виджетом диска.

- [ ] **Step 6: Commit**

```bash
git add services/homepage services/docker-compose.yml services/Caddyfile
git commit -m "feat(services): homepage dashboard with status and disk widget"
```

---

## Phase 5 — SMS→Telegram мост (полноценный код + TDD)

### Task 10: Парсер SMS из mmcli

**Files:**
- Create: `sms-bridge/pyproject.toml`, `sms-bridge/src/sms_bridge/__init__.py`, `sms-bridge/src/sms_bridge/modem.py`, `sms-bridge/tests/test_modem.py`

**Interfaces:**
- Produces: `modem.list_message_ids(runner) -> list[str]`; `modem.read_message(runner, msg_id) -> Sms` где `Sms = dataclass(id:str, sender:str, text:str, timestamp:str)`; `runner` — callable `(list[str]) -> str` (обёртка над subprocess, для тестируемости).

- [ ] **Step 1: pyproject.toml**

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

- [ ] **Step 2: Написать падающий тест парсера списка**

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

- [ ] **Step 4: Реализовать парсер списка**

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

- [ ] **Step 5: Тест детального парсинга (падающий)**

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

- [ ] **Step 7: Реализовать read_message**

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

- [ ] **Step 8: Запустить все тесты**

Run: `pytest tests/test_modem.py -v`
Expected: PASS (оба теста).

- [ ] **Step 9: Commit**

```bash
git add sms-bridge/pyproject.toml sms-bridge/src/sms_bridge/__init__.py sms-bridge/src/sms_bridge/modem.py sms-bridge/tests/test_modem.py
git commit -m "feat(sms): mmcli SMS parser with tests"
```

### Task 11: Отправка в Telegram

**Files:**
- Create: `sms-bridge/src/sms_bridge/telegram.py`, `sms-bridge/tests/test_telegram.py`

**Interfaces:**
- Produces: `telegram.format_message(sms: Sms) -> str`; `telegram.send(token, chat_id, text, poster=requests.post) -> bool`.

- [ ] **Step 1: Тест форматирования (падающий)**

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

- [ ] **Step 3: Реализовать format_message + send**

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

- [ ] **Step 4: Тест send с моком (падающий → пишем сразу)**

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

- [ ] **Step 5: Запустить все тесты**

Run: `pytest tests/test_telegram.py -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add sms-bridge/src/sms_bridge/telegram.py sms-bridge/tests/test_telegram.py
git commit -m "feat(sms): telegram formatting and send with tests"
```

### Task 12: Цикл моста + конфиг + запуск

**Files:**
- Create: `sms-bridge/src/sms_bridge/config.py`, `sms-bridge/src/sms_bridge/bridge.py`, `sms-bridge/src/sms_bridge/__main__.py`, `sms-bridge/tests/test_bridge.py`, `sms-bridge/Dockerfile`; Modify: `services/docker-compose.yml`

**Interfaces:**
- Consumes: `modem.*`, `telegram.*`.
- Produces: `bridge.forward_new(runner, token, chat_id, sender=telegram.send) -> int` (число пересланных, удаляет обработанные).

- [ ] **Step 1: Тест цикла (падающий)**

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

- [ ] **Step 3: Реализовать bridge.forward_new**

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

- [ ] **Step 4: config.py + __main__.py (loop)**

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

- [ ] **Step 5: Запустить все тесты моста**

Run: `pytest -v`
Expected: PASS (все тесты modem/telegram/bridge).

- [ ] **Step 6: Dockerfile + добавить в compose**

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

- [ ] **Step 7: Проверка на боксе (нужен модем)**

Run: отправить SMS на SIM в MC7304 → проверить Telegram.
Expected: сообщение пришло в бота; SMS удалена из модема (`mmcli -m any --messaging-list-sms` пуст).

- [ ] **Step 8: Commit**

```bash
git add sms-bridge/src sms-bridge/tests/test_bridge.py sms-bridge/Dockerfile services/docker-compose.yml
git commit -m "feat(sms): bridge loop, config, docker packaging"
```

### Task 13: СПАЙК — голос на MC7304

**Files:**
- Create: `sms-bridge/spike-voice.md` (результат; код спайка — throwaway)

- [ ] **Step 1: Проверить голосовые возможности модема**

Run на боксе:
```bash
mmcli -m any | grep -iE 'voice|supported'   # есть ли voice в capabilities
mmcli -m any --voice-list-calls             # поддержка команд голоса
# при наличии voice: попробовать mmcli -m any --voice-create-call=number=<num>
```

- [ ] **Step 2: Записать вывод и решение**

```markdown
# sms-bridge/spike-voice.md
## Результат
- Voice в capabilities: <да/нет>
- --voice-* команды: <работают/ошибка>
## Решение
- Если voice есть → отдельный план на звонки (SIP-мост к приложению телефона).
- Если нет → звонки отклоняются или внешний GSM-шлюз/другой модем.
```

- [ ] **Step 3: Commit**

```bash
git add sms-bridge/spike-voice.md
git commit -m "spike(sms): MC7304 voice capability investigation"
```

---

## Phase 6 — Exit-прокси

### Task 14: SOCKS5 для личных устройств (bind на tailnet)

**Files:**
- Create: `proxy/socks5-compose.yml`

**Interfaces:**
- Consumes: tailnet-IP (Task 6).
- Produces: SOCKS5 на `<TAILNET_IP>:1080`, доступный только из tailnet.

- [ ] **Step 1: socks5-compose.yml**

```yaml
# proxy/socks5-compose.yml — bind ТОЛЬКО на tailnet-IP (не 0.0.0.0)
services:
  socks5:
    image: serjs/go-socks5-proxy:latest
    restart: unless-stopped
    ports: ["<TAILNET_IP>:1080:1080"]
    environment:
      - PROXY_USER=konotop
      - PROXY_PASSWORD=${SOCKS_PASSWORD}
```

- [ ] **Step 2: Проверка**

Run: с личного устройства (в tailnet): `curl --socks5 konotop:${SOCKS_PASSWORD}@<TAILNET_IP>:1080 https://ifconfig.me`
Expected: возвращается **домашний IP родителей** (не IP устройства). С не-tailnet устройства порт недоступен.

- [ ] **Step 3: Настройка Chrome (личные устройства)**

```markdown
# в README proxy: расширение Proxy SwitchyOmega → профиль SOCKS5
# сервер <TAILNET_IP>:1080, логин konotop. Тумблер = только браузер через дом.
```

- [ ] **Step 4: Commit**

```bash
git add proxy/socks5-compose.yml
git commit -m "feat(proxy): tailnet-only socks5 for personal devices"
```

### Task 15: СПАЙК — проверка CGNAT + реализация случая рабочего ноута

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

- [ ] **Step 2: Случай 1 — форвард-прокси на боксе:443 (если НЕТ CGNAT)**

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

- [ ] **Step 3: Случай 2 — бесплатный VM-релей (если ЕСТЬ CGNAT)**

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

- [ ] **Step 5: Commit**

```bash
git add proxy/cgnat-check.md proxy/forward-proxy-compose.yml proxy/relay-runbook.md
git commit -m "feat(proxy): cgnat check, work-laptop forward proxy (both cases)"
```

---

## Self-Review (выполнено при написании)

**Spec coverage:** все 9 юзкейсов покрыты — 1 (Task 2 BIOS), 2 (Task 6 SSH/Tailscale), 3 (Tasks 4–5 recovery), 4 (Task 3 TLP/спиндаун), 5 (Task 8 Docker), 6а (Task 8 qBittorrent), 6б (Task 8 filebrowser), 7 (Tasks 10–12 SMS, Task 13 спайк звонков), 8 (Tasks 14–15), 9 (Tasks 8–9 дашборд + Task 7 Cloudflare). Персистентная зона p4 — Tasks 0/1/6/7/12. Конфиг-как-код — весь репозиторий.

**Placeholder scan:** оставлены только осознанные подстановки окружения (`<TAILNET_IP>`, `<TUNNEL_UUID>`, `dash.example.com`, `/dev/sdX`) — это значения, известные только на конкретном железе; помечены явно.

**Type consistency:** `Sms`(id,sender,text,timestamp), `list_message_ids`, `read_message`, `delete_message`, `format_message`, `send`, `forward_new` — согласованы между Tasks 10–12.

**Известные зависимости от железа/спайков:** Tasks 1–3, 5(проверка), 7(проверка), 12(Step 7), 13, 15 требуют физического бокса/модема/сети; выполняются при развёртывании, не в этой сессии.
