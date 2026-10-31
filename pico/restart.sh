#!/bin/bash
# Restarts a Pico running trilog: Ctrl-C stops whatever runs, reboot/0 reset.
# usage: pico/restart.sh [serial port]
set -u
PORT=${1:-$(ls /dev/ttyACM* 2>/dev/null | head -1)}
[ -n "$PORT" ] || { echo "no board found"; exit 1; }

stty -F "$PORT" 115200 raw -echo || exit 1
exec 3<>"$PORT"
cat <&3 >/dev/null &
reader=$!
printf '\003' >&3
sleep 0.5
printf 'reboot.\r' >&3

for _ in $(seq 40); do
  [ -e "$PORT" ] || break
  sleep 0.25
done
exec 3>&-
kill "$reader" 2>/dev/null
[ ! -e "$PORT" ] || { echo "$PORT did not go away bc the board did not restart"; exit 1; }

for _ in $(seq 40); do
  [ -e "$PORT" ] && break
  sleep 0.25
done
echo "board is back on $PORT"
