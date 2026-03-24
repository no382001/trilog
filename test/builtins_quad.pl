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
   L = [a, b, c].

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
   L = [a, b, c].

?- findall(x, bfoo(X), L).
   L = [x, x, x].

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
   L = [a, b].

% --- bagof basic ---

?- bagof(X, bfoo(X), L).
   L = [a, b, c].

?- bagof(X, bar(X), L).
   false.

?- bagof(X, bfoo2(X), L).
   L = [only].

bpair3(1, x).
bpair3(2, y).

?- bagof(B, bpair3(A, B), L).
   L = [x, y].

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
