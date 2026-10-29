#!/bin/bash
# Copies a UF2 to a Pico on USB, restarting it into BOOTSEL first if needed.
# usage: pico/flash.sh [file.uf2] [serial port]
set -u
UF2=${1:-$(dirname "$0")/build/trilog.uf2}
PORT=${2:-$(ls /dev/ttyACM* 2>/dev/null | head -1)}

find_drive() { lsblk -rno PATH,LABEL | awk '$2 == "RPI-RP2" { print $1 }'; }

drive=$(find_drive)
if [ -z "$drive" ]; then
  [ -n "$PORT" ] || { echo "no board found: plug it in, or hold BOOTSEL while plugging it in"; exit 1; }
  echo "restarting $PORT into BOOTSEL"
  stty -F "$PORT" 1200 || exit 1
fi

for _ in $(seq 40); do
  drive=$(find_drive)
  [ -n "$drive" ] && break
  sleep 0.25
done
[ -n "$drive" ] || { echo "the RPI-RP2 drive did not appear"; exit 1; }

dir=
for _ in $(seq 20); do
  dir=$(lsblk -rno MOUNTPOINT "$drive")
  [ -n "$dir" ] && break
  udisksctl mount -b "$drive" >/dev/null 2>&1
  sleep 0.25
done
[ -n "$dir" ] || { echo "could not mount $drive"; exit 1; }

echo "copying $UF2 to $dir"
cp "$UF2" "$dir"/ && sync || exit 1

port=
for _ in $(seq 40); do
  port=$(ls /dev/ttyACM* 2>/dev/null | head -1)
  [ -n "$port" ] && break
  sleep 0.25
done
echo "board is back on ${port:-(no serial port yet)}"
