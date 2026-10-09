% builtins tests

% --- is/2 basic arithmetic ---

?- X is 5.
   X = 5.

?- X is 2 + 3.
   X = 5.

?- X is 10 - 4.
   X = 6.

?- X is 3 * 4.
   X = 12.

?- X is 15 / 3.
   X = 5.

?- X is 7 / 2.
   X = 3.

?- X is 17 mod 5.
   X = 2.

?- X is 10 mod 5.
   X = 0.

?- X is -3 + 5.
   X = 2.

?- X is 3 - 10.
   X = -7.

% --- is/2 complex expressions ---

?- X is 1 + 2 + 3.
   X = 6.

?- X is 2 + 3 * 4.
   X = 14.

?- X is 10 - 2 * 3.
   X = 4.

?- X is (2 + 3) * 4.
   X = 20.

?- X is 2 * 3 + 4 * 5.
   X = 26.

?- X is 20 / 4 * 2.
   X = 10.

% --- is/2 with variables ---

bnum(5).

?- bnum(N), X is N + 1.
   N = 5, X = 6.

bpair(3, 4).

?- bpair(A, B), X is A + B.
   A = 3, B = 4, X = 7.

?- 5 is 2 + 3.
   true.

?- 6 is 2 + 3.
   false.

% --- is/2 failures ---

?- X is Y + 1.
   error(instantiation_error).

?- X is foo + 1.
   error(type_error(evaluable, foo/0)).

?- X is "hello".
   error(type_error(evaluable, "hello")).

% --- comparison: less than ---

?- 3 < 5.
   true.

?- 5 < 5.
   false.

?- 7 < 5.
   false.

?- 2 + 1 < 2 * 2.
   true.

% --- comparison: greater than ---

?- 5 > 3.
   true.

?- 5 > 5.
   false.

?- 3 > 5.
   false.

?- 3 * 3 > 2 + 5.
   true.

% --- comparison: less than or equal ---

?- 3 =< 5.
   true.

?- 5 =< 5.
   true.

?- 7 =< 5.
   false.

% --- comparison: greater than or equal ---

?- 5 >= 3.
   true.

?- 5 >= 5.
   true.

?- 3 >= 5.
   false.

% --- comparison: arithmetic equal ---

?- 5 =:= 5.
   true.

?- 2 + 3 =:= 1 + 4.
   true.

?- 5 =:= 6.
   false.

% --- comparison: arithmetic not equal ---

?- 5 =\= 6.
   true.

?- 5 =\= 5.
   false.

?- 2 * 3 =\= 2 + 3.
   true.

% --- true/0 and fail/0 ---

?- true.
   true.

?- fail.
   false.

btruefoo(a).

?- btruefoo(X), true.
   X = a.

% --- unification: =/2 ---

?- a = a.
   true.

?- a = b.
   false.

?- X = foo.
   X = foo.

?- X = Y, X = hello.
   X = hello, Y = hello.

?- foo(a, B) = foo(A, b).
   A = a, B = b.

?- foo(a) = bar(a).
   false.

?- foo(a) = foo(a, b).
   false.

?- [H|T] = [1, 2, 3].
   H = 1, T = [2, 3].

% --- not unifiable: \=/2 ---

?- a \= b.
   true.

?- a \= a.
   false.

?- X \= a.
   false.

?- foo(a) \= foo(b).
   true.

?- X \= a, X = b.
   false.

% --- combined builtins ---

bdouble(X, Y) :- Y is X * 2.

?- bdouble(5, D).
   D = 10.

bpositive(X) :- X > 0.

?- bpositive(5).
   true.

?- bpositive(-3).
   false.

bmax(X, Y, X) :- X >= Y.
bmax(X, Y, Y) :- Y > X.

?- bmax(3, 7, M).
   M = 7.

bfact(0, 1).
bfact(N, F) :- N > 0, N1 is N - 1, bfact(N1, F1), F is N * F1.

?- bfact(0, F).
   F = 1.

?- bfact(5, F).
   F = 120.

bsum([], 0).
bsum([H|T], S) :- bsum(T, S1), S is S1 + H.

?- bsum([1, 2, 3, 4], S).
   S = 10.

% --- edge cases ---

?- X is 0 + 0.
   X = 0.

?- X is 5 * 0.
   X = 0.

?- 0 < 1.
   true.

?- -5 < -3.
   true.

% --- findall basic ---

bfoo(a).
bfoo(b).
bfoo(c).

?- findall(X, bfoo(X), L).
   L = "abc".

:- dynamic(bar/1).

?- findall(X, bar(X), L).
   L = [].

bfoo2(only).

?- findall(X, bfoo2(X), L).
   L = [only].

% --- findall with templates ---

bpair2(1, a).
bpair2(2, b).
bpair2(3, c).

?- findall(Y, bpair2(X, Y), L).
   L = "abc".

?- findall(x, bfoo(X), L).
   L = "xxx".

bedge(a, b).
bedge(b, c).

?- findall(pair(X, Y), bedge(X, Y), L).
   L = [pair(a, b), pair(b, c)].

% --- findall with rules ---

bparent(tom, bob).
bparent(tom, liz).
bparent(bob, jim).
bchild(C, P) :- bparent(P, C).

?- findall(C, bchild(C, tom), L).
   L = [bob, liz].

?- findall(X, member(X, [1, 2, 3]), L).
   L = [1, 2, 3].

% --- findall nested ---

bitem(a).
bitem(b).
ball_items(L) :- findall(X, bitem(X), L).

?- ball_items(L).
   L = "ab".

% --- bagof basic ---

?- bagof(X, bfoo(X), L).
   L = "abc".

?- bagof(X, bar(X), L).
   false.

?- bagof(X, bfoo2(X), L).
   L = [only].

bpair3(1, x).
bpair3(2, y).

?- bagof(B, bpair3(A, B), L).
   L = "xy".

% --- nl/0 ---

?- nl.
   true.

% --- write/1 ---

?- write(hello).
   true.

?- write(42).
   true.

?- write(foo(a, b)).
   true.

?- X = hello, write(X).
   X = hello.

?- write(anything).
   true.

bgreet :- write(hi).

?- bgreet.
   true.

% --- writeln/1 ---

?- writeln(hello).
   true.

?- writeln(99).
   true.

?- writeln(anything).
   true.

bannounce(X) :- writeln(X).

?- bannounce(done).
   true.

% --- \+/1 negation as failure ---

?- \+ fail.
   true.

?- \+ true.
   false.

bnfoo(a).

?- \+ bnfoo(b).
   true.

?- \+ bnfoo(a).
   false.

?- X = b, \+ bnfoo(X).
   X = b.

?- \+ bnfoo(X).
   false.

bnot_foo(X) :- \+ bnfoo(X).

?- bnot_foo(b).
   true.

?- \+(fail).
   true.

% --- call/1 ---

?- call(true).
   true.

?- call(fail).
   false.

bcfoo(a).

?- call(bcfoo(a)).
   true.

?- G = bcfoo(a), call(G).
   G = bcfoo(a).

?- call(bcfoo(X)).
   X = a.

?- findall(X, call(member(X, [1, 2, 3])), L).
   L = [1, 2, 3].

bcapply(G) :- call(G).

?- bcapply(bcfoo(X)).
   X = a.

?- \+ call(bcfoo(b)).
   true.

?- call(call(true)).
   true.

% --- var/1 ---

?- var(X).
   true.

?- X = a, var(X).
   false.

?- var(foo).
   false.

?- var(42).
   false.

% --- nonvar/1 ---

?- nonvar(foo).
   true.

?- nonvar(42).
   true.

?- nonvar(f(x)).
   true.

?- X = a, nonvar(X).
   X = a.

?- nonvar(X).
   false.

% --- atom/1 ---

?- atom(foo).
   true.

?- atom([]).
   true.

?- atom(42).
   false.

?- atom(f(x)).
   false.

?- atom(X).
   false.

% --- integer/1 ---

?- integer(42).
   true.

?- integer(0).
   true.

?- integer(-3).
   true.

?- integer(foo).
   false.

?- integer(X).
   false.

?- X is 2 + 3, integer(X).
   X = 5.

% --- is_list/1 ---

?- is_list([]).
   true.

?- is_list([1, 2, 3]).
   true.

?- is_list([a]).
   true.

?- is_list(foo).
   false.

?- is_list([a|b]).
   false.

?- is_list([a|_]).
   false.

% --- functor/3 ---

?- functor(foo(a, b), N, A).
   N = foo, A = 2.

?- functor(T, foo, 2), T = foo(a, b).
   T = foo(a, b).

% --- bitwise arithmetic ---

?- X is 5 \/ 3.
   X = 7.

?- X is 5 /\ 3.
   X = 1.

?- X is 5 xor 3.
   X = 6.

?- X is 8 >> 2.
   X = 2.

?- X is 1 << 4.
   X = 16.

?- X is \(0).
   X = -1.

?- X is \(1).
   X = -2.

?- X is (5 /\ 6) \/ 1.
   X = 5.

% --- block comments ---

?- X is /* ignored */ 3 + 4.
   X = 7.

?- X = hello /* world */.
   X = hello.

% --- current_prolog_flag/2 ---

?- current_prolog_flag(bounded, V).
   V = true.

?- current_prolog_flag(integer_rounding_function, V).
   V = toward_zero.

?- current_prolog_flag(double_quotes, V).
   V = chars.

?- current_prolog_flag(max_integer, V).
   V = 2147483647.

?- current_prolog_flag(min_integer, V).
   V = -2147483648.

% enumeration: all flags must be produced
?- findall(F, current_prolog_flag(F, _), Fs), length(Fs, N), N > 0.
   Fs = [bounded, max_integer, min_integer, integer_rounding_function, max_arity, double_quotes, unknown, char_conversion, debug], N = 9.

% domain_error for unknown flag
?- current_prolog_flag(unknown_flag, _).
   error(domain_error(prolog_flag, unknown_flag)).

% "abc" parses as char list [a,b,c]
?- X = "abc".
   X = "abc".

?- "abc" = [a, b, c].
   true.

?- "hello" = [h, e, l, l, o].
   true.

% char list prints as string
?- findall(X, member(X, "abc"), L).
   L = "abc".

% double-quoted string is a proper list
?- is_list("abc").
   true.

?- length("abc", N).
   N = 3.

% --- read_from_chars/2 ---

?- read_from_chars("hello", T).
   T = hello.

?- read_from_chars("f(a, b)", T).
   T = f(a, b).

?- read_from_chars("42", T).
   T = 42.

?- read_from_chars("1+2", T).
   T = 1+2.

?- read_from_chars("[]", T).
   T = [].

?- read_from_chars("[1,2,3]", T).
   T = [1, 2, 3].

% iso read_term/3 at end of input gives end_of_file
?- read_from_chars([], T).
   T = end_of_file.

?- read_from_chars("  \n", T).
   T = end_of_file.

% --- read_term_from_chars/3 ---

?- read_term_from_chars("f(X, Y)", T, [variable_names(Vs)]).
   T = f(X, Y), Vs = ['X'=X, 'Y'=Y].

?- read_term_from_chars("hello", T, []).
   T = hello.

?- read_term_from_chars("f(X)", T, [variable_names(Vs)]).
   T = f(X), Vs = ['X'=X].

?- read_term_from_chars("f(X, _, Y, X)", T, [variable_names(Ns), variables(Vs)]).
   T = f(X, _A, Y, X), Ns = ['X'=X, 'Y'=Y], Vs = [X, _A, Y].

?- catch(read_from_chars("f(", _), error(E, _), true).
   E = syntax_error('unexpected end of input near ""').

?- catch(read_from_chars(_, _), error(E, C), true).
   E = instantiation_error, C = read_from_chars/2.

?- catch(read_from_chars([a, 1], _), error(E, _), true).
   E = type_error(character, 1).

?- catch(read_term_from_chars("a", _, [bad]), error(E, C), true).
   E = domain_error(read_option, bad), C = read_term_from_chars/3.

?- catch(read_term_from_chars("a", _, foo), error(E, _), true).
   E = type_error(list, foo).

?- write_term_to_chars('a b'+[x|y], [quoted(true), ignore_ops(true)], Cs).
   Cs = "+('a b', [x|y])".

?- write_term_to_chars('a b', [quoted(false)], Cs).
   Cs = "a b".

?- catch(write_term_to_chars(a, [quoted(maybe)], _), error(E, C), true).
   E = domain_error(write_option, quoted(maybe)), C = write_term_to_chars/3.

?- catch(write_term(a, [_]), error(E, C), true).
   E = instantiation_error, C = write_term/2.

?- catch(write_term(a, [color(red)]), error(E, _), true).
   E = domain_error(write_option, color(red)).

% --- write_term_to_chars/3 ---

?- write_term_to_chars(hello, [], Cs).
   Cs = "hello".

?- write_term_to_chars(f(a, b), [], Cs).
   Cs = "f(a, b)".

?- write_term_to_chars(42, [], Cs).
   Cs = "42".

?- write_term_to_chars([1,2,3], [], Cs).
   Cs = "[1, 2, 3]".

% roundtrip: write then read
?- write_term_to_chars(f(a, b), [quoted(true)], Cs), read_from_chars(Cs, T).
   Cs = "f(a, b)", T = f(a, b).

?- write_term_to_chars(hello, [quoted(true)], Cs), read_from_chars(Cs, T).
   Cs = "hello", T = hello.

% numbervars/3 and the numbervars(true) write option
?- T = f(X, Y, X), numbervars(T, 0, E).
   T = f('$VAR'(0), '$VAR'(1), '$VAR'(0)), X = '$VAR'(0), Y = '$VAR'(1), E = 2.

?- numbervars(f(a), 5, E).
   E = 5.

?- catch(numbervars(_, a, _), error(E, C), true).
   E = type_error(integer, a), C = numbervars/3.

?- write_term_to_chars(['$VAR'(0), '$VAR'(25), '$VAR'(26), '$VAR'(53)], [numbervars(true)], Cs).
   Cs = "[A, Z, A1, B2]".

?- write_term_to_chars('$VAR'(1), [quoted(true)], Cs).
   Cs = "'$VAR'(1)".

?- write_term_to_chars(['$VAR'(-1), '$VAR'(x)], [quoted(true), numbervars(true)], Cs).
   Cs = "['$VAR'(-1), '$VAR'(x)]".

?- with_output_to(chars(Cs), writeq('$VAR'(1))).
   Cs = "B".

?- with_output_to(chars(Cs), write('$VAR'(2))).
   Cs = "C".

% is_list/1 does not bind an open tail
?- is_list([a|_]).
   false.

?- X = [a|X], is_list(X).
   false.

% length/2 errors and modes
?- catch(length(_, -1), error(E, _), true).
   E = domain_error(not_less_than_zero, -1).

?- catch(length(_, a), error(E, _), true).
   E = type_error(integer, a).

?- length([a, b|T], 4).
   T = [_A, _B].

?- once(length([a, b|T], N)).
   T = [], N = 2.

?- length([a|b], _).
   false.

% keysort/2 is stable and checks its arguments
?- keysort([b-1, a-2, b-0, a-1], S).
   S = [a-2, a-1, b-1, b-0].

?- catch(keysort([a-1, x], _), error(E, _), true).
   E = type_error(pair, x).

?- catch(keysort([a-1|_], _), error(E, _), true).
   E = instantiation_error.

?- catch(keysort(foo, _), error(E, C), true).
   E = type_error(list, foo), C = keysort/2.

% subsumes_term/2
?- subsumes_term(f(_, b), f(a, b)).
   true.

?- subsumes_term(f(a, b), f(_, b)).
   false.

?- subsumes_term(f(X, X), f(_, _)).
   false.

?- subsumes_term(f(_, _), f(X, X)).
   true.

?- subsumes_term(X, f(X)).
   false.

% write_canonical/1
?- with_output_to(chars(Cs), write_canonical(f('B c', 1+2))).
   Cs = "f('B c', +(1, 2))".

% op/3 permission and argument errors (8.14.3.3, Cor.2)
?- catch(op(1000, xfy, ','), error(E, _), true).
   E = permission_error(modify, operator, ',').

?- catch(op(999, xfy, '|'), error(E, _), true).
   E = permission_error(create, operator, '|').

?- catch(op(699, xf, >), error(E, _), true).
   E = permission_error(create, operator, >).

?- catch(op(700, _, foo), error(E, _), true).
   E = instantiation_error.

?- catch(op(700, xfx, [a, 1]), error(E, _), true).
   E = type_error(atom, 1).

?- catch(op(700, xfx, f(x)), error(E, _), true).
   E = type_error(list, f(x)).

?- current_op(P, T, rem).
   P = 400, T = yfx.

% rem, **, ^ and the float functions
?- X is -7 rem 2, Y is -7 mod 2.
   X = -1, Y = 1.

?- catch(_ is 7 rem 0, error(E, _), true).
   E = evaluation_error(zero_divisor).

?- X is 2 ** 3.
   X = 8.0.

?- X is 2 ^ 10.
   X = 1024.

?- catch(_ is 2 ^ -1, error(E, _), true).
   E = type_error(float, 2).

?- X is 1 ^ -5, Y is -1 ^ -3.
   X = 1, Y = -1.

?- catch(_ is 2 ^ 63, error(E, _), true).
   E = evaluation_error(int_overflow).

?- X is sqrt(16), Y is exp(0), Z is log(1).
   X = 4.0, Y = 1.0, Z = 0.0.

?- catch(_ is sqrt(-1), error(E, _), true).
   E = evaluation_error(undefined).

?- catch(_ is atan2(0, 0), error(E, _), true).
   E = evaluation_error(undefined).

?- X is float_integer_part(-2.5), Y is float_fractional_part(-2.5).
   X = -2.0, Y = -0.5.

?- catch(_ is float_integer_part(2), error(E, _), true).
   E = type_error(float, 2).

?- X is pi, X > 3.14159, X < 3.1416.
   X = 3.141592653589793.
