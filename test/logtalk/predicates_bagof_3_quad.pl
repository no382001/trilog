% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

a(1, f(_)).
a(2, f(_)).
b(1, 1).
b(1, 1).
b(1, 2).
b(2, 1).
b(2, 2).
b(2, 2).
a(1).
a(2).
a(3).
c(2, b, 'B').
c(1, a, 'A').
c(3, c, 'C').
f(_, 1, a).
f(_, 2, b).
v1(_).
v1(_).
v1(_).
v2(_, _).
v2(_, _).
v2(_, _).
v3(A, A).
v3(A, A).
v3(_, _).
v4(A, _, A).
v4(A, A, _).
v4(_, A, A).
v5(A, _, A).
v5(A, A, _).
v5(_, A, A).
v5(A, _, A).
v6(A, B, B, A).
v6(A, _, _, A).
v6(_, B, B, _).
v6(A, B, B, A).
bagof_3_member(X, [X| _]).
bagof_3_member(X, [_| L]) :- bagof_3_member(X, L).
one(1).

% iso_bagof_3_01
?- once(bagof(X, (X=1;X=2), S)), S == [1,2].
   true.

% iso_bagof_3_02
?- once(bagof(X, (X=1;X=2), X)), X == [1,2].
   true.

% iso_bagof_3_03
?- once(bagof(X, (X=Y;X=Z), S)), S == [Y, Z].
   true.

% iso_bagof_3_04
?- bagof(_X, fail, _S).
   false.

% iso_bagof_3_05
?- once(findall(L-Y,bagof(1,(Y=1;Y=2),L),LL)), (LL == [[1]-1, [1]-2] ; LL == [[1]-2, [1]-1]).
   true.

% iso_bagof_3_06
?- once(bagof(f(X,Y), (X=a;Y=b), L)), variant(L, [f(a, _), f(_, b)]).
   true.

% iso_bagof_3_07
?- once(bagof(X, Y^((X=1,Y=1);(X=2,Y=2)), S)), S == [1, 2].
   true.

% iso_bagof_3_08
?- once(bagof(X, Y^((X=1;Y=1);(X=2,Y=2)), S)), variant(S, [1, _, 2]).
   true.

% iso_bagof_3_09
?- once((set_prolog_flag(unknown, fail), bagof(X,(Y^(X=1;Y=1);X=3),S))), S == [3].
   true.

% iso_bagof_3_10
?- once(findall(S-Y,bagof(X,(X=Y;X=_Z;Y=1),S),LL)), variant(LL, [[A,_]-A, [_]-1]).
   true.

% iso_bagof_3_11
?- once((bagof(X, a(X,Y), L), assertion(L == [1, 2]))), variant(Y, f(_)).
   true.

% iso_bagof_3_12
?- once(findall(L-Y,bagof(X,b(X,Y),L),LL)), LL == [[1, 1, 2]-1, [1, 2, 2]-2].
   true.

% iso_bagof_3_13
?- bagof(_X, _Y^_Z, _L).
   error(instantiation_error).

% iso_bagof_3_14
?- one(One), bagof(_X, One, _L).
   error(type_error(callable,1))
|  error(type_error(callable,':'(user,1))).

% iso_bagof_3_15
?- once(findall(L,bagof(X, a(X), L),LL)), subsumes_term([_], LL).
   true.

% iso_bagof_3_16
?- once(bagof(X, a(X), _)), var(X).
   true.

% iso_bagof_3_17
?- forall(bagof(X, Y^c(X, Y, _), _),(var(X), var(Y))).
   true.
