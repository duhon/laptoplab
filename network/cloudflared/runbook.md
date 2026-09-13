# network/cloudflared/runbook.md
1. `cloudflared tunnel login`
2. `cloudflared tunnel create konotop`
3. Переместить креды в /srv/persist/cloudflared/ (p4).
4. DNS: `cloudflared tunnel route dns konotop dash.example.com`
5. Cloudflare Zero Trust → Access → приложение на dash.example.com,
   политика: email = <твой email>, метод One-time PIN.
6. Запуск как сервис: `cloudflared service install`, конфиг из config.yml.
