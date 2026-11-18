% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_bitwise_left_shift_2_01
?- lgt_run((once(X is '<<'(16, 2)), X == 64)).
   true.

% iso_bitwise_left_shift_2_02
?- lgt_run((once(X is '<<'(19, 2)), X == 76)).
   true.

% iso_bitwise_left_shift_1_04
?- lgt_run((variable(N), _X is '<<'(77, N))).
   error(instantiation_error).

% iso_bitwise_left_shift_2_05
?- lgt_run((foo(0, Foo), _X is '<<'(Foo, 2))).
   error(type_error(evaluable,foo/0)).

% iso_bitwise_left_shift_2_06
?- lgt_run(_X is '<<'(1.0, 2)).
   error(type_error(integer,1.0)).

% not converted:
% iso_bitwise_left_shift_2_03: marked skipped by Logtalk
