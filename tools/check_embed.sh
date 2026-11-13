#!/bin/sh
# usage: tools/check_embed.sh IMAGE_FILES EMBEDDED... -- USERS...
# IMAGE_FILES lists the files the image loaded, one path per line. Fails when
# a USERS file uses a library that is neither EMBEDDED nor in the image.
set -eu
image=$1
shift
embedded=" "
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do
  embedded="$embedded$1 "
  shift
done
[ "$#" -gt 0 ] && shift
status=0
for f in "$@"; do
  for n in $(grep -v -E '^[[:space:]]*%' "$f" | grep -oE 'library\([a-z_0-9]+\)' |
    sed -e 's/library(//' -e 's/)//' | sort -u); do
    case "$embedded" in *" lib/$n.pl "*) continue ;; esac
    grep -q "/lib/$n\.pl\$" "$image" && continue
    echo "$f uses library($n), which is neither embedded nor in the image" >&2
    status=1
  done
done
exit "$status"
