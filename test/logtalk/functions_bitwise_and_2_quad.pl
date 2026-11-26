% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_bitwise_and_2_01
?- once(X is '/\\'(10, 12)), X == 8.
   true.

% iso_bitwise_and_2_02
?- once(X is /\(10, 12)), X == 8.
   true.

% iso_bitwise_and_2_03
?- once(X is '/\\'(17*256+125, 255)), X == 125.
   true.

% iso_bitwise_and_2_05
?- variable(N), _X is '/\\'(77, N).
   error(instantiation_error).

% iso_bitwise_and_2_06
?- foo(0, Foo), _X is '/\\'(Foo, 2).
   error(type_error(evaluable,foo/0)).

% sics_bitwise_and_2_07
?- _X is '/\\'(1.0, 2).
   error(type_error(integer,1.0)).

% not converted:
% iso_bitwise_and_2_04: marked skipped by Logtalk
