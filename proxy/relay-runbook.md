# Work-Laptop Relay Setup (CGNAT Case 2)

Free VM Relay Architecture (Oracle Cloud Always Free):

1. Поднять бесплатный VM (Oracle Cloud Always Free) с публичным IP.
2. На боксе и VM — WireGuard-линк (бокс инициирует исходящее соединение).
3. На VM — nginx stream / socat: публичный :443 -> WG-адрес бокса:прокси.
4. На боксе — тот же форвард-прокси с аутентификацией (из случая 1), слушает на WG.
5. Chrome SwitchyOmega -> HTTPS proxy <VM_PUBLIC_IP>:443 с логином.
Итог: трафик выходит через бокс (домашний IP), VM только точка входа.
