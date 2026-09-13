# Персистентная зона (p4) — вне восстановления

Recovery НИКОГДА не форматирует p4. Здесь лежат:
- tailscale/           — состояние ноды Tailscale (--statedir)
- cloudflared/         — токен туннеля, cert.json
- services.env         — TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, пароли сервисов
- proxy/               — креды форвард-прокси

Монтируется в /srv/persist. Симлинки/bind-mount из системы указывают сюда.
