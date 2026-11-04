#!/bin/bash
# Ulrich Neumerkel's ISO syntax conformity table, as published:
# https://www.complang.tuwien.ac.at/ulrich/iso-prolog/conformity_testing
# usage: test/conformity/conformity.sh [-v] [test-number...]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${TRILOG:-$ROOT/trilog}"
FILE="$ROOT/test/conformity/conformity.txt"
RUN="$ROOT/test/conformity/run.pl"
MEM_KB=524288
GS=$'\x1D'
RS=$'\x1E'

verbose=false
if [[ $1 == -v ]]; then
  verbose=true
  shift
fi
only=" $* "

field() {
  local s="${1#$'\n'}"
  printf '%s' "${s%$'\n'}"
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mapfile -d "$GS" -t groups <"$FILE"
pass=0
fail=0
setup=""
for group in "${groups[@]}"; do
  mapfile -d "$RS" -t fields <<<"$group"
  num="$(field "${fields[0]}")"
  query="$(field "${fields[1]}")"
  answer="$(field "${fields[2]}")"
  [[ -z $num ]] && continue

  setup_file=""
  # The page: /**/ stands for the last entry before it without one.
  if [[ $query == "/**/"* ]]; then
    printf '%s\n' "$setup" >"$tmp/setup"
    setup_file="$tmp/setup"
    query="${query#/\*\*/}"
    query="${query# }"
  else
    setup="$query"
  fi
  [[ $only != "  " && $only != *" $num "* ]] && continue

  printf '%s\n' "$answer" >"$tmp/answer"
  result="$(printf '%s\n' "$query" |
    (ulimit -v $MEM_KB; timeout 5 "$BIN" -f "$RUN" \
      -e "conformity('$setup_file', '$tmp/answer')." 2>&1))"

  name="#$num ${query//$'\n'/ ⏎ }"
  if [[ $result == pass* ]]; then
    pass=$((pass + 1))
    printf 'ok %d - %s\n' "$((pass + fail))" "$name"
  else
    fail=$((fail + 1))
    printf 'not ok %d - %s\n' "$((pass + fail))" "$name"
    if $verbose; then
      printf '%s\n' "${result#fail$'\n'}" | sed 's/^/# /'
    fi
  fi
done
printf '1..%d\nconformity: %d passed, %d failed of %d\n' "$((pass + fail))" "$pass" "$fail" "$((pass + fail))"
