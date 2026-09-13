# Proxy Configuration

## Personal Devices (SOCKS5)

Use the **Proxy SwitchyOmega** Chrome extension with the following SOCKS5 profile:
- **Server:** `<TAILNET_IP>:1080`
- **Protocol:** SOCKS5
- **Username:** `konotop`
- **Password:** `${SOCKS_PASSWORD}`

Switch the extension toggle to use this profile only for browser traffic through home network (tailnet-only).

## Настройка на сервере (перед `docker compose up`)

- socks5-compose.yml: заменить <TAILNET_IP> на реальный Tailscale-IP бокса
  (`tailscale ip -4`), иначе прокси нельзя поднять (это защита от bind на 0.0.0.0).
- forward-proxy (случай 1): скопировать squid.conf.sample → squid.conf,
  создать passwords (htpasswd), настроить TLS-сертификат.
