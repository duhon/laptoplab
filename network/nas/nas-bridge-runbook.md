# NAS-мост: доступ рабочего ноута к konotop через tailnet

Рабочий ноут **не может** запускать Tailscale. Но в его LAN есть NAS. NAS входит
в tailnet и становится мостом к домашнему серверу konotop. Закрывает три
потребности рабочего ноута:

1. **Homepage NAS с сервисами konotop** — через reverse proxy на NAS.
2. **SSH к konotop** — через NAS TCP-релей (end-to-end SSH).
3. **Домашний IP для сайтов** — браузер ноута → SOCKS5-релей на NAS → SOCKS5 на
   konotop (выход в интернет = домашний IP родителей). Селективно: через прокси
   идёт только браузер, остальной трафик NAS/ноута не затрагивается.

```
[рабочий ноут] --LAN--> [NAS в tailnet] --tailnet--> [konotop (дома)]
   браузер/ssh            proxy+relay              Caddy :80 / sshd / SOCKS5
```

## Обследованный NAS (факт)

- Модель/ОС: **Odroid M1S**, Armbian (Debian trixie), **arm64**.
  (Сейчас поверх стоит OpenMediaVault, но он **временный** и удаляется — на его
  сервисы и порты не опираемся.)
- Docker есть; контейнеры ведём через **Portainer** (:9000) или прямо из
  консоли (`docker compose`). Пользователь `duhon` не в группе `docker` →
  CLI-команды через `sudo`.
- LAN-IP NAS: **192.168.68.59** (iface `enP2p33s0`).
- Сейчас слушают (часть — от временного OMV): :80 homepage, :8080 OMV GUI,
  :8091 diskstatus, :9000 portainer, :22 ssh, :139/:445 samba. После снятия OMV
  часть портов освободится; перед деплоем перепроверить `ss -ltnp`.
- Tailscale: установлен и NAS авторизован в tailnet как `odroidm1s`
  (`100.123.127.87`); `tailscale ping konotop` проходит.
- Tailscale Serve на `konotop` включён: `konotop.tailb4dba1.ts.net` → Caddy
  `127.0.0.1:80`; с NAS по HTTPS получен HTTP 200.
- Выбраны LAN-порты моста: панель **8095**, SOCKS-релей **1080**. Перед
  запуском повторно проверить их доступность. Они не зависят от временного OMV.

Значения (tailnet-IP, MagicDNS-имя, порты) — в `network/nas/.env`
(см. `.env.sample`). Реальный `.env` **не коммитить**.

---

## Task 7 — NAS в tailnet

Tailscale установлен на обычный Armbian без зависимости от OMV:

```bash
sudo tailscale status             # odroidm1s и konotop видны в списке
sudo tailscale ping konotop       # проверено: pong, 23 ms
tailscale ip -4                   # NAS: 100.123.127.87
```

HTTPS-доступ NAS → `https://konotop.tailb4dba1.ts.net/` проверен: HTTP 200.

LAN-IP NAS уже известен: **192.168.68.59**.

> Стек моста заводим через **Portainer** или из консоли:
> - **Portainer** (:9000): Stacks → Add stack → вставить содержимое
>   `network/nas/docker-compose.yml`, переменные из `.env` — в разделе
>   Environment variables.
> - **CLI**: скопировать `network/nas/` на NAS и
>   `sudo docker compose -f network/nas/docker-compose.yml up -d`.
>
> Сетевые контейнеры используют host network, чтобы выходить к Tailscale peers
> через host route. Caddy и socat привязывают входные listener'ы к LAN-IP NAS.

---

## Task 8 — Веб-панель и SSH konotop через NAS

### На konotop — опубликовать панель в tailnet

Caddy слушает только `127.0.0.1:80`. Включить Tailscale Serve, чтобы панель была
доступна узлам tailnet (в том числе NAS) по HTTPS на MagicDNS-имени:

```bash
sudo tailscale serve --bg 80
tailscale serve status            # https://konotop.tailb4dba1.ts.net → 127.0.0.1:80
```

В LAN при этом ничего не открывается — только внутри tailnet.

### На NAS — Homepage и reverse proxy к сервисам

```bash
cp network/nas/.env.sample network/nas/.env
# проверить NAS_LAN_IP, NAS_BRIDGE_DIR, KONOTOP_TS_IP, KONOTOP_HOST и порты
sudo docker compose --env-file network/nas/.env \
  -f network/nas/docker-compose.yml up -d panel-proxy ssh-relay
```

Корень `http://<NAS_LAN_IP>:<PANEL_PORT>` показывает Homepage самого NAS, где
размещены ссылки на сервисы konotop. Пути `/torrent/`, `/files/` и `/portainer/`
проксируются в tailnet к соответствующим сервисам. Проверка (закрывает
потребность 1): открыть Homepage и перейти по ссылкам на сервисы.
Этот участок использует HTTP в локальной сети; пользоваться им только в доверенной
LAN. Для недоверенной сети можно вместо этого открыть локальный SSH-туннель:
`ssh -N -L 8095:127.0.0.1:80 -p 2222 duhon@192.168.68.59` и перейти на
`http://127.0.0.1:8095`.

### (Опция) Ссылки на konotop в Homepage самого NAS

На NAS уже работает своя Homepage (`http://192.168.68.59`, конфиг в
`/docker-files/homepage/config/services.yaml`). Группа ссылок konotop добавлена;
до правки создана резервная копия
`/docker-files/homepage/config/services.yaml.bak.before-konotop`. Блок-источник
в репозитории: `network/nas/homepage-konotop-group.yaml`. Рабочий ноут открывает
панель NAS и переходит к konotop одним кликом.

### SSH к konotop через TCP-релей на NAS

У sshd NAS отключён TCP forwarding, поэтому используем отдельный socat-контейнер
в Docker. Он принимает соединение на LAN-IP NAS:2222 и пересылает TCP напрямую
на `konotop` tailnet-IP:22. SSH-шифрование и аутентификация идут end-to-end между
рабочим ноутом и konotop; ключ на NAS не копируется. Listener доступен только на
LAN-IP NAS.

На **рабочем ноуте** добавь в `~/.ssh/config`:

```
Host konotop
    HostName 192.168.68.59            # LAN-IP NAS
    Port 2222                         # SSH relay → konotop:22
    User duhon
    IdentityFile ~/.ssh/<WORK_KEY>
```

На konotop публичный ключ рабочего ноута должен быть в
`/home/duhon/.ssh/authorized_keys`. На NAS копировать его не нужно.

Для администрирования из LAN можно выполнить `ssh -p 2222 duhon@192.168.68.59`;
ключ и host key принадлежат konotop, TCP-релей не завершает SSH-сессию.
Проверка (закрывает потребность 2): `ssh konotop` с рабочего ноута — вход по
ключу в konotop. При первом подключении проверь host-key fingerprint konotop.

---

## Task 9 — Домашний IP для браузера рабочего ноута

### На konotop — SOCKS5 без авторизации на tailnet-IP

Прокси слушает только на tailnet-IP konotop, но не требует логин/пароль. Его
могут использовать узлы tailnet, которым доступен этот адрес. Выход в интернет
идёт с домашнего IP (сам konotop — дома).

```bash
sudo sh -c 'grep -q "^KONOTOP_TS_IP=" /srv/persist/services.env ||
  printf "KONOTOP_TS_IP=100.65.92.104\n" >> /srv/persist/services.env'

# из каталога репозитория на konotop:
sudo docker compose --env-file /srv/persist/services.env \
  -f proxy/socks5-compose.yml up -d
sudo ss -ltnp | grep 100.65.92.104:1080   # только tailnet-IP
```

### На NAS — TCP-релей LAN → SOCKS5 konotop

```bash
sudo docker compose --env-file .env -f docker-compose.yml up -d socks-relay
```

Релей пробрасывает `<NAS_LAN_IP>:<SOCKS_PORT>` → `KONOTOP_TS_IP:1080` без
авторизации. Любое устройство, которому доступен NAS на этом порту, сможет
использовать домашний IP; использовать только в доверенной LAN. Для недоверенной
сети вместо него поднимать локальный SSH-туннель через порт `2222`.

Проверить пароль и совпадение прямого/проксированного egress с konotop:

```bash
bash network/nas/test-socks-route.sh
```

### На рабочем ноуте — браузер через прокси

Chrome + Proxy SwitchyOmega, профиль SOCKS5:
- Server: `<NAS_LAN_IP>`, Port: `<SOCKS_PORT>`
- Authentication: none

Тумблер = только браузер идёт через дом; остальной трафик ноута — напрямую.

Проверка (закрывает потребность 3): с включённым профилем открыть
`https://ifconfig.me` → **домашний IP родителей**. С выключенным — обычный IP.

---

## Итоговая проверка фазы 3

| Потребность | Путь | Проверка |
|---|---|---|
| Веб-панель | ноут → NAS panel-proxy → serve → Caddy | `http://<NAS_LAN_IP>:<PANEL_PORT>` открывает дашборд |
| SSH | ноут → NAS TCP relay → konotop | `ssh konotop` входит по ключу |
| Домашний IP | ноут-браузер → NAS socks-relay → SOCKS5 konotop | `ifconfig.me` = домашний IP |

Если NAS-мост по какой-то причине не подходит — см. опциональные альтернативы в
Phase 7 (Cloudflare Tunnel, прямой прокси на :443, VM-релей при CGNAT).
