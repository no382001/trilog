% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_functor_3_01
?- lgt_run(functor(foo(a,b,c), foo, 3)).
   true.

% iso_functor_3_02
?- lgt_run((once(functor(foo(a,b,c), X, Y)), X-Y == foo-3)).
   true.

% iso_functor_3_03
?- lgt_run((once(functor(X, foo, 3)), variant(X, foo(_A,_B,_C)))).
   true.

% iso_functor_3_04
?- lgt_run((once(functor(X, foo, 0)), X == foo)).
   true.

% iso_functor_3_05
?- lgt_run((once(functor(mats(A,B), A, B)), A-B == mats-2)).
   true.

% iso_functor_3_06
?- lgt_run(functor(foo(a), foo, 2)).
   false.

% iso_functor_3_07
?- lgt_run(functor(foo(a), fo, 1)).
   false.

% iso_functor_3_08
?- lgt_run((once(functor(1, X, Y)), X-Y == 1-0)).
   true.

% iso_functor_3_09
?- lgt_run((once(functor(X, 1.1, 0)), X == 1.1)).
   true.

% iso_functor_3_10
?- lgt_run(functor([_|_], '.', 2)).
   true.

% iso_functor_3_11
?- lgt_run(functor([], [], 0)).
   true.

% iso_functor_3_12
?- lgt_run((G = functor(_X, _Y, 3), call(G))).
   error(instantiation_error).

% iso_functor_3_13
?- lgt_run((G = functor(_X, foo, _N), call(G))).
   error(instantiation_error).

% iso_functor_3_14
?- lgt_run((G = functor(_X, foo, a), call(G))).
   error(type_error(integer,a)).

% iso_functor_3_15
?- lgt_run((G = functor(_F, 1.5, 1), call(G))).
   error(type_error(atom,1.5)).

% iso_functor_3_16
?- lgt_run((G = functor(_F, foo(a), 1), call(G))).
   error(type_error(atomic,foo(a))).

% iso_functor_3_18
?- lgt_run((G = functor(_T, foo, -1), call(G))).
   error(domain_error(not_less_than_zero,-1)).

% not converted:
% iso_functor_3_17: condition \+ current_prolog_flag(max_arity,unbounded) is false for trilog
