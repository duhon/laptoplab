# network/tailscale-runbook.md
1. `curl -fsSL https://tailscale.com/install.sh | sh`
2. Состояние — на p4 (переживает восстановление):
   `sudo mkdir -p /srv/persist/tailscale`
   Правка unit: `--state=/srv/persist/tailscale/tailscaled.state`
3. `sudo tailscale up --ssh --advertise-exit-node`
   (exit-node пригодится для личных устройств; включается тумблером у клиента)
4. Записать tailnet-IP: `tailscale ip -4`

## Доступ к веб-морде из tailnet (без выставления в LAN)
Caddy слушает только на 127.0.0.1:80. Чтобы дашборд был доступен твоим
устройствам в tailnet, включить Tailscale Serve:
`sudo tailscale serve --bg 80`
(проксирует tailnet → 127.0.0.1:80 с TLS; в LAN ничего не открывается).
