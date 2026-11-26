% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

% iso_arg_3_01
?- arg(1, foo(a,b), a).
   true.

% iso_arg_3_02
?- once(arg(1, foo(a,b), X)), X == a.
   true.

% iso_arg_3_03
?- once(arg(1, foo(X,b), a)), X == a.
   true.

% iso_arg_3_04
?- once(arg(1, foo(X,b), Y)), Y == X.
   true.

% iso_arg_3_05
?- arg(1, foo(a,b), b).
   false.

% iso_arg_3_06
?- arg(0, foo(a,b), foo).
   false.

% iso_arg_3_07
?- arg(3, foo(3,4), _).
   false.

% iso_arg_3_08
?- G = arg(_, foo(a,b), a), call(G).
   error(instantiation_error).

% iso_arg_3_09
?- G = arg(1, _, a), call(G).
   error(instantiation_error).

% iso_arg_3_10
?- G = arg(0, atom, _), call(G).
   error(type_error(compound,atom)).

% iso_arg_3_11
?- G = arg(0, 3, _), call(G).
   error(type_error(compound,3)).

% iso_arg_3_12
?- arg(1, foo(X), u(X)).
   true.

% eddbali_arg_3_13
?- G = arg(-3, foo(a,b), _A), call(G).
   error(domain_error(not_less_than_zero,-3)).

% eddbali_arg_3_14
?- G = arg(a, foo(a,b), _X), call(G).
   error(type_error(integer,a)).

% eddbali_arg_3_15
?- once(arg(2, foo(a,f(X,b),c), f(a,Y))), X-Y == a-b.
   true.

% sics_arg_3_16
?- G = arg(1, 3, _A), call(G).
   error(type_error(compound,3)).
