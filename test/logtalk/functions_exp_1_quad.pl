% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).
large(123456789).

% iso_exp_1_01
?- once(X is exp(0.0)), X == 1.0.
   true.

% iso_exp_1_02
?- once(X is exp(1.0)), X =~= 2.71828.
   true.

% iso_exp_1_03
?- variable(X), _X is exp(X).
   error(instantiation_error).

% iso_exp_1_04
?- once(X is exp(0)), X == 1.0.
   true.

% iso_exp_1_05
?- foo(0, Foo), _X is exp(Foo).
   error(type_error(evaluable,foo/0)).
