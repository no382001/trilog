% SPDX-FileCopyrightText: 1998-2026 Paulo Moura <pmoura@logtalk.org>
% SPDX-License-Identifier: Apache-2.0

:- consult('test/logtalk/lgtunit.pl').

variable(_).
foo(0, foo).
foo(1, foo(1)).
foo(2, foo(1,2)).

% iso_bitwise_complement_1_01
?- lgt_run((once(X is '\\'('\\'(10))), X == 10)).
   true.

% iso_bitwise_complement_1_02
?- lgt_run((once(X is \(\(10))), X == 10)).
   true.

% iso_bitwise_complement_1_04
?- lgt_run((variable(N), _X is '\\'(N))).
   error(instantiation_error).

% sics_bitwise_complement_1_05
?- lgt_run(_X is '\\'(2.5)).
   error(type_error(integer,2.5)).

% not converted:
% iso_bitwise_complement_1_03: marked skipped by Logtalk
