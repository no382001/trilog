% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

list_of(0, _, []).
list_of(N, A, [A|L]) :- N > 0, N1 is N-1, list_of(N1, A, L).

% iso_univ_2_01
?- foo(a,b) =.. [foo,a,b].
   true.

% iso_univ_2_02
?- once(X =.. [foo,a,b]), X == foo(a,b).
   true.

% iso_univ_2_03
?- once(foo(a,b) =.. L), L == [foo,a,b].
   true.

% iso_univ_2_04
?- once(foo(X,b) =.. [foo,a,Y]), (X == a, Y == b).
   true.

% iso_univ_2_05
?- 1 =.. [1].
   true.

% iso_univ_2_06
?- foo(a,b) =.. [foo,b,a].
   false.

% iso_univ_2_07
?- _ =.. _.
   error(instantiation_error).

% iso_univ_2_08
?- _ =.. [foo,a|_].
   error(instantiation_error).

% iso_univ_2_09
?- _ =.. [foo|bar].
   error(type_error(list,[foo|bar])).

% iso_univ_2_10
?- _ =.. [_Foo,bar].
   error(instantiation_error).

% iso_univ_2_11
?- _ =.. [3,1].
   error(type_error(atom,3)).

% iso_univ_2_12
?- _ =.. [1.1,foo].
   error(type_error(atom,1.1)).

% iso_univ_2_13
?- _ =.. [a(b),1].
   error(type_error(atom,a(b))).

% iso_univ_2_14
?- _ =.. 4.
   error(type_error(list,4)).

% iso_univ_2_15
?- f(X) =.. [f,u(X)].
   true.

% sics_univ_2_16
?- _ =.. [f(a)].
   error(type_error(atomic,f(a))).

% sics_univ_2_17
?- _ =.. [].
   error(domain_error(non_empty_list,[])).

% not converted:
% sics_univ_2_18: condition \+ current_prolog_flag(max_arity,unbounded) is false for trilog
