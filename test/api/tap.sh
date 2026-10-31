#!/bin/bash

for prog in "$@"; do
  out="$("$prog" 2>&1)"
  code=$?
  tap="$(printf '%s\n' "$out" | grep -E '^(not )?ok([ \t]|$)|^#')"
  if [[ -n $tap ]]; then
    printf '%s\n' "$tap"
    if [[ $code != 0 && $tap != *"not ok"* ]]; then
      printf 'not ok - %s exited %d\n' "$prog" "$code"
    fi
  elif [[ $code == 0 ]]; then
    printf 'ok - %s\n' "$prog"
  else
    printf 'not ok - %s exited %d\n' "$prog" "$code"
    printf '%s\n' "$out" | sed 's/^/# /'
  fi
done
