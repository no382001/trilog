% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).

% iso_abs_1_01
?- once(X is abs(7)), X == 7.
   true.

% iso_abs_1_02
?- once(X is abs(3-11)), X == 8.
   true.

% iso_abs_1_03
?- once(X is abs(3.2-11.0)), X == 7.8.
   true.

% iso_abs_1_04
?- variable(N), _X is abs(N).
   error(instantiation_error).

% iso_abs_1_05
?- foo(0, Foo), _X is abs(Foo).
   error(type_error(evaluable,foo/0)).
