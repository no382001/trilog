% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).

% iso_floor_1_01
?- lgt_run((once(X is floor(7.4)), X == 7)).
   true.

% iso_floor_1_02
?- lgt_run((once(X is floor(-0.4)), X == -1)).
   true.
