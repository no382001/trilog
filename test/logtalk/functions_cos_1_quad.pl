% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_cos_1_01
?- once(X is cos(0.0)), X == 1.0.
   true.

% iso_cos_1_02
?- variable(N), _X is cos(N).
   error(instantiation_error).

% iso_cos_1_03
?- once(X is cos(0)), X == 1.0.
   true.

% iso_cos_1_04
?- foo(0, Foo), _X is cos(Foo).
   error(type_error(evaluable,foo/0)).

% iso_cos_1_05
?- once((PI is atan(1.0)*4, X is cos(PI/2.0))), X =~= 0.0.
   true.
