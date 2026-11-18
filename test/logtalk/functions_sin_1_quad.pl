% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_sin_1_01
?- lgt_run((once(X is sin(0.0)), X == 0.0)).
   true.

% iso_sin_1_02
?- lgt_run((variable(N), _X is sin(N))).
   error(instantiation_error).

% iso_sin_1_03
?- lgt_run((once(X is sin(0)), X == 0.0)).
   true.

% iso_sin_1_04
?- lgt_run((foo(0, Foo), _X is sin(Foo))).
   error(type_error(evaluable,foo/0)).

% iso_sin_1_05
?- lgt_run((once((PI is atan(1.0)*4, X is sin(PI/2.0))), X =~= 1.0)).
   true.
