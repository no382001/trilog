% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_log_1_01
?- once(X is log(1.0)), X == 0.0.
   true.

% iso_log_1_02
?- once(E is log(2.71828)), E =~= 1.0.
   true.

% iso_log_1_03
?- variable(X), _X is log(X).
   error(instantiation_error).

% iso_log_1_04
?- _X is log(0).
   error(evaluation_error(_)).

% iso_log_1_05
?- foo(0, Foo), _X is log(Foo).
   error(type_error(evaluable,foo/0)).

% iso_log_1_06
?- _X is log(0.0).
   error(evaluation_error(_)).
