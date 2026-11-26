% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_bitwise_or_2_01
?- once(X is '\\/'(10, 12)), X == 14.
   true.

% iso_bitwise_or_2_02
?- once(X is \/(10, 12)), X == 14.
   true.

% iso_bitwise_or_2_03
?- once(X is '\\/'(125, 255)), X == 255.
   true.

% iso_bitwise_or_2_05
?- variable(N), _X is '\\/'(77, N).
   error(instantiation_error).

% iso_bitwise_or_2_06
?- foo(0, Foo), _X is '\\/'(Foo, 2).
   error(type_error(evaluable,foo/0)).

% sics_bitwise_or_2_07
?- _X is '\\/'(10.0, 12).
   error(type_error(integer,10.0)).

% not converted:
% iso_bitwise_or_2_04: marked skipped by Logtalk
