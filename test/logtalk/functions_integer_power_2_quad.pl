% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).
big_float(1.0e+300).
negative(-42).
zero(0).

% iso_integer_power_2_01
?- once(X is 0^0), X == 1.
   true.

% iso_integer_power_2_02
?- once(X is 3^1.0), X == 3.0.
   true.

% iso_integer_power_2_03
?- once(X is 3^3), X == 27.
   true.

% iso_integer_power_2_04
?- once(X is 2^27), X == 134217728.
   true.

% iso_integer_power_2_05
?- once(X is 2^3^3), X == 134217728.
   true.

% iso_integer_power_2_06
?- _X is 2^(-1).
   error(type_error(float,2)).

% iso_integer_power_2_07
?- once(X is 2.0^(-1)), X =~= 0.5.
   true.

% iso_integer_power_2_08
?- once(X is 1^(-1)), X == 1.
   true.

% iso_integer_power_2_09
?- once(X is 2^ -1.5), X =~= 0.353553.
   true.
