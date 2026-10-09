#!/usr/bin/env bats

# Reading and writing terms: operators, writeq, write_canonical, numbervars, quoting.

load common

@test "an integer literal too large for 64 bits is a syntax error, not clamped (regression)" {
  # regression: strtoll silently clamped 99999999999999999999 to max_int.
  run "$TRILOG" -e "X = 99999999999999999999."
  [[ "$output" == *"parse error"* ]]
  [[ "$output" != *"9223372036854775807"* ]]
  run "$TRILOG" -e "
    catch(atom_number('99999999999999999999', _), error(E1, _), true),
    catch(atom_number('-99999999999999999999', _), error(E2, _), true),
    write(r(E1, E2)), nl.
  "
  [[ "$output" == *"r(representation_error(max_integer), representation_error(min_integer))"* ]]
}

@test "input ending inside 0' or a quoted escape stops at the end (regression)" {
  # regression: the parser stepped over the terminating NUL and read on into the environment.
  for q in "X = 0'" "X = 0'\\" "X = 'ab\\" 'X = "ab\'; do
    run env -i TRILOG_LEAK_CANARY=leaked "$TRILOG" -e "$q"
    [[ "$output" == *"parse error"* ]]
    [[ "$output" != *"TRILOG_LEAK_CANARY"* ]]
  done
}

@test "input ending in a symbol-char token stops at the end (regression)" {
  for q in "X = (:-" "X = f(:- ." "X = f(+"; do
    run env -i TRILOG_LEAK_CANARY=leaked "$TRILOG" -e "$q"
    [[ "$output" == *"parse error"* ]]
    [[ "$output" != *"TRILOG_LEAK_CANARY"* ]]
  done
}

@test "atom_to_term/3 populates NameVars, sharing repeated vars, skipping bare _" {
  run "$TRILOG" -e "
    atom_to_term('foo(X,Y,X,_)', T, NV),
    write(T-NV),
    nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"foo(_G"* ]]
  [[ "$output" == *"=(X, _G"* ]]
  [[ "$output" == *"=(Y, _G"* ]]
}

@test "0'c character-code literals, including escapes and the doubled quote" {
  run "$TRILOG" -e "
    A is 0'a,
    B is 0'\\ ,
    C is 0'\\n,
    D is 0'\\t,
    E is 0'\\\\,
    F is 0'''.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"A = 97"* ]]
  [[ "$output" == *"B = 32"* ]]
  [[ "$output" == *"C = 10"* ]]
  [[ "$output" == *"D = 9"* ]]
  [[ "$output" == *"E = 92"* ]]
  [[ "$output" == *"F = 39"* ]]
}

@test "Op(Args) compound-term syntax works even when Op is also an operator" {
  run "$TRILOG" -e "
    X = -(1,2),
    Y = ==(a,b),
    Z is -(5).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"X = -(1, 2)"* ]]
  [[ "$output" == *"Y = ==(a, b)"* ]]
  [[ "$output" == *"Z = -5"* ]]

  run "$TRILOG" -e "
    X = 3,
    Y is -X.
  "
  [[ "$output" == *"Y = -3"* ]]
}

@test "a bare operator atom parses as a plain atom in argument position" {
  run "$TRILOG" -e "
    X = \\+,
    Y = -,
    Z = [\\+, -, +].
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"X = \\+"* ]]
  [[ "$output" == *"Y = -"* ]]
  [[ "$output" == *"Z = [\\+, -, +]"* ]]
}

@test "printing a tail-cyclic list terminates (regression)" {
  # regression: the list printer walked the spine with no limit, looping forever on L = [a|L].
  run timeout 10 "$TRILOG" -e "
    L = [a|L],
    write(done),
    nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"done"* ]]
  [[ "$output" == *"|...]"* ]]
}

@test "op/3 defines a custom infix operator, most recently asserted priority wins" {
  cat > /tmp/mi_op_test.pl <<'PLEOF'
:- op(700, xfx, ===>).
rewrite(a ===> b).
PLEOF
  run "$TRILOG" /tmp/mi_op_test.pl -e "
    rewrite(X),
    X = (A ===> B),
    write(A),
    write(B).
  "
  [ "$status" -eq 0 ]
  succeeded
  [[ "$output" == *"ab"* ]]

  cat > /tmp/mi_op_test2.pl <<'PLEOF'
:- op(700, xfx, ===>).
:- op(600, xfx, ===>).
lower_prec(X) :- X = (a ===> b ===> c).
PLEOF
  run "$TRILOG" /tmp/mi_op_test2.pl -e "
    lower_prec(X),
    write(X).
  "
  [ "$status" -eq 0 ]
  succeeded
  [[ "$output" == *"===>(===>(a, b), c)"* ]]
  rm -f /tmp/mi_op_test.pl /tmp/mi_op_test2.pl
}

@test "numbervars/3 and write_term numbervars(true) print '\$VAR'(N) as a variable name" {
  run "$TRILOG" -f -e "
    T = f(X, Y, X, Z),
    numbervars(T, 0, End),
    writeq(T),
    nl,
    write_term(T, [quoted(true), numbervars(false)]),
    nl.
  "
  [[ "$output" == *"f(A, B, A, C)"* ]]
  [[ "$output" == *"f('\$VAR'(0), '\$VAR'(1), '\$VAR'(0), '\$VAR'(2))"* ]]
  [[ "$output" == *"End = 3"* ]]
}

@test "printing a cyclic term stops at the cycle (regression)" {
  # regression: without the old 4 KB text cap, term_to_atom/2 of a cyclic term grew without bound.
  run timeout 10 "$TRILOG" -e "
    X = f(X, Y),
    Y = [a|Y],
    term_to_atom(X, A),
    write(A),
    nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"f(..., [a|...])"* ]]
}

@test "write_canonical/1,2 quote atoms and ignore operators" {
  run "$TRILOG" -f -e "
    write_canonical(f('B c', 1+2, -(3), [1])),
    nl,
    write_canonical(user_output, 'it''s' = a),
    nl.
  "
  [[ "$output" == *"f('B c', +(1, 2), -(3), [1])"* ]]
  [[ "$output" == *"=('it\\'s', a)"* ]]
}

@test "write_canonical/1 output reads back as the same term" {
  run "$TRILOG" -f -e "
    Ts = [[a, b], [a|b], '[]', {a, b}, '{}'(x), f(:-, (a :- b)), - 1, -(-(1)), 1 - -1,
          1.5, -0.0, 'hello world', 'it''s', '\\n', 'B', f(A, B, A), '\$VAR'(1),
          f(;, '|', ','), \\+ a, a = \\+, [-]],
    findall(T,
            ( member(T, Ts),
              with_output_to(chars(Cs), write_canonical(T)),
              read_term_from_chars(Cs, T2, []),
              \\+ ( subsumes_term(T, T2), subsumes_term(T2, T) )
            ),
            Bad),
    length(Ts, N),
    write(r(N, Bad)),
    nl.
  "
  [[ "$output" == *"r(21, [])"* ]]
}

@test "curly terms print in curly notation" {
  run "$TRILOG" -f -e "
    writeq(f({x}, '{}'(y), {})),
    nl,
    write_canonical({a, b}),
    nl.
  "
  [[ "$output" == *"f({x}, {y}, {})"* ]]
  [[ "$output" == *"{','(a, b)}"* ]]
}

@test "op/3 raises ISO permission errors for ',', '|' and infix/postfix clashes" {
  run "$TRILOG" -f -e "
    catch(op(1000, xfy, ','), error(E1, _), true),
    catch(op(0, xfy, ','), error(E2, _), true),
    catch(op(999, xfy, '|'), error(E3, _), true),
    catch(op(699, xf, >), error(E4, _), true),
    catch(op(700, _, foo), error(E5, _), true),
    op(1100, xfy, '|'),
    writeq(r(E1, E2, E3, E4, E5)),
    nl.
  "
  [[ "$output" == *"r(permission_error(modify, operator, ','), permission_error(modify, operator, ','), permission_error(create, operator, '|'), permission_error(create, operator, >), instantiation_error)"* ]]
}

@test "current_op/3 lists the standard operator table" {
  run "$TRILOG" -f -e "
    findall(op(P, T, N), current_op(P, T, N), L),
    msort(L, S),
    writeq(S),
    nl.
  "
  [[ "$output" == *"[op(200, fy, +), op(200, fy, -), op(200, fy, \\), op(200, xfx, **), op(200, xfy, ^), op(400, yfx, *), op(400, yfx, /), op(400, yfx, //), op(400, yfx, /\\), op(400, yfx, <<), op(400, yfx, >>), op(400, yfx, mod), op(400, yfx, rem), op(400, yfx, xor), op(500, yfx, +), op(500, yfx, -), op(500, yfx, \\/), op(700, xfx, <), op(700, xfx, =), op(700, xfx, =..), op(700, xfx, =:=), op(700, xfx, =<), op(700, xfx, ==), op(700, xfx, =\\=), op(700, xfx, >), op(700, xfx, >=), op(700, xfx, @<), op(700, xfx, @=<), op(700, xfx, @>), op(700, xfx, @>=), op(700, xfx, \\=), op(700, xfx, \\==), op(700, xfx, is), op(900, fy, \\+), op(1000, xfy, ','), op(1050, xfy, ->), op(1100, xfy, ;), op(1200, fx, :-), op(1200, fx, ?-), op(1200, xfx, -->), op(1200, xfx, :-)]"* ]]
}

@test "standard operators parse with their priority and associativity" {
  printf '%s\n' \
    't((a :- b, c ; d -> e)).' \
    't(1 - 2 - 3).' \
    't(2 ^ 3 ^ 4).' \
    't(1 + 2 * 3).' \
    't(- - a).' \
    't(\+ a = b).' \
    't(a rem b mod c).' \
    't(2 ** 3).' \
    't((a --> b, c)).' \
    't(x is 1 + 2).' \
    't(a = b).' > "$BATS_TEST_TMPDIR/ops.pl"
  run "$TRILOG" -f "$BATS_TEST_TMPDIR/ops.pl" -e "
    forall(t(X), (write_canonical(X), nl)).
  "
  [ "${lines[0]}" = ":-(a, ;(','(b, c), ->(d, e)))" ]
  [ "${lines[1]}" = "-(-(1, 2), 3)" ]
  [ "${lines[2]}" = "^(2, ^(3, 4))" ]
  [ "${lines[3]}" = "+(1, *(2, 3))" ]
  [ "${lines[4]}" = "-(-(a))" ]
  [ "${lines[5]}" = "\\+(=(a, b))" ]
  [ "${lines[6]}" = "mod(rem(a, b), c)" ]
  [ "${lines[7]}" = "**(2, 3)" ]
  [ "${lines[8]}" = "-->(a, ','(b, c))" ]
  [ "${lines[9]}" = "is(x, +(1, 2))" ]
  [ "${lines[10]}" = "=(a, b)" ]
}

@test "operators declared with op/3 in a file parse the rest of that file" {
  printf '%s\n' \
    ':- op(700, xfx, ===).' \
    ':- op(200, xfy, [&&, ++]).' \
    't(a === b).' \
    't(a && b && c).' \
    't(x ++ y).' > "$BATS_TEST_TMPDIR/userops.pl"
  run "$TRILOG" -f "$BATS_TEST_TMPDIR/userops.pl" -e "
    forall(t(X), (write_canonical(X), nl)).
  "
  [ "${lines[0]}" = "===(a, b)" ]
  [ "${lines[1]}" = "&&(a, &&(b, c))" ]
  [ "${lines[2]}" = "++(x, y)" ]
}

@test "op/3 can redefine and remove a standard operator (regression)" {
  # regression: the parser checked a hardcoded copy of the standard table before '$$op'/3.
  printf '%s\n' \
    ':- op(300, xfx, +).' \
    't(1 * 2 + 3).' \
    ':- op(0, xfx, ==).' \
    ':- catch(atom_to_term('"'"'x == y'"'"', _, _), error(syntax_error(_), _), assertz(removed)).' > "$BATS_TEST_TMPDIR/redef.pl"
  run "$TRILOG" -f "$BATS_TEST_TMPDIR/redef.pl" -e "
    t(X),
    write_canonical(X),
    nl,
    ( removed -> write(removed) ; write(still_an_operator) ),
    nl.
  "
  [ "${lines[0]}" = "*(1, +(2, 3))" ]
  [ "${lines[1]}" = "removed" ]
}

@test "string unification" {
  run "$TRILOG" -e "X = \"hello\", X = [h,e,l,l,o], write(ok)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "long atom name doesn't crash" {
  run "$TRILOG" -e "X = abcdefghijklmnopqrstuvwxyz_abcdefghijklmnopqrstuvwxyz, write(ok)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "term_to_atom and atom_to_term roundtrip" {
  result=$(printf "term_to_atom(foo(1,bar), A), atom_to_term(A, T, _), write(T).\n" \
    | "$TRILOG" 2>&1)
  [[ "$result" == *"foo(1, bar)"* ]]
}
