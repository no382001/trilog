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
d(1, 1).
d(1, 2).
d(1, 1).
d(2, 2).
d(2, 1).
d(2, 2).
c(2, b, 'B').
c(1, a, 'A').
c(3, c, 'C').
a(foo(_), p/0, 1).
a(baz(_), x/1, 2).
a(foo(_), p/0, 2).
a(bar(_), s/0, 2).
a(foo(_), p/0, 3).
a(foo(_), q/1, 1).
a(foo(_), r/2, 2).
a(bar(_), s/0, 1).
a(bar(_), s/0, 3).
a(foo(_), q/1, 2).
a(foo(_), q/1, 3).
a(foo(_), r/2, 1).
a(bar(_), t/1, 1).
a(bar(_), t/1, 2).
a(bar(_), u/2, 2).
a(bar(_), u/2, 3).
a(baz(_), v/0, 1).
a(baz(_), v/0, 2).
a(bar(_), t/1, 3).
a(bar(_), u/2, 1).
a(baz(_), v/0, 3).
a(baz(_), x/1, 1).
a(foo(_), r/2, 3).
a(baz(_), x/1, 3).
a(baz(_), z/2, 1).
a(baz(_), z/2, 2).
a(baz(_), z/2, 3).
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
setof_3_member(X, [X| _]).
setof_3_member(X, [_| L]) :- setof_3_member(X, L).

% iso_setof_3_01
?- once(setof(X, (X=1;X=2), S)), S == [1,2].
   true.

% iso_setof_3_02
?- once(setof(X, (X=1;X=2), X)), X == [1,2].
   true.

% iso_setof_3_03
?- once(setof(X, (X=2;X=1), S)), S == [1,2].
   true.

% iso_setof_3_04
?- once(setof(X, (X=2;X=2), S)), S == [2].
   true.

% iso_setof_3_05
?- once(setof(X, (X=Y;X=Z), S)), (S == [Z,Y] ; S == [Y,Z]).
   true.

% iso_setof_3_06
?- setof(_X, fail, _S).
   false.

% iso_setof_3_07
?- once(findall(L-Y,setof(1,(Y=1;Y=2),L),LL)), LL == [[1]-1, [1]-2].
   true.

% iso_setof_3_08
?- once(setof(f(X,Y), (X=a;Y=b), L)), variant(L, [f(_,b), f(a,_)]).
   true.

% iso_setof_3_09
?- once(setof(X, Y^((X=1,Y=1);(X=2,Y=2)), S)), S == [1, 2].
   true.

% iso_setof_3_10
?- once(setof(X, Y^((X=1;Y=1);(X=2,Y=2)), S)), variant(S, [_, 1, 2]).
   true.

% iso_setof_3_11
?- once((set_prolog_flag(unknown, fail), setof(X, (Y^(X=1;Y=2);X=3), S))), S == [3].
   true.

% iso_setof_3_12
?- findall(S-Y,setof(X,(X=Y;X=_Z;Y=1),S),LL), (variant(LL, [[A,_]-A, [_]-1]) -> true ; variant(LL, [[_,A]-A, [_]-1])).
   true.

% iso_setof_3_13
?- once((setof(X, a(X,Y), L), assertion(L == [1, 2]))), variant(Y, f(_)).
   true.

% iso_setof_3_14
?- setof(X, setof_3_member(X,[f(U,b),f(V,c)]), L), (variant(L, [f(U,b),f(V,c)]) -> true ; variant(L, [f(V,c),f(U,b)])).
   true.

% iso_setof_3_15
?- setof(X, setof_3_member(X,[f(U,b),f(V,c)]), [f(a,c),f(a,b)]) -> U == a, V == a ; true.
   true.

% iso_setof_3_16
?- once(setof(X, setof_3_member(X,[f(b,U),f(c,V)]), [f(b,a),f(c,a)])), (U == a, V == a).
   true.

% iso_setof_3_17
?- setof(X, setof_3_member(X,[V,U,f(U),f(V)]), L) -> variant(L, [U, V, f(U), f(V)]) ; variant(L, [V, U, f(V), f(U)]).
   true.

% iso_setof_3_18
?- setof(X, setof_3_member(X,[V,U,f(U),f(V)]), [a,b,f(a),f(b)]), ((U == a, V == b) -> true ; U == b, V == a).
   true.

% iso_setof_3_19
?- setof(X, setof_3_member(X,[V,U,f(U),f(V)]), [a,b,f(b),f(a)]).
   false.

% iso_setof_3_20
?- setof(X, exists(U,V)^setof_3_member(X,[V,U,f(U),f(V)]), [a,b,f(a),f(b)]).
   true.

% iso_setof_3_21
?- once(findall(L-Y,setof(X,b(X,Y),L),LL)), LL == [[1, 2]-1, [1, 2]-2].
   true.

% iso_setof_3_22
?- once(setof(X-Xs, Y^setof(Y,b(X,Y),Xs), L)), L == [1-[1,2], 2-[1,2]].
   true.

% iso_setof_3_23
?- setof(X-Xs, setof(Y,b(X,Y),Xs), L), assertion(var(Y)), assertion(L == [1-[1,2], 2-[1,2]]).
   true.

% iso_setof_3_24
?- setof(X-Xs, bagof(Y,d(X,Y),Xs), L), assertion(var(Y)), assertion(L == [1-[1,2,1], 2-[2,1,2]]).
   true.

% eddbali_setof_3_25
?- setof(f(X,Y),X=Y,[f(g(Z),Z)]).
   true.

% eddbali_setof_3_26
?- setof(X, X^(true; 4), _L).
   error(type_error(callable,(true;4)))
|  error(type_error(callable,':'(user,(true;4))))
|  error(type_error(callable,4))
|  error(type_error(callable,':'(user,4))).

% sics_setof_3_27
?- setof(_X, A^A^1, _L).
   error(type_error(callable,1))
|  error(type_error(callable,':'(user,1))).

% sics_setof_3_28
?- once(setof(X, X=1, [1|A])), A == [].
   true.

% sics_setof_3_29
?- setof(X, X=1, [A|1]).
   error(type_error(list,[A|1])).
