# CGNAT Detection Procedure

1. На устройстве в домашней сети: `curl ifconfig.me` → PUBLIC_IP
2. В админке роутера — WAN-IP.
3. Совпадают и не из 100.64.0.0/10 → CGNAT НЕТ (случай 1).
   Иначе → CGNAT ЕСТЬ (случай 2).
Результат: <записать>
