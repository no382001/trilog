#!/usr/bin/env bats

TRILOG="./trilog"

# --- exit code contract ---

@test "exit 0 on successful query" {
  run "$TRILOG" -e "true."
  [ "$status" -eq 0 ]
}

@test "exit 0 on failed query (query failure is not process error)" {
  run "$TRILOG" -e "false."
  [ "$status" -eq 0 ]
}

@test "exit 1 on parse error" {
  run "$TRILOG" -e "garbage@@."
  [ "$status" -eq 1 ]
}

@test "exit 0 on thrown exception" {
  run "$TRILOG" -e "throw(boom)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"boom"* ]]
}

# --- file loading (positional arg) ---

@test "positional file arg loads clauses and -e can query them" {
  run "$TRILOG" test/upstream_family.pl -e "parent(tom,X), write(X)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"bob"* ]]
}

@test "positional file arg with nonexistent file exits nonzero" {
  run "$TRILOG" nonexistent_file.pl -e "true."
  [ "$status" -ne 0 ]
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

# --- -v (verbose startup consult) ---

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

# regression
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

# --- pipe (non-interactive) mode ---

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

# --- quad runner (quad.pl) ---

@test "quad_cli exits 0 on passing tests" {
  echo '?- 1 =:= 1.' > /tmp/trilog_pass_quad.pl
  echo '   true.' >> /tmp/trilog_pass_quad.pl
  run "$TRILOG" -e "consult('lib/quad.pl'), quad_cli('/tmp/trilog_pass_quad.pl')"
  [ "$status" -eq 0 ]
  rm -f /tmp/trilog_pass_quad.pl
}

@test "quad_cli exits 1 on failing test" {
  echo '?- 1 =:= 2.' > /tmp/trilog_fail_quad.pl
  echo '   true.' >> /tmp/trilog_fail_quad.pl
  run "$TRILOG" -e "consult('lib/quad.pl'), quad_cli('/tmp/trilog_fail_quad.pl')"
  [ "$status" -eq 1 ]
  rm -f /tmp/trilog_fail_quad.pl
}

# --- error messages ---

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

# --- multiple expressions in sequence ---

@test "assert persists across queries in pipe" {
  result=$(printf "assert(color(red)).\ncolor(X), write(X).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"red"* ]]
}

# --- consult via -e ---

@test "consult and query in one expression" {
  run "$TRILOG" -e "consult('test/upstream_family.pl'), parent(tom,bob)."
  [ "$status" -eq 0 ]
}

# --- STR type consistency ---

@test "string unification" {
  run "$TRILOG" -e "X = \"hello\", X = [h,e,l,l,o], write(ok)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "string in arithmetic context gives type error" {
  run "$TRILOG" -e "X is \"hello\"."
  [[ "$output" == *"type_error"* ]]
}

# --- edge cases ---

@test "empty expression" {
  run "$TRILOG" -e ""
  # should not crash
  true
}

@test "deeply nested term doesn't crash" {
  run "$TRILOG" -e "X = f(f(f(f(f(f(f(f(f(f(a)))))))))), write(ok)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "long atom name doesn't crash" {
  run "$TRILOG" -e "X = abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz, write(ok)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

# --- help flag ---

@test "-h prints usage and exits" {
  run "$TRILOG" -h
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"-e"* ]]
}

# --- JUnit XML output (quad_cli_junit) ---

@test "quad_cli_junit produces JUnit XML" {
  rm -rf /tmp/trilog_junit_test
  mkdir -p /tmp/trilog_junit_test
  echo '?- 1 =:= 1.' > /tmp/trilog_junit_quad.pl
  echo '   true.' >> /tmp/trilog_junit_quad.pl
  run "$TRILOG" -e "consult('lib/quad.pl'), quad_cli_junit('/tmp/trilog_junit_quad.pl', '/tmp/trilog_junit_test')"
  [ "$status" -eq 0 ]
  [ -f /tmp/trilog_junit_test/trilog_junit_quad.xml ]
  [[ "$(cat /tmp/trilog_junit_test/trilog_junit_quad.xml)" == *"<testsuite"* ]]
  [[ "$(cat /tmp/trilog_junit_test/trilog_junit_quad.xml)" == *"<testcase"* ]]
  rm -rf /tmp/trilog_junit_test /tmp/trilog_junit_quad.pl
}

# --- catch/throw ---

@test "catch traps exception, recovery goal runs" {
  result=$(printf "catch(throw(boom), boom, write(caught)).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"caught"* ]]
}

@test "catch passes through on no exception" {
  result=$(printf "catch(write(ok), _, write(bad)).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"ok"* ]]
  [[ "$result" != *"bad"* ]]
}

# --- file I/O from Prolog ---

@test "open/write/close creates file with content" {
  rm -f /tmp/trilog_fio_test.txt
  printf "open('/tmp/trilog_fio_test.txt', write, S), write(S, hello_world), close(S).\n" \
    | "$TRILOG" >/dev/null 2>&1
  [ -f /tmp/trilog_fio_test.txt ]
  [[ "$(cat /tmp/trilog_fio_test.txt)" == *"hello_world"* ]]
  rm -f /tmp/trilog_fio_test.txt
}

# --- backtracking in pipe mode ---

@test "pipe mode: all solutions printed with semicolons" {
  result=$(printf "member(X, [aa,bb,cc]).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"X = aa"* ]]
  [[ "$result" == *"X = bb"* ]]
  [[ "$result" == *"X = cc"* ]]
  [[ "$result" == *";"* ]]
}

# --- directives in consulted files ---

@test "directive in .pl file executes on consult" {
  printf ":- assert(from_directive(yes)).\n" > /tmp/trilog_dir_test.pl
  result=$(printf "consult('/tmp/trilog_dir_test.pl').\nfrom_directive(X), write(X).\n" \
    | "$TRILOG" 2>&1)
  [[ "$result" == *"yes"* ]]
  rm -f /tmp/trilog_dir_test.pl
}

# --- multiple consults coexist ---

@test "two consulted files both available" {
  printf "fruit(apple).\n" > /tmp/trilog_a.pl
  printf "veggie(carrot).\n" > /tmp/trilog_b.pl
  result=$(printf "consult('/tmp/trilog_a.pl').\nconsult('/tmp/trilog_b.pl').\nfruit(X), write(X), nl.\nveggie(Y), write(Y).\n" \
    | "$TRILOG" 2>&1)
  [[ "$result" == *"apple"* ]]
  [[ "$result" == *"carrot"* ]]
  rm -f /tmp/trilog_a.pl /tmp/trilog_b.pl
}

# --- asserta vs assertz ordering ---

@test "asserta inserts before, assertz after" {
  result=$(printf "assert(c(bb)).\nasserta(c(aa)).\nassert(c(cc)).\nfindall(X,c(X),L), write(L).\n" \
    | "$TRILOG" 2>&1)
  [[ "$result" == *"[aa, bb, cc]"* ]]
}

# --- higher-order predicates ---

@test "maplist applies predicate to each element" {
  printf "inc(X,Y) :- Y is X + 1.\n" > /tmp/trilog_map.pl
  result=$(printf "consult('/tmp/trilog_map.pl').\nmaplist(inc, [1,2,3], L), write(L).\n" \
    | "$TRILOG" 2>&1)
  [[ "$result" == *"[2, 3, 4]"* ]]
  rm -f /tmp/trilog_map.pl
}

@test "foldl accumulates over list" {
  printf "add(X, S0, S) :- S is S0 + X.\n" > /tmp/trilog_fold.pl
  result=$(printf "consult('/tmp/trilog_fold.pl').\nfoldl(add, [1,2,3,4], 0, Sum), write(Sum).\n" \
    | "$TRILOG" 2>&1)
  [[ "$result" == *"10"* ]]
  rm -f /tmp/trilog_fold.pl
}

# --- between/3 ---

@test "between generates integer range" {
  result=$(printf "findall(X, between(1,5,X), L), write(L).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"[1, 2, 3, 4, 5]"* ]]
}

# --- with_output_to ---

@test "with_output_to captures write into atom" {
  result=$(printf "with_output_to(atom(X), write(hello)), write(X).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"hello"* ]]
}

# --- term_to_atom / atom_to_term roundtrip ---

@test "term_to_atom and atom_to_term roundtrip" {
  result=$(printf "term_to_atom(foo(1,bar), A), atom_to_term(A, T, _), write(T).\n" \
    | "$TRILOG" 2>&1)
  [[ "$result" == *"foo(1, bar)"* ]]
}

# --- copy_term ---

@test "copy_term preserves structure with fresh vars" {
  result=$(printf "copy_term(f(X,X), f(A,B)), A = hello, write(B).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"hello"* ]]
}
