#!/bin/bash
# Prints the board's IP address. Asking needs the prompt, so this stops the
# server with Ctrl-C and starts it again after the answer.
# usage: pico/get-ip.sh [serial port]
set -u
PORT=${1:-$(ls /dev/ttyACM* 2>/dev/null | head -1)}
[ -n "$PORT" ] || { echo "no board found"; exit 1; }

out=$(mktemp)
trap 'rm -f "$out"' EXIT
stty -F "$PORT" 115200 raw -echo || exit 1
exec 3<>"$PORT"
cat <&3 >"$out" &
reader=$!
printf '\003' >&3
sleep 0.5
printf "wifi_ip(A), write('ip: '), write(A), nl, serve(80).\r" >&3
for _ in $(seq 20); do
  grep -q 'ip: [0-9]\|false\.' "$out" && break
  sleep 0.25
done
exec 3>&-
kill "$reader" 2>/dev/null

ip=$(grep -o 'ip: [0-9][0-9.]*' "$out" | head -1)
[ -n "$ip" ] || { echo "the board has no IP: WiFi is not connected"; exit 1; }
echo "${ip#ip: }"
