#!/usr/bin/env bats

# Builtin and library predicates: arithmetic, type checks, text, lists, flags and their errors.

load common

@test "arithmetic via is/2" {
  run "$TRILOG" test/family.pl -e "double(21, R)."
  [[ "$output" == *"R = 42"* ]]
}

@test "raw byte I/O via put_code" {
  run "$TRILOG" -e "
    put_code(72),
    put_code(105).
  "
  [[ "$output" == *"Hi"* ]]
}

@test "flush_output/0 is callable" {
  run "$TRILOG" -e "
    write(x),
    flush_output,
    write(y),
    nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"xy"* ]]
}

@test "flush_output/0 does not touch the real stream during with_output_to/2 capture (regression)" {
  run "$TRILOG" -e "
    with_output_to(atom(A), (write(hi), flush_output, write(there))),
    writeq(A),
    nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"A = hithere"* ]]
}

@test "with_output_to/2 nests correctly, each level popping its own slice (regression)" {
  run "$TRILOG" -e "
    with_output_to(atom(A), (write(hi), with_output_to(atom(B), write(inner)), write(there))),
    write(A-B),
    nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"-(hithere, inner)"* ]]
}

@test "get_time_ms/1 returns a non-negative integer, monotonic across two calls" {
  run "$TRILOG" -e "
    get_time_ms(T0),
    (between(1,200000,_), fail; true),
    get_time_ms(T1),
    (T1 >= T0 -> write(ok) ; write(bad)),
    nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "type checks distinguish var/atom/number/compound" {
  run "$TRILOG" -e "
    var(X),
    nonvar(foo),
    atom(foo),
    \\+ atom(1),
    number(1),
    number(1.5),
    \\+ number(foo),
    integer(1),
    \\+ integer(1.5),
    compound(foo(1)),
    \\+ compound(foo),
    callable(foo),
    callable(foo(1)),
    \\+ callable(1).
  "
  [ "$status" -eq 0 ]
  succeeded
}

@test "extended arithmetic: mod, abs, min, max" {
  run "$TRILOG" -e "
    X is 7 mod 3,
    Y is -7 mod 3,
    Z is abs(-5),
    W is min(3,7),
    V is max(3,7).
  "
  [[ "$output" == *"X = 1"* ]]
  [[ "$output" == *"Y = 2"* ]]
  [[ "$output" == *"Z = 5"* ]]
  [[ "$output" == *"W = 3"* ]]
  [[ "$output" == *"V = 7"* ]]
}

@test "bitwise operators in is/2: /\\, \\/, xor, <<, >>, unary \\" {
  run "$TRILOG" -e '
    A is 6 /\ 3,
    B is 6 \/ 3,
    C is 6 xor 3,
    D is 1 << 4,
    E is 32 >> 2,
    F is \ 0.
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"A = 2"* ]]
  [[ "$output" == *"B = 7"* ]]
  [[ "$output" == *"C = 5"* ]]
  [[ "$output" == *"D = 16"* ]]
  [[ "$output" == *"E = 8"* ]]
  [[ "$output" == *"F = -1"* ]]
}

@test "min_int divided by -1 raises int_overflow instead of trapping (regression)" {
  # regression: INT64_MIN / -1 killed the process with SIGFPE.
  run "$TRILOG" -e "
    catch(_ is -9223372036854775808 // -1, error(E1, _), true),
    catch(_ is -9223372036854775808 / -1, error(E2, _), true),
    write(r(E1, E2)), nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"r(evaluation_error(int_overflow), evaluation_error(int_overflow))"* ]]
}

@test "mod takes the divisor's sign and never overflows (regression)" {
  # regression: min_int mod -1 trapped, and ((a % b) + b) % b overflowed near max_int.
  run "$TRILOG" -e "
    A is -9223372036854775808 mod -1,
    B is 9223372036854775806 mod 9223372036854775807,
    C is -7 mod 3, D is 7 mod -3, E is 6 mod 3,
    write(r(A, B, C, D, E)), nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"r(0, 9223372036854775806, 2, -2, 0)"* ]]
}

@test "negating min_int raises int_overflow (regression)" {
  # regression: -(min_int) and abs(min_int) silently returned min_int.
  run "$TRILOG" -e "
    catch(_ is -(-9223372036854775808), error(E1, _), true),
    catch(_ is abs(-9223372036854775808), error(E2, _), true),
    A is abs(-5), B is -(7),
    write(r(E1, E2, A, B)), nl.
  "
  [[ "$output" == *"r(evaluation_error(int_overflow), evaluation_error(int_overflow), 5, -7)"* ]]
}

@test "shifts are defined for every shift amount (regression)" {
  # regression: 1 << 64 gave 1 and 1 >> -1 gave 0 (C shift UB).
  run "$TRILOG" -e "
    A is 1 << 62, B is -1 << 3, C is 1 >> 64, D is -1 >> 70,
    E is 1 >> -2, F is -16 >> 2, G is 8 << -1,
    catch(_ is 1 << 63, error(E1, _), true),
    catch(_ is 1 << 64, error(E2, _), true),
    write(r(A, B, C, D, E, F, G, E1, E2)), nl.
  "
  [[ "$output" == *"r(4611686018427387904, -8, 0, -1, 4, -4, 4, evaluation_error(int_overflow), evaluation_error(int_overflow))"* ]]
}

@test "=.. raises the ISO errors instead of truncating or ignoring a bad tail (regression)" {
  # regression: more than 255 arguments were silently dropped, and [f, a | foo] built f(a).
  run "$TRILOG" -e "
    E = error(X, _),
    findall(X, ( member(L, [[foo|bar], 4, [], [3,1], [a(b),1], [f(a)]]), catch(_ =.. L, E, true) ), Xs),
    length(Args, 300), T =.. [f|Args], functor(T, _, A),
    write(Xs), nl, write(arity(A)), nl.
  "
  [[ "$output" == *"[type_error(list, [foo|bar]), type_error(list, 4), domain_error(non_empty_list, []), type_error(atom, 3), type_error(atom, a(b)), type_error(atomic, f(a))]"* ]]
  [[ "$output" == *"arity(300)"* ]]
}

@test "functor/3 raises the ISO errors instead of failing silently (regression)" {
  run "$TRILOG" -e "
    E = error(X, _),
    findall(X, ( member(N-A, [foo-a, 1.5-1, foo(a)-1, foo-(-1)]), catch(functor(_, N, A), E, true) ), Xs),
    write(Xs), nl.
  "
  [[ "$output" == *"[type_error(integer, a), type_error(atom, 1.5), type_error(atomic, foo(a)), domain_error(not_less_than_zero, -1)]"* ]]
}

@test "float arithmetic in is/2: mixed-mode promotion, //, float/1" {
  run "$TRILOG" -e "
    A is 1.5 + 2,
    B is 4/2,
    integer(B),
    C is 4/3,
    integer(C),
    D is min(1, 2.5),
    float(D),
    E is max(1.5, 2),
    float(E),
    F is abs(-1.5),
    G is floor(3.7),
    H is truncate(-3.7),
    I is float(3),
    float(I),
    J is 7 // 2,
    integer(J),
    K is 7.0 / 2.
  "
  [ "$status" -eq 0 ]
  succeeded
  [[ "$output" == *"A = 3.5"* ]]
  [[ "$output" == *"B = 2"* ]]
  [[ "$output" == *"C = 1"* ]]
  [[ "$output" == *"F = 1.5"* ]]
  [[ "$output" == *"G = 3"* ]]
  [[ "$output" == *"H = -3"* ]]
  [[ "$output" == *"J = 3"* ]]
  [[ "$output" == *"K = 3.5"* ]]
  [[ "$output" == *"D = 1.0"* ]]
  [[ "$output" == *"E = 2.0"* ]]
  [[ "$output" == *"I = 3.0"* ]]
}

@test "float arithmetic rejects int-only operators" {
  run "$TRILOG" -e "catch(X is 5 mod 2.0, E, true)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"type_error(integer, 2.0)"* ]]

  run "$TRILOG" -e "catch(X is 1/0.0, E, true)."
  [[ "$output" == *"evaluation_error(zero_divisor)"* ]]
}

@test "unevaluable arithmetic fails the goal instead of crashing the process (regression)" {
  # eval_arith used to exit(1) on anything unevaluable instead of just
  # failing the goal.
  run "$TRILOG" -e "X is Y."
  [ "$status" -eq 0 ]
  ! succeeded

  run "$TRILOG" -e "X < Y."
  [ "$status" -eq 0 ]
  ! succeeded

  run "$TRILOG" -e "X is foo(1,2)."
  [ "$status" -eq 0 ]
  ! succeeded

  # ordinary arithmetic is unaffected
  run "$TRILOG" -e "
    X is 1 + 2 * 3,
    Y is X mod 5.
  "
  [[ "$output" == *"X = 7"* ]]
  [[ "$output" == *"Y = 2"* ]]
}

@test "division by zero throws evaluation_error(zero_divisor), not a silent failure" {
  run "$TRILOG" -e "catch(X is 1/0, E, true)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"evaluation_error(zero_divisor)"* ]]
  run "$TRILOG" -e "catch(X is 5 mod 0, E, true)."
  [[ "$output" == *"evaluation_error(zero_divisor)"* ]]
}

@test "integer overflow throws evaluation_error(int_overflow), not silent wraparound" {
  run "$TRILOG" -e "catch((X is 2000000000 * 2000000000 * 3), E, true)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"evaluation_error(int_overflow)"* ]]
}

@test "functor/3 decomposes and constructs both ways" {
  run "$TRILOG" -e "
    functor(foo(a,b,c), N, A),
    functor(T, foo, 3).
  "
  [[ "$output" == *"N = foo"* ]]
  [[ "$output" == *"A = 3"* ]]
  [[ "$output" == *"T = foo("* ]]
}

@test "arg/3 extracts a 1-indexed argument" {
  run "$TRILOG" -e "arg(2, foo(a,b,c), X)."
  [[ "$output" == *"X = b"* ]]
}

@test "univ =.. decomposes and constructs both ways" {
  run "$TRILOG" -e "
    foo(a,b,c) =.. L,
    T =.. [foo,a,b,c].
  "
  [[ "$output" == *"L = [foo, a, b, c]"* ]]
  [[ "$output" == *"T = foo(a, b, c)"* ]]
}

@test "compare/3 gives standard order of terms" {
  run "$TRILOG" -e "
    compare(O1, 1, 2),
    compare(O2, foo, abc),
    compare(O3, foo(1), foo(1)).
  "
  [[ "$output" == *"O1 = <"* ]]
  [[ "$output" == *"O2 = >"* ]]
  [[ "$output" == *'O3 = ='* ]]
}

@test "atom_codes, char_code, and number_codes round-trip both ways" {
  run "$TRILOG" -e "
    atom_codes(hi, L1),
    atom_codes(A, [104,105]),
    char_code(a, C),
    char_code(Ch, 97),
    number_codes(42, L2),
    number_codes(N, [52,50]).
  "
  [[ "$output" == *"L1 = [104, 105]"* ]]
  [[ "$output" == *"A = hi"* ]]
  [[ "$output" == *"C = 97"* ]]
  [[ "$output" == *"Ch = a"* ]]
  [[ "$output" == *"L2 = [52, 50]"* ]]
  [[ "$output" == *"N = 42"* ]]
}

@test "read_line_to_atom/2 reads one line at a time, end_of_file at EOF" {
  path="$BATS_TEST_TMPDIR/read_line.txt"
  printf 'line one\nline two\n' > "$path"
  run "$TRILOG" -e "
    open('$path', read, S),
    read_line_to_atom(S, L1),
    read_line_to_atom(S, L2),
    read_line_to_atom(S, L3),
    close(S).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"L1 = 'line one'"* ]]
  [[ "$output" == *"L2 = 'line two'"* ]]
  [[ "$output" == *"L3 = end_of_file"* ]]
}

@test "term-order comparisons: ==, \\==, @<, @>, @=<, @>=, \\=" {
  run "$TRILOG" -e "
    1 == 1,
    1 \\== 2,
    1 @< 2,
    2 @> 1,
    1 @=< 1,
    1 @>= 1,
    \\+ (1 == 2),
    1 \\= 2,
    \\+ (1 \\= 1).
  "
  [ "$status" -eq 0 ]
  succeeded
}

@test "append, member, memberchk, reverse, length" {
  run "$TRILOG" -e "
    append([1,2],[3,4],L1),
    append(X,[3,4],[1,2,3,4]),
    member(2,[1,2,3]),
    \\+ member(5,[1,2,3]),
    memberchk(2,[1,2,2,3]),
    reverse([1,2,3],R),
    length([a,b,c],N),
    length(L2,3).
  "
  [[ "$output" == *"L1 = [1, 2, 3, 4]"* ]]
  [[ "$output" == *"X = [1, 2]"* ]]
  [[ "$output" == *"R = [3, 2, 1]"* ]]
  [[ "$output" == *"N = 3"* ]]
}

@test "nth0, nth1, last, is_list, sum_list, max_list, min_list, numlist" {
  run "$TRILOG" -e "
    nth0(1,[a,b,c],X1),
    nth1(1,[a,b,c],X2),
    last([1,2,3],X3),
    is_list([1,2,3]),
    \\+ is_list([1|foo]),
    sum_list([1,2,3,4],S),
    max_list([3,1,4,1,5],Mx),
    min_list([3,1,4,1,5],Mn),
    numlist(1,5,NL).
  "
  [[ "$output" == *"X1 = b"* ]]
  [[ "$output" == *"X2 = a"* ]]
  [[ "$output" == *"X3 = 3"* ]]
  [[ "$output" == *"S = 10"* ]]
  [[ "$output" == *"Mx = 5"* ]]
  [[ "$output" == *"Mn = 1"* ]]
  [[ "$output" == *"NL = [1, 2, 3, 4, 5]"* ]]
}

@test "select, delete, subtract, intersection, union, permutation" {
  run "$TRILOG" -e "
    select(2,[1,2,3],R1),
    delete([1,2,1,3,1],1,R2),
    subtract([1,2,3,4],[2,4],R3),
    intersection([1,2,3,4],[2,4,5],R4),
    union([1,2,3],[2,3,4],R5),
    findall(P,permutation([1,2],P),Ps).
  "
  [[ "$output" == *"R1 = [1, 3]"* ]]
  [[ "$output" == *"R2 = [2, 3]"* ]]
  [[ "$output" == *"R3 = [1, 3]"* ]]
  [[ "$output" == *"R4 = [2, 4]"* ]]
  [[ "$output" == *"R5 = [1, 2, 3, 4]"* ]]
  [[ "$output" == *"Ps = [[1, 2], [2, 1]]"* ]]
}

@test "flatten, list_to_set, max_member, min_member, repeat" {
  run "$TRILOG" -e "
    flatten([1,[2,[3,4],5],6],R1),
    list_to_set([1,2,1,3,2],R2),
    max_member(Mx,[3,1,4,1,5]),
    min_member(Mn,[3,1,4,1,5]),
    (repeat, X=done, !).
  "
  [[ "$output" == *"R1 = [1, 2, 3, 4, 5, 6]"* ]]
  [[ "$output" == *"R2 = [1, 2, 3]"* ]]
  [[ "$output" == *"Mx = 5"* ]]
  [[ "$output" == *"Mn = 1"* ]]
  [[ "$output" == *"X = done"* ]]
}

@test "atom_length, atom_concat (all 3 modes + nondet split), sub_atom, current_op" {
  run "$TRILOG" -e "
    atom_length(hello,L1),
    atom_concat(foo,bar,C1),
    atom_concat(foo,C2,foobar),
    atom_concat(C3,bar,foobar),
    findall(X-Y,atom_concat(X,Y,ab),Splits),
    length(Splits,NSplits),
    sub_atom(hello,1,3,_,Sub),
    op(750,xfx,foo_op),
    current_op(750,xfx,foo_op).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"L1 = 5"* ]]
  [[ "$output" == *"C1 = foobar"* ]]
  [[ "$output" == *"C2 = bar"* ]]
  [[ "$output" == *"C3 = foo"* ]]
  [[ "$output" == *"NSplits = 3"* ]]
  [[ "$output" == *"Sub = ell"* ]]
  succeeded
}

@test "atom_chars, atom_number, number_chars (both modes), writeln, retractall, abolish" {
  run "$TRILOG" -e "
    atom_chars(hi,Chars),
    atom_chars(A1,[h,i]),
    atom_number('42',N1),
    atom_number(A2,42),
    number_chars(42,NC),
    number_chars(N2,['4','2']),
    dynamic(tmp/1),
    assertz(tmp(1)),
    assertz(tmp(2)),
    retractall(tmp(_)),
    \\+ tmp(_),
    assertz(tmp2(1,2)),
    abolish(tmp2/2),
    catch(tmp2(_,_), error(existence_error(procedure,_),_), true).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"Chars = \"hi\""* ]]
  [[ "$output" == *"A1 = hi"* ]]
  [[ "$output" == *"N1 = 42"* ]]
  [[ "$output" == *"A2 = '42'"* ]]
  [[ "$output" == *'NC = "42"'* ]]
  [[ "$output" == *"N2 = 42"* ]]
  succeeded

  run "$TRILOG" -e "writeln(hi)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"hi"* ]]
}

@test "term_variables collects each distinct unbound var once, left to right" {
  run "$TRILOG" -e "
    term_variables(foo(X,Y,X,bar(Z)), Vs),
    length(Vs, N).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"N = 3"* ]]
}

@test "must_be throws type_error/domain_error/instantiation_error" {
  run "$TRILOG" -e "
    catch(must_be(integer, foo), E1, true),
    catch(must_be(not_less_than_zero, -1), E2, true),
    catch(must_be(var, foo), E3, true),
    catch(must_be(atom, X), E4, true).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"type_error(integer, foo)"* ]]
  [[ "$output" == *"domain_error(not_less_than_zero, -1)"* ]]
  [[ "$output" == *"uninstantiation_error(foo)"* ]]
  [[ "$output" == *"E4 = error(instantiation_error,"* ]]
}

@test "must_be passes valid terms silently, boolean/1 and character/1 delegate through call/2" {
  run "$TRILOG" -e "
    must_be(integer, 5),
    must_be(boolean, true),
    must_be(list, [1,2,3]),
    character(a),
    \\+ character(ab).
  "
  [ "$status" -eq 0 ]
  succeeded
}

@test "can_be passes an unbound Term without throwing, unlike must_be" {
  run "$TRILOG" -e "can_be(integer, X)."
  [ "$status" -eq 0 ]
  succeeded

  run "$TRILOG" -e "catch(can_be(integer, foo), E, true)."
  [[ "$output" == *"type_error(integer, foo)"* ]]
}

@test "between enumerates and checks, forall, succ, plus" {
  run "$TRILOG" -e "
    findall(X, between(1,5,X), L),
    between(1,5,3),
    \\+ between(1,5,9),
    forall(member(Y,[1,2,3]),Y>0),
    succ(3,S1),
    succ(S2,4),
    plus(2,3,P).
  "
  [[ "$output" == *"L = [1, 2, 3, 4, 5]"* ]]
  [[ "$output" == *"S1 = 4"* ]]
  [[ "$output" == *"S2 = 3"* ]]
  [[ "$output" == *"P = 5"* ]]
}

@test "call/2,3,4 dispatch through univ, including partial application" {
  run "$TRILOG" -e "
    call(=,1,1),
    call(is,X,1+2),
    maplist(plus(10),[1,2,3],L).
  "
  [[ "$output" == *"X = 3"* ]]
  [[ "$output" == *"L = [11, 12, 13]"* ]]
}

@test "maplist/2,3,4, foldl, include, exclude, partition" {
  run "$TRILOG" test/family.pl -e "
    maplist(integer,[1,2,3]),
    \\+ maplist(integer,[1,foo,3]),
    maplist(succ,[1,2,3],L1),
    foldl(plus,[1,2,3,4],0,S),
    include(integer,[1,foo,2,bar,3],L2),
    exclude(integer,[1,foo,2,bar,3],L3),
    partition(integer,[1,foo,2,bar,3],Inc,Exc).
  "
  [[ "$output" == *"L1 = [2, 3, 4]"* ]]
  [[ "$output" == *"S = 10"* ]]
  [[ "$output" == *"L2 = [1, 2, 3]"* ]]
  [[ "$output" == *"L3 = [foo, bar]"* ]]
  [[ "$output" == *"Inc = [1, 2, 3]"* ]]
  [[ "$output" == *"Exc = [foo, bar]"* ]]
}

@test "sort dedups and orders, msort keeps duplicates" {
  run "$TRILOG" -e "
    sort([3,1,4,1,5,9,2,6], L1),
    msort([3,1,4,1,5,9,2,6], L2).
  "
  [[ "$output" == *"L1 = [1, 2, 3, 4, 5, 6, 9]"* ]]
  [[ "$output" == *"L2 = [1, 1, 2, 3, 4, 5, 6, 9]"* ]]
}

@test "number_chars/2 on a cyclic list throws a catchable error instead of dying (regression)" {
  # regression: the heap grew until GC's scratch arrays failed to allocate, killing the process.
  run bash -c "ulimit -v 524288; timeout 60 $TRILOG -e \"L = ['1'|L], catch(number_chars(_, L), error(E, _), true), write(caught(E)), nl.\""
  [[ "$output" == *"caught(representation_error(cyclic_term))"* ]]
}

@test "text builtins and arg/3 raise ISO argument errors" {
  run "$TRILOG" -f -e "
    catch(atom_chars(f(a), _), error(E1, C1), true),
    catch(atom_chars(_, iso), error(E2, _), true),
    catch(atom_length(atom, '4'), error(E3, _), true),
    catch(sub_atom('Banana', a, 2, _, _), error(E4, _), true),
    catch(char_code(ab, _), error(E5, _), true),
    catch(atom_codes(_, [-1]), error(E6, _), true),
    catch(number_codes(_, [51, 120]), error(E7, _), true),
    catch(arg(a, f(x), _), error(E8, _), true),
    number_chars(1, ['0', '1']).
  "
  [[ "$output" == *"E1 = type_error(atom, f(a)), C1 = /(atom_chars, 2)"* ]]
  [[ "$output" == *"E2 = type_error(list, iso)"* ]]
  [[ "$output" == *"E3 = type_error(integer, '4')"* ]]
  [[ "$output" == *"E4 = type_error(integer, a)"* ]]
  [[ "$output" == *"E5 = type_error(character, ab)"* ]]
  [[ "$output" == *"E6 = representation_error(character_code)"* ]]
  [[ "$output" == *"E7 = syntax_error(illegal_number)"* ]]
  [[ "$output" == *"E8 = type_error(integer, a)"* ]]
}

@test "is_list/1 fails on an open or cyclic list without binding it (regression)" {
  # regression: is_list([a|T]) bound T = [] and succeeded.
  run "$TRILOG" -f -e "
    ( is_list([a|T]) -> R1 = yes ; R1 = no ),
    ( X = [a|X], is_list(X) -> R2 = yes ; R2 = no ),
    ( is_list([a, b]) -> R3 = yes ; R3 = no ),
    ( var(T) -> R4 = unbound ; R4 = bound ),
    write(r(R1, R2, R3, R4)),
    nl.
  "
  [[ "$output" == *"r(no, no, yes, unbound)"* ]]
}

@test "length/2 raises ISO errors for a bad length (regression)" {
  # regression: length(L, -1) failed and length(L, a) raised type_error(evaluable, a/0).
  run "$TRILOG" -f -e "
    catch(length(_, -1), error(E1, C1), true),
    catch(length(_, a), error(E2, C2), true),
    write(r(E1, C1, E2, C2)),
    nl.
  "
  [[ "$output" == *"r(domain_error(not_less_than_zero, -1), /(length, 2), type_error(integer, a), /(length, 2))"* ]]
}

@test "length/2 fills, measures and enumerates partial lists, fails on improper ones" {
  run "$TRILOG" -f -e "
    length([a, b|T], 4),
    length(T, NT),
    findall(N, (length([x|_], N), (N >= 3 -> ! ; true)), Ns),
    ( length([a|b], _) -> R1 = yes ; R1 = no ),
    ( X = [a|X], length(X, _) -> R2 = yes ; R2 = no ),
    write(r(NT, Ns, R1, R2)),
    nl.
  "
  [[ "$output" == *"r(2, [1, 2, 3], no, no)"* ]]
}

@test "keysort/2 is stable and checks its arguments" {
  run "$TRILOG" -f -e "
    keysort([b-1, a-2, b-0, a-1, a-0], S),
    catch(keysort([a-1, x], _), error(E1, _), true),
    catch(keysort([a-1|_], _), error(E2, _), true),
    catch(keysort(foo, _), error(E3, C3), true),
    catch(keysort([a-1], foo), error(E4, _), true),
    write(r(S, E1, E2, E3, C3, E4)),
    nl.
  "
  [[ "$output" == *"r([-(a, 2), -(a, 1), -(a, 0), -(b, 1), -(b, 0)], type_error(pair, x), instantiation_error, type_error(list, foo), /(keysort, 2), type_error(list, foo))"* ]]
}

@test "subsumes_term/2 is one-way and does not bind" {
  run "$TRILOG" -f -e "
    ( subsumes_term(f(_, b), f(a, b)) -> R1 = yes ; R1 = no ),
    ( subsumes_term(f(a, b), f(_, b)) -> R2 = yes ; R2 = no ),
    ( subsumes_term(f(X, X), f(_, _)) -> R3 = yes ; R3 = no ),
    ( subsumes_term(f(_, _), f(Y, Y)) -> R4 = yes ; R4 = no ),
    ( subsumes_term(Z, f(Z)) -> R5 = yes ; R5 = no ),
    G = g(A),
    subsumes_term(G, g(1)),
    ( var(A) -> R6 = unbound ; R6 = bound ),
    write(r(R1, R2, R3, R4, R5, R6)),
    nl.
  "
  [[ "$output" == *"r(yes, no, no, yes, no, unbound)"* ]]
}

@test "rem, **, ^, sqrt, log, exp, trig, pi and float parts evaluate per ISO" {
  run "$TRILOG" -f -e "
    A is -7 rem 2,
    B is 2 ** 3,
    C is 2 ^ 10,
    D is sqrt(16),
    E is float_fractional_part(-2.5),
    catch(_ is 2 ^ -1, error(E1, _), true),
    catch(_ is sqrt(-1), error(E2, _), true),
    catch(_ is 2 ^ 63, error(E3, _), true),
    catch(_ is exp(1000), error(E4, _), true),
    ( pi > 3.14159, pi < 3.1416, atan(1) * 4 =:= pi -> P = ok ; P = bad ),
    write(r(A, B, C, D, E, E1, E2, E3, E4, P)),
    nl.
  "
  [[ "$output" == *"r(-1, 8.0, 1024, 4.0, -0.5, type_error(float, 2), evaluation_error(undefined), evaluation_error(int_overflow), evaluation_error(float_overflow), ok)"* ]]
}

@test "atoms with the same text are the same atom, across many atoms" {
  run "$TRILOG" -f -e "
    findall(A, (between(1, 5000, I), number_codes(I, Cs), atom_codes(A, [0'a|Cs])), As),
    findall(B, (between(1, 5000, I), number_codes(I, Cs), atom_codes(B, [0'a|Cs])), Bs),
    ( As == Bs -> R1 = same ; R1 = different ),
    sort(As, S),
    length(S, N),
    atom_chars(X, \"a4999\"),
    ( X == a4999 -> R2 = same ; R2 = different ),
    ( 'it''s' == 'it\\'s', '' == '', [] == '[]' -> R3 = same ; R3 = different ),
    ( a1 \\== a2, 'A' \\== a -> R4 = distinct ; R4 = merged ),
    write(r(R1, N, R2, R3, R4)),
    nl.
  "
  [[ "$output" == *"r(same, 5000, same, same, distinct)"* ]]
}

@test "string in arithmetic context gives type error" {
  run "$TRILOG" -e "X is \"hello\"."
  [[ "$output" == *"type_error"* ]]
}

@test "open/write/close creates file with content" {
  rm -f /tmp/trilog_fio_test.txt
  printf "open('/tmp/trilog_fio_test.txt', write, S), write(S, hello_world), close(S).\n" \
    | "$TRILOG" >/dev/null 2>&1
  [ -f /tmp/trilog_fio_test.txt ]
  [[ "$(cat /tmp/trilog_fio_test.txt)" == *"hello_world"* ]]
  rm -f /tmp/trilog_fio_test.txt
}

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

@test "between generates integer range" {
  result=$(printf "findall(X, between(1,5,X), L), write(L).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"[1, 2, 3, 4, 5]"* ]]
}

@test "with_output_to captures write into atom" {
  result=$(printf "with_output_to(atom(X), write(hello)), write(X).\n" | "$TRILOG" 2>&1)
  [[ "$result" == *"hello"* ]]
}
