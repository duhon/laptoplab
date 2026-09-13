# network/tailscale-runbook.md
1. `curl -fsSL https://tailscale.com/install.sh | sh`
2. Состояние — на p4 (переживает восстановление):
   `sudo mkdir -p /srv/persist/tailscale`
   Правка unit: `--state=/srv/persist/tailscale/tailscaled.state`
3. `sudo tailscale up --ssh --advertise-exit-node`
   (exit-node пригодится для личных устройств; включается тумблером у клиента)
4. Записать tailnet-IP: `tailscale ip -4`
