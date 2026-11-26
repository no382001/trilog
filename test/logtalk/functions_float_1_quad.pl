% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).

% iso_float_1_function_01
?- once(X is float(7)), X == 7.0.
   true.

% iso_float_1_function_02
?- once(X is float(7.3)), X == 7.3.
   true.

% iso_float_1_function_03
?- once(X is float(5//3)), X == 1.0.
   true.

% iso_float_1_function_04
?- variable(N), _X is float(N).
   error(instantiation_error).

% iso_float_1_function_05
?- foo(0, Foo), _X is float(Foo).
   error(type_error(evaluable,foo/0)).

% iso_float_1_function_06
?- foo(1, Foo), _X is float(Foo).
   error(type_error(evaluable,foo/1)).
