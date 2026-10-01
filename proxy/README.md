# Proxy Configuration

## Personal Devices (SOCKS5)

Use the **Proxy SwitchyOmega** Chrome extension with the following SOCKS5 profile:
- **Server:** `100.65.92.104:1080`
- **Protocol:** SOCKS5
- **Authentication:** none

Switch the extension toggle to use this profile only for browser traffic through home network (tailnet-only).

## Рабочий ноут через NAS

Рабочий ноут без Tailscale использует NAS в своей LAN как локальный TCP-релей:

- **Server:** `<NAS_LAN_IP>:1080` (currently `192.168.68.59:1080`)
- **Protocol:** SOCKS5
- **Authentication:** none

Релей на NAS пересылает запрос в tailnet к SOCKS5 на konotop. Только браузер с
включённым профилем выходит через домашний IP. Прокси не требует авторизации и
доступен любому устройству, которому доступен адрес NAS:1080 в LAN. Использовать
только в доверенной LAN. Для недоверенной LAN использовать SSH-туннель.
Deployment и проверка — в `network/nas/nas-bridge-runbook.md`.

## Настройка на сервере (перед `docker compose up`)

- `socks5-compose.yml` слушает только на `KONOTOP_TS_IP` (сейчас `100.65.92.104`).
- SOCKS5 не требует пароля; любой узел tailnet, имеющий доступ к этому адресу,
  может использовать прокси.
- forward-proxy (случай 1): скопировать squid.conf.sample → squid.conf,
  создать passwords (htpasswd), настроить TLS-сертификат.
