#!/usr/bin/env bash
set -euo pipefail

nas_ip=192.168.68.59

direct_ip="$(curl -fsS --max-time 15 https://ifconfig.me/ip)"
proxy_ip="$(curl -fsS --max-time 15 --socks5-hostname "$nas_ip:1080" https://ifconfig.me/ip)"

if [[ "$direct_ip" != "$proxy_ip" ]]; then
  echo "SOCKS proxy egress does not match konotop's direct egress" >&2
  exit 1
fi

echo "Unauthenticated SOCKS proxy and home egress verified"
