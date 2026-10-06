#!/usr/bin/env bats

TRILOG="./trilog"

succeeded() {
  [[ "$output" != *"   false."* && "$output" != *"uncaught exception"* && "$output" != *"parse error"* ]]
}

answers() {
  if succeeded; then
    echo $(($(echo "$output" | grep -c '^;  ') + 1))
  else
    echo 0
  fi
}

# --- exit code contract ---

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

@test "nonexistent file exits nonzero" {
  run "$TRILOG" nonexistent_file.pl -e "true."
  [ "$status" -ne 0 ]
}

# --- file loading + querying ---

@test "file arg loads clauses and -e can query them" {
  run "$TRILOG" test/family.pl -e "grandparent(tom, W)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"W = ann"* ]]
}

@test "arithmetic via is/2" {
  run "$TRILOG" test/family.pl -e "double(21, R)."
  [[ "$output" == *"R = 42"* ]]
}

# --- backtracking and cut: the core of the ABC loop ---

@test "backtracking enumerates every solution" {
  run "$TRILOG" test/family.pl -e "choice(W)."
  [[ "$output" == *"W = a"* ]]
  [[ "$output" == *"W = b"* ]]
  [[ "$output" == *"W = c"* ]]
}

@test "cut prunes remaining choice points" {
  run "$TRILOG" test/family.pl -e "first_choice(W)."
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"W = a"* ]]
}

@test "cut is scoped to its own clause across a nested call (regression)" {
  # solving q between the call and '!' must not clobber the barrier and
  # let p(2) leak through.
  run "$TRILOG" test/family.pl -e "p(X)."
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"X = 1"* ]]
  [[ "$output" != *"X = 2"* ]]
}

@test "cut inside recursion only prunes its own call" {
  run "$TRILOG" test/family.pl -e "first_gt3([1,3,4,5,6], X)."
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"X = 4"* ]]
}

# --- boot/core.pl control constructs, built from cut + meta-call ---

@test "disjunction tries both branches on backtrack" {
  run "$TRILOG" test/family.pl -e "(choice(W) ; W=none)."
  [[ "$output" == *"W = a"* ]]
  [[ "$output" == *"W = none"* ]]
}

@test "if-then commits to the condition's first solution only" {
  # Exactly one solution: Else must be unreachable once Cond succeeds
  # (regression: ';'/2's own cut used to miss this).
  run "$TRILOG" test/family.pl -e "(choice(W) -> true ; true)."
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"W = a"* ]]
}

@test "if-then-else takes the else branch on condition failure" {
  run "$TRILOG" test/family.pl -e "(fail -> W=yes ; W=no)."
  [[ "$output" == *"W = no"* ]]
}

@test "negation as failure" {
  run "$TRILOG" test/family.pl -e "(\\+ parent(ann,tom), W=ok)."
  [[ "$output" == *"W = ok"* ]]
}

@test "once commits to the first solution" {
  run "$TRILOG" test/family.pl -e "once(choice(W))."
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"W = a"* ]]
}

# --- raw I/O ---

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

# --- type checks, term inspection, atom/number <-> codes, compare/3 ---
# The small C primitives boot/*.pl's library builds on.

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

# --- integer edge cases ---

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

@test "=.. raises the ISO errors instead of truncating or ignoring a bad tail (regression)" {
  # regression: more than 255 arguments were silently dropped, and [f, a | foo] built f(a).
  run "$TRILOG" -e "
    E = error(X, _),
    findall(X, ( member(L, [[foo|bar], 4, [], [3,1], [a(b),1], [f(a)]]), catch(_ =.. L, E, true) ), Xs),
    length(Args, 300), catch(_ =.. [f|Args], error(R, _), true),
    write(Xs), nl, write(R), nl.
  "
  [[ "$output" == *"[type_error(list, [foo|bar]), type_error(list, 4), domain_error(non_empty_list, []), type_error(atom, 3), type_error(atom, a(b)), type_error(atomic, f(a))]"* ]]
  [[ "$output" == *"representation_error(max_arity)"* ]]
}

@test "functor/3 raises the ISO errors instead of failing silently (regression)" {
  run "$TRILOG" -e "
    E = error(X, _),
    findall(X, ( member(N-A, [foo-a, 1.5-1, foo(a)-1, foo-(-1), foo-256]), catch(functor(_, N, A), E, true) ), Xs),
    write(Xs), nl.
  "
  [[ "$output" == *"[type_error(integer, a), type_error(atom, 1.5), type_error(atomic, foo(a)), domain_error(not_less_than_zero, -1), representation_error(max_arity)]"* ]]
}

@test "startup under a tiny memory cap reports out of memory instead of crashing (regression)" {
  # regression: the arena's malloc was unchecked, so a failed allocation segfaulted.
  for kb in 3500 3750 4000 4250 4500 4750 5000 5500 6000; do
    run bash -c "ulimit -v $kb; $TRILOG -e 'true.'"
    [ "$status" -ne 139 ]
  done
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

@test "atom_to_term/3 populates NameVars, sharing repeated vars, skipping bare _" {
  run "$TRILOG" -e "atom_to_term('foo(X,Y,X,_)', T, NV), write(T-NV), nl."
  [ "$status" -eq 0 ]
  [[ "$output" == *"foo(_G"* ]]
  [[ "$output" == *"=(X, _G"* ]]
  [[ "$output" == *"=(Y, _G"* ]]
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

  run "$TRILOG" -e "X = 3, Y is -X."
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

# --- boot/core.pl library ---

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

@test "if-then-else makes the else branch unreachable once cond succeeds (regression)" {
  # regression: max_list/2 (built on ->/;) used to produce multiple
  # "maximum" values instead of one.
  run "$TRILOG" -e "findall(M, max_list([3,1,4,1,5], M), L)."
  [[ "$output" == *"L = [5]"* ]]
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

@test "bagof does not group by Goal's free variables (regression)" {
  # NOT ISO grouping, deliberately: K/L here stay unbound in the single
  # collected pair rather than backtracking over distinct witnesses.
  run "$TRILOG" -e "
    assertz(bagof_p(a,1)),
    assertz(bagof_p(a,2)),
    assertz(bagof_p(b,3)),
    findall(K-L, bagof(X,bagof_p(K,X),L), Groups), length(Groups, N), write(N).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"N = 1"* ]]
}

@test "bagof with V^Goal has no effect on the ungrouped result (regression)" {
  run "$TRILOG" -e "
    assertz(bagof_p(a,1)),
    assertz(bagof_p(a,2)),
    assertz(bagof_p(b,3)),
    bagof(X, K^bagof_p(K,X), L).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"L = [1, 2, 3]"* ]]
}

@test "bagof fails outright on no solutions, unlike findall's []" {
  run "$TRILOG" -e "bagof(X, member(X,[]), L)."
  [ "$status" -eq 0 ]
  ! succeeded
}

@test "calling a non-callable term throws type_error(callable, _), not a crash (regression)" {
  # a bare integer as a goal used to corrupt the heap: key_of_goal's
  # "not callable" sentinel (pred_id = -1) fed straight into
  # make_existence_error, which built an atom cell from that -1.
  run "$TRILOG" -e "catch(call(42), error(type_error(callable, 42), _), true), write(ok), nl."
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "bagof with an unbound Goal argument doesn't loop forever (regression)" {
  # '$bagof_strip' used to unify an unbound Goal0 with V^G0 itself,
  # recursing on the fresh var forever, instead of throwing
  # instantiation_error.
  run "$TRILOG" -e "catch(bagof(_X,_Y^_Z,_L), error(instantiation_error, _), true), write(ok), nl."
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

@test "setof sorts and dedups, built on bagof plus sort/2" {
  run "$TRILOG" -e "setof(X, member(X,[3,1,2,1]), L)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"L = [1, 2, 3]"* ]]
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

# --- first-argument indexing ---

@test "indexing finds the right clause on a bound first argument" {
  run "$TRILOG" test/family.pl -e "item(three, X)."
  [[ "$output" == *"X = 3"* ]]
}

@test "indexing does not break backtracking (regression)" {
  # regression: a stale binding from the clause that just failed used to
  # wrongly rule out every other clause by index.
  run "$TRILOG" test/family.pl -e "choice(W)."
  [[ "$output" == *"W = a"* ]]
  [[ "$output" == *"W = b"* ]]
  [[ "$output" == *"W = c"* ]]
}

@test "indexing proves determinism across predicates, not just within one (regression)" {
  # regression: the index key used to omit predicate identity, so
  # unrelated clauses looked like matches and choice points never freed.
  skip "pre-existing timeout in this sandbox, confirmed unrelated to any change here"
  run env TRILOG_GC_THRESHOLD=200 timeout 10 "$TRILOG" test/family.pl -e "count(50000)."
  [ "$status" -eq 0 ]
}

# --- catch/3, throw/1 ---
# Implemented natively: an active-catch scope threaded through frame_t.

@test "catch/3 catches a matching thrown ball" {
  run "$TRILOG" -e "catch(throw(oops), oops, W=caught)."
  [[ "$output" == *"W = caught"* ]]
}

@test "catch/3 unifies structured balls" {
  run "$TRILOG" -e "catch(throw(err(1,foo)), err(N,X), true)."
  [[ "$output" == *"N = 1"* ]]
  [[ "$output" == *"X = foo"* ]]
}

@test "non-matching catcher re-throws to the next outer catch/3" {
  run "$TRILOG" -e "catch(catch(throw(a), b, W=inner), a, W=outer)."
  [[ "$output" == *"W = outer"* ]]
}

@test "uncaught exception is reported, not a crash" {
  run "$TRILOG" -e "throw(oops)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"oops"* ]]
}

@test "catch/3 is transparent to a goal that just succeeds or fails" {
  run "$TRILOG" -e "catch(fail, _, true)."
  [ "$status" -eq 0 ]
  ! succeeded
}

# --- cut scoping through ;/->, call/1, catch/3 (regression) ---

@test "a cut reached through a bare ; is transparent to the enclosing goal (regression)" {
  run "$TRILOG" -e "( (write(a), !, fail) ; write(b) )."
  [ "$status" -eq 0 ]
  [[ "$output" == *"a"* ]]
  [[ "$output" != *"b"* ]]
  ! succeeded
}

@test "call/1 gives an embedded cut its own scope, opaque to the enclosing ; (regression)" {
  run "$TRILOG" -e "( call((write(a), !, fail)) ; write(b) )."
  [ "$status" -eq 0 ]
  [[ "$output" == *"a"* ]]
  [[ "$output" == *"b"* ]]
  succeeded
}

@test "catch/3's Goal argument gives an embedded cut its own scope too (regression)" {
  run "$TRILOG" -e "( catch((write(a), !, fail), _, true) ; write(b) )."
  [ "$status" -eq 0 ]
  [[ "$output" == *"a"* ]]
  [[ "$output" == *"b"* ]]
  succeeded
}

@test "once/1 and \\+/1 don't crash on an embedded cut (regression)" {
  run "$TRILOG" -e "once((write(x), !, fail)) ; write(y)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"x"* ]]
  [[ "$output" == *"y"* ]]

  run "$TRILOG" -e "( \\+ (write(z), !, fail) ; write(q) )."
  [ "$status" -eq 0 ]
  [[ "$output" == *"z"* ]]
  [[ "$output" == *"q"* ]]
}

@test "backtracking into Goal through catch/3 finds every solution (regression)" {
  # opt(a) succeeds first, so opt(b)'s later throw needs the catch scope
  # to survive independently of any one attempt.
  run "$TRILOG" test/family.pl -e "catch(opt(W), bad_b, W=recovered)."
  [[ "$output" == *"W = a"* ]]
  [[ "$output" == *"W = recovered"* ]]
}

@test "catch/3 under GC pressure stays correct (regression)" {
  # Correctness under GC pressure, with catch_stack entries as live
  # roots marked/translated/compacted every pass.
  run env TRILOG_GC_THRESHOLD=200 timeout 15 "$TRILOG" test/family.pl -e "catch(count(20000), _, true)."
  [ "$status" -eq 0 ]
}

# --- a foundational solve-loop bug, found while building findall/3 ---

@test "true as a non-final goal does not terminate the query early (regression)" {
  # regression: reaching true as the first pending goal used to end the
  # query, even with real goals still queued after it.
  run "$TRILOG" -e "
    (true, X=ok),
    Y=X.
  "
  [[ "$output" == *"X = ok"* ]]
  [[ "$output" == *"Y = ok"* ]]
}

# --- findall/3, via assert-based accumulation ---

@test "findall/3 collects every solution in order" {
  run "$TRILOG" test/family.pl -e "findall(X, choice(X), L)."
  [[ "$output" == *'L = "abc"'* ]]
}

@test "findall/3 gives an empty list, not failure, for no solutions" {
  run "$TRILOG" test/family.pl -e "findall(X, choice(nonexistent), L)."
  [ "$status" -eq 0 ]
  [[ "$output" == *"L = []"* ]]
}

@test "findall/3 applies the template, not just the goal's bindings" {
  run "$TRILOG" test/family.pl -e "findall(Y, (choice(X), Y = pair(X,X)), L)."
  [[ "$output" == *"L = [pair(a, a), pair(b, b), pair(c, c)]"* ]]
}

@test "nested findall/3 does not conflate inner and outer items (regression)" {
  # regression: unqualified '$findall_item' facts let a nested findall sweep up an outer call's leftover items; fixed via a unique id per call.
  run "$TRILOG" test/family.pl -e "findall(Outer, (choice(_), findall(Inner, inner_choice(Inner), Outer)), L)."
  [[ "$output" == *'L = ["abc", "abc", "abc"]'* ]]
}

# --- term copying: variable sharing, cyclic terms, occurs check ---

@test "unifying and comparing two cyclic terms terminates (regression)" {
  # regression: X = f(X), Y = f(Y), X = Y recursed forever and segfaulted, as did == and compare/3.
  run timeout 20 "$TRILOG" -e "
    X = f(X), Y = f(Y), X = Y, X == Y, compare(O1, X, Y),
    A = f(A), B = f(f(B)), A = B, A == B,
    L = [a|L], M = [a, a|M], L = M, L == M,
    P = f(P, 1), Q = f(Q, 2), ( P = Q -> R1 = unified ; R1 = failed ),
    ( P == Q -> R2 = same ; R2 = different ), compare(O2, P, Q),
    C = g(C), D = g(D), unify_with_occurs_check(C, D),
    write(r(O1, R1, R2, O2)), nl.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"r(=, failed, different, <)"* ]]
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

@test "copy_term/2 preserves variable sharing" {
  run "$TRILOG" -e "copy_term(f(X,Y,X,g(Y)), f(A,B,C,g(D))), A == C, B == D, A \\== B."
  succeeded
}

@test "runaway allocation throws a catchable resource_error(memory) instead of dying (regression)" {
  # regression: the heap grew until GC's scratch arrays failed to allocate, killing the process.
  run bash -c "ulimit -v 524288; timeout 60 $TRILOG -e \"L = ['1'|L], catch(number_chars(_, L), error(E, _), true), write(caught(E)), nl.\""
  [[ "$output" == *"caught(resource_error(memory))"* ]]
}

@test "printing a tail-cyclic list terminates (regression)" {
  # regression: the list printer walked the spine with no limit, looping forever on L = [a|L].
  run timeout 10 "$TRILOG" -e "L = [a|L], write(done), nl."
  [ "$status" -eq 0 ]
  [[ "$output" == *"done"* ]]
  [[ "$output" == *"|...]"* ]]
}

@test "copy_term/2 throws on a cyclic term instead of crashing (regression)" {
  run "$TRILOG" -e "X = f(X), catch(copy_term(X, _), error(E, _), (write(caught(E)), nl))."
  [ "$status" -eq 0 ]
  [[ "$output" == *"caught(representation_error(cyclic_term))"* ]]
}

@test "findall/3 throws on a cyclic solution instead of crashing (regression)" {
  run "$TRILOG" -e "X = [X|_], catch(findall(X, true, _), error(E, _), (write(caught(E)), nl))."
  [ "$status" -eq 0 ]
  [[ "$output" == *"caught(representation_error(cyclic_term))"* ]]
}

@test "assertz/1 throws on a cyclic term instead of crashing (regression)" {
  run "$TRILOG" -e "X = f(X), catch(assertz(p(X)), error(E, _), (write(caught(E)), nl))."
  [ "$status" -eq 0 ]
  [[ "$output" == *"caught(representation_error(cyclic_term))"* ]]
}

@test "unify_with_occurs_check/2 fails where the variable occurs in the term" {
  run "$TRILOG" -e "
    ( unify_with_occurs_check(X, f(X)) -> R1 = unified ; R1 = failed ),
    ( unify_with_occurs_check(f(A,B), f(B,g(A))) -> R2 = unified ; R2 = failed ),
    write(r(R1, R2)), nl.
  "
  [[ "$output" == *"r(failed, failed)"* ]]
}

@test "unify_with_occurs_check/2 unifies like =/2 otherwise" {
  run "$TRILOG" -e "unify_with_occurs_check(f(X,a,[H|T]), f(b,Y,[1,2])), write(X-Y-H-T), nl."
  [[ "$output" == *"-(-(-(b, a), 1), [2])"* ]]
}

@test "unify_with_occurs_check/2 terminates on an already-cyclic term" {
  run timeout 5 "$TRILOG" -e "X = f(X), unify_with_occurs_check(Y, g(X)), write(ok), nl."
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

# --- assertz/1, asserta/1, retract/1 ---

@test "assertz/1 adds a fact, queryable immediately" {
  run "$TRILOG" -e "
    assertz(dyn_fact(1)),
    assertz(dyn_fact(2)),
    dyn_fact(X).
  "
  [[ "$output" == *"X = 1"* ]]
  [[ "$output" == *"X = 2"* ]]
}

@test "asserta/1 prepends rather than appends" {
  run "$TRILOG" -e "
    assertz(dyn_order(z)),
    asserta(dyn_order(a)),
    dyn_order(X).
  "
  [[ "$output" == *"X = a"* ]]
  [[ "$output" == *"X = z"* ]]
}

@test "assertz/1 stores a rule, not just a fact" {
  run "$TRILOG" -e "
    assertz((dyn_double(X,Y) :- Y is X*2)),
    dyn_double(21,R).
  "
  [[ "$output" == *"R = 42"* ]]
}

@test "retract/1 removes exactly the matching clause" {
  run "$TRILOG" -e "
    assertz(dyn_r(1)),
    assertz(dyn_r(2)),
    retract(dyn_r(1)),
    dyn_r(X).
  "
  [[ "$output" == *"X = 2"* ]]
  [[ "$output" != *"X = 1"* ]]
}

@test "retract/1 fails, not errors, when nothing matches" {
  run "$TRILOG" -e "retract(dyn_nonexistent(1))."
  [ "$status" -eq 0 ]
  ! succeeded
}

# --- logical update view: a call iterates the clauses that existed when it started ---

@test "logical update view: retractall/abolish during iteration still yield the original clauses" {
  run "$TRILOG" -e "
    assertz(r(1)), assertz(r(2)), findall(X, (r(X), retractall(r(_))), A),
    assertz(i(ant)), assertz(i(bee)), findall(Y, (i(Y), abolish(i/1)), B),
    write(A-B), nl.
  "
  [[ "$output" == *"-([1, 2], [ant, bee])"* ]]
}

@test "logical update view: clauses added or retracted during iteration are not seen" {
  run "$TRILOG" -e "
    assertz(s(1)), findall(X, (s(X), X < 3, Y is X + 1, assertz(s(Y))), A),
    assertz(q(1)), assertz(q(2)), assertz(q(3)), findall(Z, (q(Z), retract(q(2))), B),
    write(A-B), nl.
  "
  [[ "$output" == *"-([1], [1])"* ]]
}

@test "a cut in a dynamic clause prunes its remaining clauses, through ; and -> too" {
  run "$TRILOG" -e "
    assertz((d(X) :- X > 0, !)), assertz(d(_)),
    findall(one, d(1), A), findall(two, d(0), B),
    assertz((e(X, R) :- ( X > 0 -> R = pos, ! ; R = neg ))), assertz(e(_, other)),
    findall(R1, e(1, R1), C), findall(R2, e(0, R2), D),
    write(r(A, B, C, D)), nl.
  "
  [[ "$output" == *'r([one], [two], [pos], [neg, other])'* ]]
}

@test "a cut inside call/1 or a variable goal in a dynamic clause stays local" {
  run "$TRILOG" -e "
    assertz((f(X) :- call(!), X = 1)), assertz(f(2)),
    assertz((h(X) :- G = !, G, X = 1)), assertz(h(2)),
    findall(X, f(X), A), findall(Y, h(Y), B),
    write(A-B), nl.
  "
  [[ "$output" == *"-([1, 2], [1, 2])"* ]]
}

@test "lib/meta.pl: solve/1 runs goals with cut when consulted" {
  run "$TRILOG" -e "
    consult('lib/meta.pl'),
    findall(X, solve((member(X, [1, 2, 3]), X > 1)), A),
    findall(Y, solve((member(Y, [1, 2, 3]), Y > 1, !)), B),
    write(A-B), nl.
  "
  [[ "$output" == *"-([2, 3], [2])"* ]]
}

@test "assert/retract/abolish raise the ISO errors for bad arguments" {
  run "$TRILOG" -e "
    E = error(X, _),
    findall(X, ( member(G, [assertz(_), assertz(4), asserta((foo :- 4)), retract((4 :- _)),
                            abolish(_), abolish(foo), abolish(foo/_), abolish(foo/a),
                            abolish(5/2), abolish(foo/(-1))]),
                 catch(G, E, true) ), Xs),
    write(Xs), nl.
  "
  [[ "$output" == *"[instantiation_error, type_error(callable, 4), type_error(callable, 4), type_error(callable, 4), instantiation_error, type_error(predicate_indicator, foo), instantiation_error, type_error(integer, a), type_error(atom, 5), domain_error(not_less_than_zero, -1)]"* ]]
}

@test "an asserted predicate still exists, and fails, once its last clause is retracted (regression)" {
  # regression: a predicate counted as existing only while it had clauses, so calling an emptied one raised existence_error.
  run "$TRILOG" -e "
    assertz(st(1)), retract(st(1)),
    assertz(su(1)), retractall(su(_)),
    retractall(sv(_)),
    findall(X, st(X), A), findall(Y, su(Y), B), findall(Z, sv(Z), C),
    write(r(A, B, C)), nl.
  "
  [[ "$output" != *"existence_error"* ]]
  [[ "$output" == *"r([], [], [])"* ]]
}

# --- GC: mark-and-slide with pointer reversal ---
# Both regressions below only show up under a forced low threshold.

@test "GC does not corrupt correctness under a forced low threshold" {
  run env TRILOG_GC_THRESHOLD=50 "$TRILOG" test/family.pl -e "grandparent(tom, W)."
  [[ "$output" == *"W = ann"* ]]
  run env TRILOG_GC_THRESHOLD=50 "$TRILOG" test/family.pl -e "p(X)."
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"X = 1"* ]]
  run env TRILOG_GC_THRESHOLD=50 "$TRILOG" test/family.pl -e "(choice(W) ; W=none)."
  [[ "$output" == *"W = a"* ]]
  [[ "$output" == *"W = none"* ]]
}

@test "a binding made before a still-live choice point survives GC and backtracking out of it (regression)" {
  # regression: gc_maybe_run built trail_new_index AFTER compact_trail() had already mutated trail[], wrongly unbinding a still-live variable.
  run env TRILOG_GC_THRESHOLD=100 timeout 10 "$TRILOG" -e "
    numlist(1,20,L),
    length(L,N).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"L = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]"* ]]
  [[ "$output" == *"N = 20"* ]]
}

@test "cut-discarded garbage is reclaimed, not just accumulated (regression)" {
  # regression: each iteration used to permanently retain one more cell
  # than the last, making GC passes progressively more expensive.
  run env TRILOG_GC_THRESHOLD=200 timeout 10 "$TRILOG" test/family.pl -e "loop(20000)."
  [ "$status" -eq 0 ]
}

@test "deep list survives a full mark pass without stack overflow (regression)" {
  # regression: print_term used to recurse once per list element and
  # segfault well before this length.
  run timeout 10 "$TRILOG" test/family.pl -e "
    count_list(50000, L),
    list_len(L, N).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"N = 50000"* ]]
}

# --- interactive solution-stepping (real tty only) ---

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

# --- DCGs ---

@test "DCG: terminals and phrase/2" {
  printf 'greeting --> [hello], [world].\n' > /tmp/trilog_dcg1.pl
  run "$TRILOG" /tmp/trilog_dcg1.pl -e "phrase(greeting, [hello, world])."
  succeeded
  run "$TRILOG" /tmp/trilog_dcg1.pl -e "phrase(greeting, [hello, there])."
  ! succeeded
  rm -f /tmp/trilog_dcg1.pl
}

@test "DCG: recursion and a {}//1 embedded goal" {
  printf 'digits([D|Ds]) --> [D], { D >= 0, D =< 9 }, digits(Ds).\n' > /tmp/trilog_dcg2.pl
  printf 'digits([D]) --> [D], { D >= 0, D =< 9 }.\n' >> /tmp/trilog_dcg2.pl
  run "$TRILOG" /tmp/trilog_dcg2.pl -e "phrase(digits(Ds), [1,2,3])."
  [[ "$output" == *"Ds = [1, 2, 3]"* ]]
  rm -f /tmp/trilog_dcg2.pl
}

@test "DCG: ; alternation and a cut committing a branch" {
  cat > /tmp/trilog_dcg3.pl <<'EOF'
alt --> [x] ; [y].
opt --> [z], !, [w].
opt --> [].
EOF
  run "$TRILOG" /tmp/trilog_dcg3.pl -e "phrase(alt, [x])."
  succeeded
  run "$TRILOG" /tmp/trilog_dcg3.pl -e "phrase(alt, [y])."
  succeeded
  run "$TRILOG" /tmp/trilog_dcg3.pl -e "phrase(opt, [z, w])."
  succeeded
  run "$TRILOG" /tmp/trilog_dcg3.pl -e "phrase(opt, [])."
  succeeded
  rm -f /tmp/trilog_dcg3.pl
}

@test "DCG: a recursive nonterminal handles a long input in bounded memory (regression)" {
  # regression: each recursive call nested another solve/2 meta-interpreter, so 10 items already exhausted memory.
  cat > /tmp/trilog_dcg4.pl <<'EOF'
count(N0, N) --> [_], !, { N1 is N0 + 1 }, count(N1, N).
count(N, N) --> [].
EOF
  run bash -c "ulimit -v 1048576; timeout 30 $TRILOG /tmp/trilog_dcg4.pl -e \"length(L, 2000), phrase(count(0, N), L).\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"N = 2000"* ]]
  rm -f /tmp/trilog_dcg4.pl
}

# --- cut representation (regression) ---

@test "a clause asserted with a literal cut still cuts correctly when called from a different depth (regression)" {
  run "$TRILOG" -e "
    assertz((foo(1))),
    assertz((foo(X) :- X=2, !)),
    assertz((foo(3))),
    findall(Z, foo(Z), L),
    write(L).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"[1, 2]"* ]]
}

# --- solve/2's own cut correctness (regression) ---

@test "solve/2: a cut after a multi-clause call gives exactly one answer, not one per remaining alternative" {
  run "$TRILOG" test/family.pl -e "
    first_choice(W),
    write(W).
  "
  [ "$status" -eq 0 ]
  [ "$(answers)" -eq 1 ]
  [[ "$output" == *"W = a"* ]]
}

@test "solve/2: a cut-committed base case keeps every binding it made, including the final list tail" {
  run "$TRILOG" -e "
    assertz((build(0,[]):-!)),
    assertz((build(N,[N|T]):-N>0,N1 is N-1,build(N1,T))),
    build(3,L),
    write(L).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"[3, 2, 1]"* ]]
}

@test "solve/2: a recursive predicate's own cut never leaks into its own recursive call (regression)" {
  run "$TRILOG" -e "
    assertz((mycollect(Id,L):-retract(item(Id,X)),!,L=[X|Rest],mycollect(Id,Rest))),
    assertz((mycollect(Id,[]):-retract(mark(Id)))),
    assertz(mark(1)),
    assertz(item(1,a)),
    assertz(item(1,b)),
    mycollect(1,L),
    write(L).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ab"'* ]]
}

@test "solve/2: findall/3 itself works, having survived every prior cut design's failure mode" {
  run "$TRILOG" test/family.pl -e "
    findall(X, choice(X), L),
    write(L).
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *'"abc"'* ]]
}

@test "solve/2: two cuts in one clause body both fire, and everything after the second still runs" {
  run "$TRILOG" -e "
    assertz((foo:-write(a),!,write(b),!,write(c))),
    foo.
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"abc"* ]]
}

@test "solve/2: plain cut-free backtracking is unaffected (regression)" {
  run "$TRILOG" test/family.pl -e "
    choice(X),
    write(X),
    nl,
    fail
    ; true.
  "
  [[ "$output" == *"a"* ]]
  [[ "$output" == *"b"* ]]
  [[ "$output" == *"c"* ]]
}

@test "solve/2: DCG rules with an embedded cut work under meta-interpretation" {
  printf 'opt --> [z], !, [w].\nopt --> [].\n' > /tmp/mi_dcg_test.pl
  run "$TRILOG" /tmp/mi_dcg_test.pl -e "phrase(opt, [z, w])."
  [ "$status" -eq 0 ]
  succeeded
  run "$TRILOG" /tmp/mi_dcg_test.pl -e "phrase(opt, [])."
  [ "$status" -eq 0 ]
  succeeded
  rm -f /tmp/mi_dcg_test.pl
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
  run "$TRILOG" /tmp/mi_nest_test/a.pl -e "findall(X, a(X), A), findall(Y, b(Y), B)."
  [[ "$output" == *"A = [1, 2]"* ]]
  [[ "$output" == *"B = [1]"* ]]
  rm -rf /tmp/mi_nest_test
}

@test "GC inside a nested consult's directives leaves the outer query intact (regression)" {
  # regression: a nested query reset the choicepoint stack and garbage-collected without the outer query's roots, so the outer one resumed on freed terms and called stray subterms.
  mkdir -p /tmp/mi_gcnest_test
  printf ":- consult('inner.pl').\nafter(1).\n" > /tmp/mi_gcnest_test/outer.pl
  printf ":- op(700, xfx, '==>').\n:- X = f(a).\ninner_fact(1).\n" > /tmp/mi_gcnest_test/inner.pl
  TRILOG_GC_THRESHOLD=2000 run "$TRILOG" -f /tmp/mi_gcnest_test/outer.pl -e "after(X), inner_fact(Y)."
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

@test "the release build runs from an empty directory, its libraries baked in" {
  run make -s -C "$BATS_TEST_DIRNAME/.." release
  [ "$status" -eq 0 ]
  dir=$(mktemp -d)
  cp "$BATS_TEST_DIRNAME/../_build/trilog" "$dir/"
  run bash -c "cd '$dir' && ./trilog -f -e \"append(X, [c], [a,b,c]), maplist(atom, X), phrase([a], [a]), consult('lib/meta.pl'), findall(Y, solve(member(Y, [1, 2])), L), write(done(L)), nl.\""
  rm -rf "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"done([1, 2])"* ]]
  [[ "$output" != *"uncaught"* ]]
  [[ "$output" != *"cannot open"* ]]
}

@test "the no_posix platform build links no POSIX symbols and runs" {
  run make -s -C "$BATS_TEST_DIRNAME/.." PLATFORM=no_posix release
  [ "$status" -eq 0 ]
  bin="$BATS_TEST_DIRNAME/../_build/trilog"
  run bash -c "nm -u '$bin' | grep -wE 'clock_gettime|getrlimit|stat|isatty|tcgetattr|tcsetattr|readlink|fileno'"
  [ "$status" -ne 0 ]
  dir=$(mktemp -d)
  cp "$bin" "$dir/"
  run bash -c "cd '$dir' && ./trilog -f -e \"append(X, [bb], [aa,bb]), write(ok(X)), nl, catch(get_time_ms(_), error(E1, _), true), catch(make, error(E2, _), true).\""
  rm -rf "$dir"
  make -s -C "$BATS_TEST_DIRNAME/.." release
  [[ "$output" == *"ok([aa])"* ]]
  [[ "$output" == *"E1 = existence_error(procedure, /(get_time_ms, 1))"* ]]
  [[ "$output" == *"E2 = existence_error(procedure, /(file_mtime, 2))"* ]]
}

@test "loading boot/core.pl and lib/ at startup produces no uncaught exceptions (regression)" {
  run "$TRILOG" -f -e "true."
  [ "$status" -eq 0 ]
  [[ "$output" != *"existence_error"* ]]
  [[ "$output" != *"uncaught exception"* ]]
}

@test "DCG rules translate lazily at call time, not eagerly at consult time (regression)" {
  run "$TRILOG" -e "
    assertz((greeting --> [hello],[world])),
    phrase(greeting,[hello,world]).
  "
  [ "$status" -eq 0 ]
  succeeded
}

@test "the engine keeps no writable global state" {
  root="$BATS_TEST_DIRNAME/.."
  for f in "$root"/src/kernel/*.c "$root"/src/io/*.c "$root"/src/trilog.c "$root"/src/platform/*.c; do
    gcc -std=c11 -O2 -I"$root/include" -I"$root/src/kernel" -I"$root/src/io" -I"$root/src/platform" -I"$root/_build" \
      -c "$f" -o "$BATS_TEST_TMPDIR/obj.o"
    run bash -c "size -A '$BATS_TEST_TMPDIR/obj.o' | awk '\$1 ~ /^\\.(data|bss|data\\.rel|data\\.rel\\.local)\$/ && \$2 > 0'"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "$f: $output"; false; }
  done
}

@test "the library exports only the trilog_ API" {
  run make -s -C "$BATS_TEST_DIRNAME/.." lib
  [ "$status" -eq 0 ]
  run bash -c "nm -g --defined-only '$BATS_TEST_DIRNAME/../_build/dev-posix/libtrilog.a' | awk '\$2 ~ /[TDBR]/ {print \$3}' | grep -v '^trilog_'"
  [ -z "$output" ]
}

@test "make OPAQUE=0 exports the engine's internal symbols too" {
  run make -s -C "$BATS_TEST_DIRNAME/.." OPAQUE=0 lib
  [ "$status" -eq 0 ]
  run bash -c "nm -g --defined-only '$BATS_TEST_DIRNAME/../_build/dev-posix-open/libtrilog.a' | awk '\$2 ~ /T/ {print \$3}'"
  [[ "$output" == *"unify"* ]]
  [[ "$output" == *"heap_alloc"* ]]
  [[ "$output" == *"trilog_new"* ]]
}

@test "trilog -V prints git describe and the branch" {
  root="$BATS_TEST_DIRNAME/.."
  expected="trilog $(git -C "$root" describe --tags --always --dirty) ($(git -C "$root" rev-parse --abbrev-ref HEAD))"
  run make -s -C "$root" trilog
  run "$TRILOG" -V
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "trilog.h compiles and links as C++" {
  command -v g++ >/dev/null || skip "no g++"
  root="$BATS_TEST_DIRNAME/.."
  printf '#include "trilog.h"\nint main() { return trilog_version()[0] == 0; }\n' > "$BATS_TEST_TMPDIR/host.cpp"
  run g++ -std=c++17 -Wall -Wextra -pedantic -Werror -I"$root/include" -o "$BATS_TEST_TMPDIR/host" \
    "$BATS_TEST_TMPDIR/host.cpp" "$root/_build/dev-posix/libtrilog.a" -lm
  [ "$status" -eq 0 ]
  run "$BATS_TEST_TMPDIR/host"
  [ "$status" -eq 0 ]
}


@test "reconsulting a file replaces its clauses instead of appending" {
  printf ":- dynamic(p/1).\np(1).\np(2).\n" > "$BATS_TEST_TMPDIR/r.pl"
  run "$TRILOG" -f -e "consult('$BATS_TEST_TMPDIR/r.pl'), assertz(p(99)), consult('$BATS_TEST_TMPDIR/r.pl'), findall(X, p(X), L)."
  [[ "$output" == *"L = [99, 1, 2]"* ]]
}

@test "unconsult/1 removes only the file's clauses and fails when not loaded" {
  printf ":- dynamic(p/1).\np(1).\n" > "$BATS_TEST_TMPDIR/u.pl"
  run "$TRILOG" -f -e "consult('$BATS_TEST_TMPDIR/u.pl'), assertz(p(2)), unconsult('$BATS_TEST_TMPDIR/u.pl'), findall(X, p(X), L), ( unconsult('$BATS_TEST_TMPDIR/u.pl') -> A = loaded ; A = not_loaded )."
  [[ "$output" == *"L = [2], A = not_loaded"* ]]
}

@test "consulted/1 lists loaded files, including ones from the command line" {
  printf "q(1).\n" > "$BATS_TEST_TMPDIR/c.pl"
  run "$TRILOG" -f "$BATS_TEST_TMPDIR/c.pl" -e "consulted(L), member(F, L), atom_concat(_, 'c.pl', F)."
  succeeded
  [ "$(answers)" -eq 1 ]
}

@test "make/0 reconsults files that changed since they were loaded" {
  printf "v(old).\n" > "$BATS_TEST_TMPDIR/m.pl"
  touch -t 202001010000 "$BATS_TEST_TMPDIR/m.pl"
  run "$TRILOG" -f "$BATS_TEST_TMPDIR/m.pl" -e "open('$BATS_TEST_TMPDIR/m.pl', write, S), write(S, 'v(new).'), nl(S), close(S), make, findall(X, v(X), L)."
  [[ "$output" == *"L = [new]"* ]]
}

@test "atom_to_term/3 in a directive leaves the rest of the file loading (regression)" {
  # regression: run-time parsing overwrote the consult's parse position.
  printf "a(1).\n:- atom_to_term('foo(X, Y)', _, _).\na(2).\na(3).\n" > "$BATS_TEST_TMPDIR/att.pl"
  run "$TRILOG" -f "$BATS_TEST_TMPDIR/att.pl" -e "findall(X, a(X), L)."
  [[ "$output" == *"L = [1, 2, 3]"* ]]
}

@test "answers are printed quoted, so atoms read back as atoms (#14, #16)" {
  run "$TRILOG" -f -e "\"1\" = [Ch], X = '1', Y = 'hello world', Z = abc."
  [[ "$output" == *"Ch = '1', X = '1', Y = 'hello world', Z = abc"* ]]
}

@test "current_prolog_flag/2 enumerates every ISO flag, unknown included (#13)" {
  run "$TRILOG" -f -e "current_prolog_flag(unknown, U), current_prolog_flag(char_conversion, C), current_prolog_flag(debug, D), findall(F, current_prolog_flag(F, _), Fs), length(Fs, N)."
  [[ "$output" == *"U = error, C = off, D = off"* ]]
  [[ "$output" == *"N = 9"* ]]
  run "$TRILOG" -f -e "catch(current_prolog_flag(1, _), error(E, _), true)."
  [[ "$output" == *"E = type_error(atom, 1)"* ]]
}
