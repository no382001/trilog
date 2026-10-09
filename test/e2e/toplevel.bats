#!/usr/bin/env bats

# The command line and the REPL: exit codes, flags, the init file, pipe mode and answer printing.

load common

@test "exit 0 on successful query" {
  run "$TRILOG" -e "true."
  [ "$status" -eq 0 ]
}

@test "exit 0 on failed query (query failure is not process error)" {
  run "$TRILOG" -e "fail."
  [ "$status" -eq 0 ]
}

@test "exit 1 on parse error" {
  run "$TRILOG" -e "garbage@@."
  [ "$status" -eq 1 ]
}

@test "halt/0 and halt/1 terminate the process with the given status" {
  run "$TRILOG" -e "
    write(before),
    nl,
    halt(3),
    write(after).
  "
  [ "$status" -eq 3 ]
  [[ "$output" == *"before"* ]]
  [[ "$output" != *"after"* ]]

  run "$TRILOG" -e "
    write(before),
    nl,
    halt.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"before"* ]]
}

@test "uncaught exception is reported, not a crash" {
  run "$TRILOG" -e "throw(oops)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"oops"* ]]
}

@test "raw single-keypress solution-stepping: ;/space continue, other key stops" {
  skip "hangs under bats specifically (confirmed not a tty problem)"
  fifo=$(mktemp -u)
  out=$(mktemp)
  mkfifo "$fifo"

  script -qfec "$TRILOG" "$out" <"$fifo" &
  script_pid=$!
  exec {send_fd}>"$fifo" # {var}> avoids fd 3, which bats reserves for itself

  send() { sleep "$1"; printf '%s' "$2" >&"$send_fd"; sleep 0.1; }

  send 0.3 $'member(X,[1,2,3]).\n'
  [[ "$(cat "$out")" == *"X = 1"* ]]

  send 0.4 ';' # continue on ;
  [[ "$(cat "$out")" == *"X = 2"* ]]

  send 0.4 ' ' # continue on space
  [[ "$(cat "$out")" == *"X = 3"* ]]

  send 0.4 'n' # any other key stops enumeration

  send 0.4 $'write(after).\n' # REPL must still be alive afterward
  [[ "$(cat "$out")" == *"after"* ]]

  send 0.4 $'halt.\n'

  wait "$script_pid" 2>/dev/null
  exec {send_fd}>&-
  rm -f "$fifo" "$out"
}

@test "trilog -V prints git describe and the branch" {
  root="$BATS_TEST_DIRNAME/.."
  expected="trilog $(git -C "$root" describe --tags --always --dirty) ($(git -C "$root" rev-parse --abbrev-ref HEAD))"
  run make -s -C "$root" trilog
  run "$TRILOG" -V
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "exit 0 on a query that calls false/0" {
  run "$TRILOG" -e "false."
  [ "$status" -eq 0 ]
}

@test "exit 0 on thrown exception" {
  run "$TRILOG" -e "throw(boom)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"boom"* ]]
}

@test "init file (~/.trilog) is loaded by default" {
  fake_home="$(mktemp -d)"
  echo "init_marker(loaded)." > "$fake_home/.trilog"
  run env HOME="$fake_home" "$TRILOG" -e "init_marker(X), write(X)."
  rm -rf "$fake_home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"loaded"* ]]
}

@test "-f skips loading the init file" {
  fake_home="$(mktemp -d)"
  echo "init_marker(loaded)." > "$fake_home/.trilog"
  run env HOME="$fake_home" "$TRILOG" -f -e "init_marker(X), write(X)."
  rm -rf "$fake_home"
  [[ "$output" == *"existence_error"* ]]
}

@test "without -v, startup consult is silent" {
  fake_home="$(mktemp -d)"
  echo "init_marker(loaded)." > "$fake_home/.trilog"
  run env HOME="$fake_home" "$TRILOG" -e "init_marker(X), write(X)."
  rm -rf "$fake_home"
  [ "$status" -eq 0 ]
  [[ "$output" != *"?- consult("* ]]
  [[ "$output" == *"loaded"* ]]
}

@test "-v echoes the core.pl and init file consult" {
  fake_home="$(mktemp -d)"
  echo "init_marker(loaded)." > "$fake_home/.trilog"
  run env HOME="$fake_home" "$TRILOG" -v -e "init_marker(X), write(X)."
  rm -rf "$fake_home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"?- consult('"*"core.pl')."* ]]
  [[ "$output" == *"?- consult('"*".trilog')."* ]]
  [[ "$output" == *"loaded"* ]]
}

@test "-v shows false for a missing init file" {
  run env HOME=/tmp/trilog_no_such_home_dir_at_all "$TRILOG" -v -e "true."
  [ "$status" -eq 0 ]
  [[ "$output" == *"?- consult("*".trilog')."* ]]
  [[ "$output" == *"false."* ]]
}

@test "-f -v: no init file consult attempt at all" {
  fake_home="$(mktemp -d)"
  echo "init_marker(loaded)." > "$fake_home/.trilog"
  run env HOME="$fake_home" "$TRILOG" -f -v -e "true."
  rm -rf "$fake_home"
  [ "$status" -eq 0 ]
  [[ "$output" != *".trilog"* ]]
}

@test "missing input file does not leak ctx" {
  run "$TRILOG" /tmp/trilog_does_not_exist_at_all.pl
  [ "$status" -eq 1 ]
  [[ "$output" != *"AddressSanitizer"* ]]
  [[ "$output" != *"leaked"* ]]
}

@test "-h does not leak ctx" {
  run "$TRILOG" -h
  [ "$status" -eq 0 ]
  [[ "$output" != *"AddressSanitizer"* ]]
  [[ "$output" != *"leaked"* ]]
}

@test "pipe mode: query via stdin" {
  result=$(echo "append([1],[2],X)." | "$TRILOG" 2>&1)
  [[ "$result" == *"X = [1, 2]"* ]]
}

@test "pipe mode: no prompt in output" {
  result=$(echo "true." | "$TRILOG" 2>&1)
  [[ "$result" != *"?-"* ]]
}

@test "pipe mode: multiple queries" {
  result=$(printf "write(hello).\nwrite(world).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"hello"* ]]
  [[ "$result" == *"world"* ]]
}

@test "type error prints meaningful message" {
  run "$TRILOG" -e "X is hello."
  [[ "$output" == *"type_error"* ]]
}

@test "existence error for unknown predicate" {
  run "$TRILOG" -e "nonexistent_pred(1,2,3)."
  [[ "$output" == *"existence_error"* ]]
}

@test "instantiation error on unbound arithmetic" {
  run "$TRILOG" -e "X is Y + 1."
  [[ "$output" == *"instantiation_error"* ]]
}

@test "assert persists across queries in pipe" {
  result=$(printf "assert(color(red)).\ncolor(X), write(X).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"red"* ]]
}

@test "empty expression" {
  run "$TRILOG" -e ""
  # should not crash
  true
}

@test "-h prints usage and exits" {
  run "$TRILOG" -h
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"-e"* ]]
}

@test "pipe mode: all solutions printed with semicolons" {
  result=$(printf "member(X, [aa,bb,cc]).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"X = aa"* ]]
  [[ "$result" == *"X = bb"* ]]
  [[ "$result" == *"X = cc"* ]]
  [[ "$result" == *";"* ]]
}
