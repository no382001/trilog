% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).

% iso_round_1_01
?- once(X is round(7.5)), X == 8.
   true.

% iso_round_1_02
?- once(X is round(7.6)), X == 8.
   true.

% iso_round_1_03
?- once(X is round(-0.6)), X == -1.
   true.

% iso_round_1_04
?- variable(N), _X is round(N).
   error(instantiation_error).
