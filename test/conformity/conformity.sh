#!/bin/bash
# Ulrich Neumerkel's ISO syntax conformity tests:
# https://www.complang.tuwien.ac.at/ulrich/iso-prolog/conformity_testing
# conformity.txt is taken from flowlog (https://git.liminal.cafe/byakuren/flowlog,
# tests/ulrich). Each test is "number RS query RS expected answer", tests are
# separated by GS. The query is piped into the toplevel.
#
# Prints TAP; -v adds the expected and actual output under each failure.
#
# usage: test/conformity/conformity.sh [-v] [test-number...]

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="${TRILOG:-$ROOT/trilog}"
FILE="$ROOT/test/conformity/conformity.txt"
MEM_KB=524288
GS=$'\x1D'
RS=$'\x1E'

verbose=false
if [[ $1 == -v ]]; then
  verbose=true
  shift
fi
only=" $* "

trim() {
  local s="$1"
  s="${s#"${s%%[!$'\n\r']*}"}"
  s="${s%"${s##*[!$'\n\r']}"}"
  printf '%s' "$s"
}


last_line() {
  printf '%s\n' "$1" | sed -e 's/[[:space:]]*$//' | grep -v '^$' | tail -1
}

run() {
  local errf
  errf="$(mktemp)"
  out="$(printf '%s\n' "$1" | (ulimit -v $MEM_KB; timeout 5 "$BIN" -f 2>"$errf"))"
  code=$?
  err="$(cat "$errf")"
  rm -f "$errf"
}

# The query's text stays open on a fifo; a toplevel still reading after a
# second is waiting for the rest of the term.
run_waits() {
  local dir
  dir="$(mktemp -d)"
  mkfifo "$dir/in"
  (ulimit -v $MEM_KB; timeout 5 "$BIN" -f <"$dir/in" >"$dir/out" 2>"$dir/err") &
  local pid=$!
  exec 3>"$dir/in"
  printf '%s\n' "$1" >&3
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    code=124
    kill "$pid" 2>/dev/null
  else
    code=0
  fi
  exec 3>&-
  wait "$pid" 2>/dev/null
  out="$(cat "$dir/out")"
  err="$(cat "$dir/err")"
  rm -rf "$dir"
}

# The expected error term, printed the way the toplevel prints one.
expected_error() {
  printf '%s\n' "X = ($1), writeq(X), nl." |
    (ulimit -v $MEM_KB; timeout 5 "$BIN" -f 2>/dev/null) | head -1
}

no_errors() { [[ $err != *"parse error"* && $err != *"uncaught exception"* ]]; }

check() {
  local answer="$1"
  case "$answer" in
  'syntax err.') [[ $err == *"parse error"* ]] ;;
  'waits') [[ $code == 124 ]] && no_errors ;;
  'succeeds') no_errors && [[ $(last_line "$out") != *false. ]] && [[ -n $(last_line "$out") ]] ;;
  'fails') no_errors && [[ $(last_line "$out") == *false. ]] ;;
  error\(*)
    local got
    got="$(printf '%s\n' "$err" | grep 'uncaught exception: ' | tail -1)"
    got="${got#uncaught exception: }"
    [[ -n $got && $got == "$(expected_error "$answer")" ]]
    ;;
  *) no_errors && [[ $(last_line "$out") == "$(printf '%s' "$answer" | sed -e 's/[[:space:]]*$//')" ]] ;;
  esac
}

mapfile -d "$GS" -t groups <"$FILE"
pass=0
fail=0
for group in "${groups[@]}"; do
  [[ -z $(trim "$group") ]] && continue
  mapfile -d "$RS" -t fields <<<"$group"
  num="$(trim "${fields[0]}")"
  query="$(trim "${fields[1]}")"
  answer="$(trim "${fields[2]}")"
  [[ -z $num || ${answer:0:1} == "#" ]] && continue
  [[ $only != "  " && $only != *" $num "* ]] && continue

  if [[ $answer == waits ]]; then
    run_waits "$query"
  else
    run "$query"
  fi
  name="#$num ${query//$'\n'/ ⏎ }"
  if check "$answer"; then
    pass=$((pass + 1))
    printf 'ok %d - %s\n' "$((pass + fail))" "$name"
  else
    fail=$((fail + 1))
    printf 'not ok %d - %s\n' "$((pass + fail))" "$name"
    if $verbose; then
      printf '# expected: %s\n# stdout:   %s\n# stderr:   %s\n' \
        "${answer//$'\n'/ ⏎ }" "${out//$'\n'/ ⏎ }" "${err//$'\n'/ ⏎ }"
    fi
  fi
done
printf '1..%d\nconformity: %d passed, %d failed of %d\n' "$((pass + fail))" "$pass" "$fail" "$((pass + fail))"
