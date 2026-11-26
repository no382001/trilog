% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).

% iso_mod_2_01
?- once(X is mod(5, 2)), X == 1.
   true.

% iso_mod_2_02
?- once(X is mod(0, 3+11)), X == 0.
   true.

% iso_mod_2_03
?- once(X is mod(5,-2)), X == -1.
   true.

% iso_mod_2_04
?- variable(N), _X is mod(77, N).
   error(instantiation_error).

% iso_mod_2_05
?- foo(0, Foo), _X is mod(Foo, 77).
   error(type_error(evaluable,foo/0)).

% iso_mod_2_06
?- G = (_X is mod(7.5, 2)), call(G).
   error(type_error(integer,7.5)).

% iso_mod_2_07
?- G = (_X is mod(7, 0)), call(G).
   error(evaluation_error(zero_divisor)).
