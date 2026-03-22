% solver tests

% --- append ---

?- append([], [], X).
   X = [].

?- append([], [1, 2], X).
   X = [1, 2].

?- append([1, 2], [], X).
   X = [1, 2].

?- append([1, 2], [3, 4], X).
   X = [1, 2, 3, 4].

?- append([a], [b], X).
   X = [a, b].

?- append([1, 2], [3], [1, 2, 3]).
   true.

?- append([1, 2], [3], [1, 2, 4]).
   false.

% --- member ---

?- member(1, [1, 2, 3]).
   true.

?- member(2, [1, 2, 3]).
   true.

?- member(3, [1, 2, 3]).
   true.

?- member(4, [1, 2, 3]).
   false.

?- member(1, []).
   false.

?- member(a, [a]).
   true.

?- member(b, [a]).
   false.

% --- combined ---

?- append([1], [2], X), member(1, X).
   X = [1, 2].

?- append([1], [2], X), member(3, X).
   false.

% --- facts ---

foo_s(a).
foo_s(b).

?- foo_s(a).
   true.

?- foo_s(X).
   X = a
;  X = b.

?- foo_s(c).
   false.

% --- nested structures ---

fs(g(a)).

?- fs(g(X)).
   X = a.

?- fs(h(X)).
   false.

% --- rules ---

sparent(tom, bob).
sparent(bob, jim).
sgrandparent(X, Z) :- sparent(X, Y), sparent(Y, Z).

?- sparent(tom, X).
   X = bob.

?- sgrandparent(tom, X).
   X = jim.

% --- anonymous variables ---

safoo(a, b).

?- safoo(_, b).
   true.

?- safoo(_, _).
   true.

sapair(a, b).

?- sapair(_, _).
   true.

safirst([H|_], H).

?- safirst([1, 2, 3], X).
   X = 1.

sasecond([_, X|_], X).

?- sasecond([a, b, c], X).
   X = b.

?- _ = foo.
   true.

sawrap(f(a, b)).

?- sawrap(_).
   true.

safoo2(a).
sabar :- safoo2(_).

?- sabar.
   true.

safoo3(a).
safoo3(b).
saboth :- safoo3(_), safoo3(_).

?- once(saboth).
   true.

% --- backtrack reclamation (term pool) ---
% Backtracking previously leaked goals_alloc'd terms. With term_mark
% in choice point frames, backtracking reclaims them.

% between(1,3000,X) backtracks 2999 times — would exhaust the term pool
% without backtrack reclamation.
?- between(1, 3000, X), X =:= 3000.
   X = 3000.

% --- LCO (last call optimization / binding reclamation) ---
% Deterministic recursive predicates that previously exhausted the
% binding trail (MAX_BINDINGS=4096) now survive via substitute+reclaim.

% between to depth 2000 — previously crashed at ~680
?- between(1, 2000, X), X =:= 2000.
   X = 2000.

% LCO must preserve binding chains through append
?- append([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], [a, b, c], X).
   X = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, a, b, c].

% deeper append through LCO binding chain patching
?- append([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20], [end], _X), length(_X, N).
   N = 21.

% reverse exercises accumulator-style recursion
?- reverse([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], X).
   X = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1].

% multi-solution with between — LCO must not break backtracking
?- between(1, 5, X).
   X = 1
;  X = 2
;  X = 3
;  X = 4
;  X = 5.

% findall+between — LCO disabled inside findall by bind_floor
?- findall(_X, between(1, 10, _X), _L), length(_L, N).
   N = 10.

% findall(member) — last element must not be unbound
?- findall(_X, member(_X, [1, 2, 3]), L).
   L = [1, 2, 3].

?- findall(_X, member(_X, [a]), L).
   L = [a].

?- findall(_X, member(_X, [a, b, c, d, e]), L).
   L = [a, b, c, d, e].

% findall through call/1 indirection
?- findall(_X, call(member(_X, [1, 2, 3])), L).
   L = [1, 2, 3].

% nested findall
?- findall(_L, (member(_N, [3, 4, 5]), findall(_X, between(1, _N, _X), _L)), _R), length(_R, Len).
   Len = 3.

% --- sub_atom with bound Sub (string pool optimization) ---

?- sub_atom(abcdefghij, B, _, _, efg).
   B = 4.

?- sub_atom(abcdefghijklmnopqrstuvwxyz, B, _, _, xyz).
   B = 23.

?- sub_atom(abcdefghijklmnopqrstuvwxyz, _, _, _, abc).
   true.

?- sub_atom(abcdefghijklmnopqrstuvwxyz, _, _, _, zzz).
   false.

?- sub_atom(hello, B, L, A, ell).
   B = 1, L = 3, A = 1.

?- sub_atom(hello, 1, 3, _, S).
   S = ell.

% sub_atom returns only first match (builtin limitation)
?- sub_atom(abcabc, B, _, _, abc).
   B = 0.

% --- combined stress ---

?- findall(_X, (between(1, 100, _X), _X mod 10 =:= 0), L).
   L = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100].

?- findall(_X, (between(1, 50, _X), _X mod 7 =:= 0), L).
   L = [7, 14, 21, 28, 35, 42, 49].
