% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).
negative(-1).
big_float(1.0e+300).
small_float(1.0e-300).

% iso_power_2_01
?- once(X is '**'(5, 3)), X =~= 125.0.
   true.

% iso_power_2_02
?- once(X is '**'(-5.0, 3)), X =~= -125.0.
   true.

% iso_power_2_03
?- once(X is '**'(5, -1)), X =~= 0.2.
   true.

% iso_power_2_04
?- variable(N), _X is '**'(77, N).
   error(instantiation_error).

% iso_power_2_05
?- foo(0, Foo), _X is '**'(Foo, 3).
   error(type_error(evaluable,foo/0)).

% iso_power_2_06
?- once(X is '**'(5, 3.0)), X =~= 125.0.
   true.

% iso_power_2_07
?- once(X is '**'(0, 0.0)), X =~= 1.0.
   true.

% iso_power_2_09
?- foo(0, Foo), _X is '**'(5, Foo).
   error(type_error(evaluable,foo/0)).

% iso_power_2_10
?- foo(1, Foo), _X is '**'(Foo, 3).
   error(type_error(evaluable,foo/1)).

% iso_power_2_11
?- foo(1, Foo), _X is '**'(5, Foo).
   error(type_error(evaluable,foo/1)).

% iso_power_2_12
?- foo(2, Foo), _X is '**'(Foo, 3).
   error(type_error(evaluable,foo/2)).

% iso_power_2_13
?- foo(2, Foo), _X is '**'(5, Foo).
   error(type_error(evaluable,foo/2)).
