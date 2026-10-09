#!/usr/bin/env bats

# Size and depth: deep terms, long lists, many goals or variables, memory exhaustion.

load common

@test "startup under a tiny memory cap reports out of memory instead of crashing (regression)" {
  # regression: the arena's malloc was unchecked, so a failed allocation segfaulted.
  for kb in 3500 3750 4000 4250 4500 4750 5000 5500 6000; do
    run bash -c "ulimit -v $kb; $TRILOG -e 'true.'"
    [ "$status" -ne 139 ]
  done
}

@test "a 300000-element list survives unify, compare, copy, findall and assert (regression)" {
  # regression: each of these recursed in C once per list cell and overflowed the C stack.
  run "$TRILOG" -e "
    numlist(1, 300000, L), numlist(1, 300000, M),
    L = M, L == M, compare(O, L, M), unify_with_occurs_check(L, M),
    copy_term(L, C), length(C, N1),
    findall(L, true, [F]), length(F, N2),
    assertz(big(L)), big(B), length(B, N3),
    length(V, 300000), copy_term(V, W), V = W,
    write(r(O, N1, N2, N3)), nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"r(=, 300000, 300000, 300000)"* ]]
}

@test "copy_term/2 keeps more than 64 variables distinct (regression)" {
  # regression: a fixed 64-slot table aliased every variable past the 63rd.
  run "$TRILOG" -e "
    length(L, 100), T =.. [f|L], copy_term(T, C), C =.. [_|Vs],
    nth0(70, Vs, A), last(Vs, Z),
    ( A == Z -> write(aliased) ; write(distinct) ), nl.
  "
  [[ "$output" == *"distinct"* ]]
}

@test "findall/3 keeps more than 64 variables distinct (regression)" {
  run "$TRILOG" -e "
    length(L, 5000), findall(L, true, [M]), sort(M, S), length(S, K),
    write(distinct(K)), nl.
  "
  [[ "$output" == *"distinct(5000)"* ]]
}

@test "a term nested 100000 deep in its first argument works under a 512 KB C stack (regression)" {
  # regression: unify, compare, copy, assert, print and parse recursed in C once per level.
  run bash -c "ulimit -s 512; $TRILOG -e \"
    assertz(nest(_, A, g(A, x))),
    numlist(1, 100000, Ns),
    foldl(nest, Ns, x, T),
    foldl(nest, Ns, x, T2),
    T = T2,
    T == T2,
    copy_term(T, C),
    assertz(deep(C)),
    deep(D),
    D == T,
    term_to_atom(T, At),
    atom_to_term(At, T3, _),
    T3 == T,
    write(deep_ok),
    nl.
  \""
  [ "$status" -eq 0 ]
  [[ "$output" == *"deep_ok"* ]]
}

@test "clauses, directives and queries with many goals and variables run correctly" {
  # A 200-goal clause, a 200-goal directive, a fact sharing 400 variables, and a 200-goal query.
  python3 -c "
goals = ', '.join('X%d = %d' % (i, i) for i in range(200))
print('t(S) :- ' + goals + ', S is X0 + X199.')
print(':- ' + ', '.join(['true'] * 200) + ', assertz(dir_ran).')
args = ', '.join('V%d' % i for i in range(400))
print('wide(f(' + args + '), g(' + ', '.join('V%d' % i for i in reversed(range(400))) + ')).')
" > "$BATS_TEST_TMPDIR/many.pl"
  query="$(python3 -c "print(', '.join(['true'] * 200) + ', write(query_ran), nl')")"
  run "$TRILOG" -f "$BATS_TEST_TMPDIR/many.pl" -e "
    t(S),
    dir_ran,
    wide(F, G),
    F =.. [_|Fs],
    G =.. [_|Gs],
    reverse(Gs, Rs),
    term_variables(F, Vs),
    length(Vs, NV),
    ( Fs == Rs -> Shared = shared ; Shared = not_shared ),
    write(r(S, NV, Shared)),
    nl.
  "
  [[ "$output" == *"r(199, 400, shared)"* ]]
  run "$TRILOG" -f -e "$query."
  [[ "$output" == *"query_ran"* ]]
}

@test "no limit on body goals or variables per clause, directive or query" {
  # regression: more than 255 body goals or 512 variables was a parse error.
  python3 -c "
goals = ', '.join('X%d = %d' % (i, i) for i in range(1000))
print('t(S) :- ' + goals + ', S is X0 + X999.')
print(':- ' + ', '.join(['true'] * 1000) + ', assertz(dir_ran).')
" > "$BATS_TEST_TMPDIR/huge.pl"
  query="$(python3 -c "print(', '.join('Q%d = %d' % (i, i) for i in range(1000)) + ', S is Q0 + Q999, write(s(S)), nl')")"
  run "$TRILOG" -f "$BATS_TEST_TMPDIR/huge.pl" -e "
    t(S),
    dir_ran,
    write(r(S)),
    nl.
  "
  [[ "$output" == *"r(999)"* ]]
  run "$TRILOG" -f -e "$query."
  [[ "$output" == *"s(999)"* ]]
}

@test "deeply nested term doesn't crash" {
  run "$TRILOG" -e "X = f(f(f(f(f(f(f(f(f(f(a)))))))))), write(ok)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}
