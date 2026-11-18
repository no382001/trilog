% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_xor_2_01
?- lgt_run((once(X is xor(10, 12)), X == 6)).
   true.

% iso_xor_2_02
?- lgt_run((once(X is xor(125, 255)), X == 130)).
   true.

% not converted:
% iso_xor_2_03: marked skipped by Logtalk
