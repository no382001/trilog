% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_sqrt_1_01
?- once(X is sqrt(0.0)), X == 0.0.
   true.

% iso_sqrt_1_02
?- once(X is sqrt(1)), X == 1.0.
   true.

% iso_sqrt_1_03
?- once(X is sqrt(1.21)), X =~= 1.1.
   true.

% iso_sqrt_1_04
?- variable(X), _X is sqrt(X).
   error(instantiation_error).

% iso_sqrt_1_05
?- _X is sqrt(-1.0).
   error(evaluation_error(undefined)).

% iso_sqrt_1_06
?- foo(0, Foo), _X is sqrt(Foo).
   error(type_error(evaluable,foo/0)).
