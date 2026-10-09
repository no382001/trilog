#!/usr/bin/env bats

# Loading code: file arguments, consult/reconsult/unconsult/consulted/make, directives.

load common

@test "nonexistent file exits nonzero" {
  run "$TRILOG" nonexistent_file.pl -e "true."
  [ "$status" -ne 0 ]
}

@test "file arg loads clauses and -e can query them" {
  run "$TRILOG" test/e2e/files/family.pl -e "grandparent(tom, W)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"W = ann"* ]]
}

@test "a consult-time directive can call a core.pl-defined predicate (regression)" {
  cat > /tmp/mi_directive_test.pl <<'PLEOF'
:- ( member(x, [x, y]) -> true ; throw(should_not_happen) ).
ok_marker(1).
PLEOF
  run "$TRILOG" /tmp/mi_directive_test.pl -e "
    ok_marker(X),
    write(X).
  "
  [ "$status" -eq 0 ]
  succeeded
  [[ "$output" == *"1"* ]]
  rm -f /tmp/mi_directive_test.pl
}

@test "a consult/1 directive loads the rest of the outer file too (regression)" {
  # regression: the nested consult clobbered the outer file's parse position, silently dropping everything after the directive.
  mkdir -p /tmp/mi_nest_test/sub
  printf "a(1).\n:- consult('sub/b.pl').\na(2).\n" > /tmp/mi_nest_test/a.pl
  printf "b(1).\n" > /tmp/mi_nest_test/sub/b.pl
  run "$TRILOG" /tmp/mi_nest_test/a.pl -e "
    findall(X, a(X), A),
    findall(Y, b(Y), B).
  "
  [[ "$output" == *"A = [1, 2]"* ]]
  [[ "$output" == *"B = [1]"* ]]
  rm -rf /tmp/mi_nest_test
}

@test "GC inside a nested consult's directives leaves the outer query intact (regression)" {
  # regression: a nested query reset the choicepoint stack and garbage-collected without the outer query's roots, so the outer one resumed on freed terms and called stray subterms.
  mkdir -p /tmp/mi_gcnest_test
  printf ":- consult('inner.pl').\nafter(1).\n" > /tmp/mi_gcnest_test/outer.pl
  printf ":- op(700, xfx, '==>').\n:- X = f(a).\ninner_fact(1).\n" > /tmp/mi_gcnest_test/inner.pl
  TRILOG_GC_THRESHOLD=2000 run "$TRILOG" -f /tmp/mi_gcnest_test/outer.pl -e "
    after(X),
    inner_fact(Y).
  "
  [[ "$output" != *"uncaught exception"* ]]
  [[ "$output" == *"X = 1"* ]]
  [[ "$output" == *"Y = 1"* ]]
  rm -rf /tmp/mi_gcnest_test
}

@test "a consult/1 directive resolves a relative path against the consulting file's directory" {
  mkdir -p /tmp/mi_rel_test/sub
  printf ":- consult('sub/b.pl').\n" > /tmp/mi_rel_test/a.pl
  printf "b(1).\n" > /tmp/mi_rel_test/sub/b.pl
  run "$TRILOG" /tmp/mi_rel_test/a.pl -e "b(X)."
  [[ "$output" == *"X = 1"* ]]
  rm -rf /tmp/mi_rel_test
}

@test "reconsulting a file replaces its clauses instead of appending" {
  printf ":- dynamic(p/1).\np(1).\np(2).\n" > "$BATS_TEST_TMPDIR/r.pl"
  run "$TRILOG" -f -e "
    consult('$BATS_TEST_TMPDIR/r.pl'),
    assertz(p(99)),
    consult('$BATS_TEST_TMPDIR/r.pl'),
    findall(X, p(X), L).
  "
  [[ "$output" == *"L = [99, 1, 2]"* ]]
}

@test "unconsult/1 removes only the file's clauses and fails when not loaded" {
  printf ":- dynamic(p/1).\np(1).\n" > "$BATS_TEST_TMPDIR/u.pl"
  run "$TRILOG" -f -e "
    consult('$BATS_TEST_TMPDIR/u.pl'),
    assertz(p(2)),
    unconsult('$BATS_TEST_TMPDIR/u.pl'),
    findall(X, p(X), L),
    ( unconsult('$BATS_TEST_TMPDIR/u.pl') -> A = loaded ; A = not_loaded ).
  "
  [[ "$output" == *"L = [2], A = not_loaded"* ]]
}

@test "consulted/1 lists loaded files, including ones from the command line" {
  printf "q(1).\n" > "$BATS_TEST_TMPDIR/from_command_line.pl"
  run "$TRILOG" -f "$BATS_TEST_TMPDIR/from_command_line.pl" -e "
    consulted(L),
    member(F, L),
    atom_concat(_, '/from_command_line.pl', F).
  "
  succeeded
  [ "$(answers)" -eq 1 ]
}

@test "make/0 reconsults files that changed since they were loaded" {
  printf "v(old).\n" > "$BATS_TEST_TMPDIR/m.pl"
  touch -t 202001010000 "$BATS_TEST_TMPDIR/m.pl"
  run "$TRILOG" -f "$BATS_TEST_TMPDIR/m.pl" -e "
    open('$BATS_TEST_TMPDIR/m.pl', write, S),
    write(S, 'v(new).'),
    nl(S),
    close(S),
    make,
    findall(X, v(X), L).
  "
  [[ "$output" == *"L = [new]"* ]]
}

@test "atom_to_term/3 in a directive leaves the rest of the file loading (regression)" {
  # regression: run-time parsing overwrote the consult's parse position.
  printf "a(1).\n:- atom_to_term('foo(X, Y)', _, _).\na(2).\na(3).\n" > "$BATS_TEST_TMPDIR/att.pl"
  run "$TRILOG" -f "$BATS_TEST_TMPDIR/att.pl" -e "findall(X, a(X), L)."
  [[ "$output" == *"L = [1, 2, 3]"* ]]
}

@test "positional file arg loads clauses and -e can query them" {
  run "$TRILOG" test/e2e/files/genealogy.pl -e "parent(tom,X), write(X)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"bob"* ]]
}

@test "positional file arg with nonexistent file exits nonzero" {
  run "$TRILOG" nonexistent_file.pl -e "true."
  [ "$status" -ne 0 ]
}

@test "consult and query in one expression" {
  run "$TRILOG" -e "consult('test/e2e/files/genealogy.pl'), parent(tom,bob)."
  [ "$status" -eq 0 ]
}

@test "directive in .pl file executes on consult" {
  printf ":- assert(from_directive(yes)).\n" > /tmp/trilog_dir_test.pl
  result=$(printf "consult('/tmp/trilog_dir_test.pl').\nfrom_directive(X), write(X).\n" \
    | "$TRILOG" 2>&1)
  [[ "$result" == *"yes"* ]]
  rm -f /tmp/trilog_dir_test.pl
}

@test "two consulted files both available" {
  printf "fruit(apple).\n" > /tmp/trilog_a.pl
  printf "veggie(carrot).\n" > /tmp/trilog_b.pl
  result=$(printf "consult('/tmp/trilog_a.pl').\nconsult('/tmp/trilog_b.pl').\nfruit(X), write(X), nl.\nveggie(Y), write(Y).\n" \
    | "$TRILOG" 2>&1)
  [[ "$result" == *"apple"* ]]
  [[ "$result" == *"carrot"* ]]
  rm -f /tmp/trilog_a.pl /tmp/trilog_b.pl
}

@test "unconsult/1 and consulted/1 accept any spelling of a loaded file's path" {
  dir="$BATS_TEST_TMPDIR/spell"
  mkdir -p "$dir/sub"
  printf 'v(1).\n' > "$dir/sub/f.pl"
  bin="$(cd "$(dirname "$TRILOG")" && pwd)/$(basename "$TRILOG")"
  cd "$dir"
  run "$bin" -f -e "
    consult('sub/f.pl'),
    consult('./sub/../sub/f.pl'),
    findall(X, v(X), L1),
    unconsult('sub/f.pl'),
    catch(v(_), error(E, _), true),
    write(r(L1, E)),
    nl.
  "
  [[ "$output" == *"r([1], existence_error(procedure, /(v, 1)))"* ]]
}
