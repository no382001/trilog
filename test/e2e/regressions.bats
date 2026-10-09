#!/usr/bin/env bats

# Tests per GitHub issue

load common

@test "answers are printed quoted, so atoms read back as atoms (#14, #16)" {
  run "$TRILOG" -f -e "
    \"1\" = [Ch],
    X = '1',
    Y = 'hello world',
    Z = abc.
  "
  [[ "$output" == *"Ch = '1', X = '1', Y = 'hello world', Z = abc"* ]]
}

@test "current_prolog_flag/2 enumerates every ISO flag, unknown included (#13)" {
  run "$TRILOG" -f -e "
    current_prolog_flag(unknown, U),
    current_prolog_flag(char_conversion, C),
    current_prolog_flag(debug, D),
    findall(F, current_prolog_flag(F, _), Fs),
    length(Fs, N).
  "
  [[ "$output" == *"U = error, C = off, D = off"* ]]
  [[ "$output" == *"N = 9"* ]]
  run "$TRILOG" -f -e "catch(current_prolog_flag(1, _), error(E, _), true)."
  [[ "$output" == *"E = type_error(atom, 1)"* ]]
}

@test "key a prints all answers; stopping early prints ; ... . (#28)" {
  command -v script >/dev/null || skip "no script(1)"
  repl() { { echo 'member(X, [1,2,3]).'; sleep 0.3; printf '%s' "$1"; sleep 0.3; printf '\004'; } \
    | timeout 5 script -qc "$TRILOG -f" /dev/null 2>&1 | tr -d '\r'; }
  run repl a
  [[ "$output" == *"X = 1"$'\n'";  X = 2"$'\n'";  X = 3."* ]]
  run repl x
  [[ "$output" == *"X = 1"$'\n'";  ... ."* ]]
}

@test "errors name the predicate that raised them in their context (#4)" {
  run "$TRILOG" -f -e "
    catch(X is Y, error(_, C1), true),
    catch(functor(_, _, _), error(_, C2), true),
    catch(sort(a, _), error(_, C3), true),
    catch(assertz(_), error(_, C4), true),
    catch(compare(foo, a, b), error(_, C5), true).
  "
  [[ "$output" == *"C1 = /(is, 2)"* ]]
  [[ "$output" == *"C2 = /(functor, 3)"* ]]
  [[ "$output" == *"C3 = /(sort, 2)"* ]]
  [[ "$output" == *"C4 = /(assertz, 1)"* ]]
  [[ "$output" == *"C5 = /(compare, 3)"* ]]
}

@test "read_from_chars/2, read_term_from_chars/3, write_term_to_chars/3 exist (#20)" {
  run "$TRILOG" -f -e "
    write_term_to_chars(f('A b', [x|y]), [quoted(true)], Cs),
    read_term_from_chars(Cs, T, []),
    read_from_chars(\"g(X, Y, X)\", G),
    read_term_from_chars(\"h(X, _)\", _, [variable_names(Ns), variables(Vs)]),
    length(Vs, NV),
    catch(read_from_chars(\"g(\", _), error(E, C), true).
  "
  [[ "$output" == *"Cs = \"f('A b', [x|y])\""* ]]
  [[ "$output" == *"T = f('A b', [x|y])"* ]]
  [[ "$output" == *"G = g(_G"* ]]
  [[ "$output" == *"Ns = [=('X', _G"* ]]
  [[ "$output" == *"NV = 2"* ]]
  [[ "$output" == *"E = syntax_error("* ]]
  [[ "$output" == *"C = /(read_from_chars, 2)"* ]]
}

@test "compound arity is unbounded: functor/3, arg/3, =../2, the parser and abolish/1 (#26)" {
  run "$TRILOG" -f -e "
    functor(T, f, 5000),
    arg(5000, T, z),
    T =.. [_|As],
    length(As, N1),
    length(L, 20000),
    T2 =.. [g|L],
    functor(T2, _, N2),
    functor(T3, h, 1000),
    T3 =.. [h|As3],
    maplist(=(a), As3),
    term_to_atom(T3, At),
    atom_to_term(At, T4, _),
    ( T4 == T3 -> R1 = same ; R1 = different ),
    current_prolog_flag(max_arity, M),
    catch(functor(_, f, 1000000000), error(E, _), true),
    abolish(foo/1000),
    write(r(N1, N2, R1, M, E)),
    nl.
  "
  [[ "$output" == *"r(5000, 20000, same, unbounded, resource_error(memory))"* ]]
}

@test "the interactive toplevel prompts with ?- (#3)" {
  command -v script >/dev/null || skip "no script(1)"
  run bash -c "{ echo 'X = 1.'; sleep 0.3; printf '\004'; } | timeout 5 script -qc '$TRILOG -f' /dev/null 2>&1 | tr -d '\r'"
  [[ "$output" == *"?- "* ]]
  [[ "$output" == *"X = 1."* ]]
}

@test "answers end with . and each further answer starts with ;, false. is indented (#8)" {
  run "$TRILOG" -f -e "member(X, [a, b, c])."
  [[ "$output" == *"   X = a"$'\n'";  X = b"$'\n'";  X = c."* ]]
  run "$TRILOG" -f -e "fail."
  [ "$output" = "   false." ]
}

@test "double-quoted text is a list of chars (#11)" {
  run "$TRILOG" -f -e "
    Xs = \"abc\",
    ( Xs == [a, b, c] -> R1 = chars ; R1 = not_chars ),
    [C|Cs] = \"hello\",
    writeq(r(R1, C, Cs)),
    nl.
  "
  [[ "$output" == *"r(chars, h, \"ello\")"* ]]
}

@test "writeq('\\n') prints the escape, not a raw newline (#12)" {
  run "$TRILOG" -f -e "writeq('\\n'), nl, writeq(f('a\\nb')), nl."
  [ "${lines[0]}" = "'\\n'" ]
  [ "${lines[1]}" = "f('a\\nb')" ]
}

@test "false/0 exists and fails without an error (#19)" {
  run "$TRILOG" -f -e "( false -> R = succeeded ; R = failed ), write(R), nl."
  [[ "$output" == *"failed"* ]]
  [[ "$output" != *"existence_error"* ]]
}

@test "integer flags are integers, not atoms (#23)" {
  run "$TRILOG" -f -e "
    current_prolog_flag(max_integer, Max),
    current_prolog_flag(min_integer, Min),
    ( integer(Max), integer(Min), Max > 0, Min < 0 -> R = integers ; R = not_integers ),
    current_prolog_flag(max_arity, A),
    write(r(R, A)),
    nl.
  "
  [[ "$output" == *"r(integers, unbounded)"* ]]
}
